import AppKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private let pipeStore = PipeStore()
    private lazy var controller = Controller(configStore: configStore, pipeStore: pipeStore)
    private lazy var settings = SettingsWindowController(configStore: configStore, pipeStore: pipeStore)
    private lazy var onboarding = OnboardingWindowController(
        transformKey: HotkeySpec.label(configStore.config.transformHotkey)
    ) { [weak self] completed in self?.onboardingEnded(completed: completed) }
    private let keyMonitor = KeyMonitor()
    private var statusItem: NSStatusItem!
    private var watcher: DirectoryWatcher?
    private var tapRetry: Timer?
    private var cancellables = Set<AnyCancellable>()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensure()
        setUpMainMenu()
        setUpStatusItem()

        keyMonitor.delegate = controller
        controller.onPhaseChange = { [weak self] _ in self?.updateIcon() }
        // During setup the onboarding window has the missing step, so show it rather than Settings.
        controller.onNeedsSetup = { [weak self] in
            guard let self else { return }
            if OnboardingWindowController.isDone { settings.show() } else { onboarding.show() }
        }

        configStore.$config
            .removeDuplicates()
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)

        // Load the model into memory as soon as its download finishes.
        SpeechModel.shared.$state
            .removeDuplicates()
            .filter { $0 == .ready }
            .sink { [weak self] _ in
                guard let self else { return }
                controller.transcription.prewarm(configStore.config.transcription)
            }
            .store(in: &cancellables)

        watcher = DirectoryWatcher(url: Paths.configDir) { [weak self] in
            MainActor.assumeIsolated {
                self?.configStore.load()
                self?.pipeStore.load()
            }
        }

        // Onboarding asks for permissions one at a time, so skip the launch-time prompts.
        if OnboardingWindowController.isDone {
            Task {
                _ = await AudioRecorder.requestPermission()
                startKeyMonitor()
            }
        } else {
            startKeyMonitor(prompt: false)
            onboarding.show()
        }
    }

    private func apply(_ config: Config) {
        keyMonitor.mainSpec = HotkeySpec.parse(config.hotkey)
        keyMonitor.transformSpec = HotkeySpec.parse(config.transformHotkey)
        keyMonitor.resetState()
        SpeechModel.shared.use(config.transcription.model)
        SpeechModel.shared.refresh()
        controller.transcription.prewarm(config.transcription)
        updateIcon()
    }

    /// After the last step, Settings opens on Pipes, where the user can write their own.
    /// If Talky can't dictate yet, it opens on General instead, where the missing permission or model is.
    /// A window closed early opens nothing, and macOS asks for Accessibility if it is still off.
    private func onboardingEnded(completed: Bool) {
        startKeyMonitor(prompt: !completed)
        guard completed else { return }
        let model = SpeechModel.shared
        let canDictate = Permissions.accessibility && Permissions.microphone && (model.isReady || model.isDownloading)
        settings.show(tab: canDictate ? .pipes : .general)
    }

    /// The event tap needs Accessibility. Prompt once, then keep retrying until the user grants it.
    private func startKeyMonitor(prompt: Bool = true) {
        if keyMonitor.start() { return updateIcon() }
        if prompt { Permissions.promptAccessibility() }
        tapRetry?.invalidate()
        tapRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return t.invalidate() }
                if self.keyMonitor.start() {
                    t.invalidate()
                    self.updateIcon()
                }
            }
        }
        updateIcon()
    }

    // MARK: Menu bar

    /// Talky shows no menu bar, but text fields only get Cmd-C, Cmd-V and the other edit keys
    /// through the key equivalents of a main menu.
    private func setUpMainMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "Talky", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        if !configStore.config.enabled || !keyMonitor.isRunning {
            symbol = "mic.slash"
        } else {
            switch controller.phase {
            case .recording: symbol = "waveform.circle.fill"
            case .processing: symbol = "ellipsis.circle"
            default: symbol = "waveform"
            }
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Talky")
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let c = configStore.config

        let toggle = NSMenuItem(title: "Talky On", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.state = c.enabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        var notes = false
        if !keyMonitor.isRunning {
            addInfo(menu, "Waiting for Accessibility permission…")
            notes = true
        }
        switch SpeechModel.shared.state {
        case .ready: break
        case .downloading(let received, let total):
            let percent = total > 0 ? " \(Int(Double(received) / Double(total) * 100))%" : ""
            addInfo(menu, "Downloading the speech model…\(percent)")
            notes = true
        case .missing, .failed:
            addAction(menu, "Download the Speech Model", #selector(downloadSpeechModel), "")
            notes = true
        }
        if let err = configStore.loadError ?? pipeStore.loadError {
            addInfo(menu, err)
            notes = true
        }
        if notes { menu.addItem(.separator()) }

        addAction(menu, "Settings…", #selector(openSettings), ",")
        if Updater.shared.isAvailable { addAction(menu, "Check for Updates…", #selector(checkForUpdates), "") }
        menu.addItem(.separator())
        addAction(menu, "Quit Talky", #selector(quit), "q")
    }

    private func addInfo(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addAction(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleEnabled() { configStore.config.enabled.toggle() }
    @objc private func openSettings() { settings.show() }
    @objc private func downloadSpeechModel() { SpeechModel.shared.download() }
    @objc private func checkForUpdates() { Updater.shared.checkNow() }
    @objc private func quit() { NSApp.terminate(nil) }
}
