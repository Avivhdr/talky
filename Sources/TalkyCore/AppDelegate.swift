import AppKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configStore = ConfigStore()
    private let pipeStore = PipeStore()
    private lazy var controller = Controller(configStore: configStore, pipeStore: pipeStore)
    private lazy var settings = SettingsWindowController(configStore: configStore, pipeStore: pipeStore)
    private let keyMonitor = KeyMonitor()
    private var statusItem: NSStatusItem!
    private var watcher: DirectoryWatcher?
    private var tapRetry: Timer?
    private var cancellables = Set<AnyCancellable>()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensure()
        setUpStatusItem()

        keyMonitor.delegate = controller
        controller.onPhaseChange = { [weak self] _ in self?.updateIcon() }

        configStore.$config
            .removeDuplicates()
            .sink { [weak self] config in self?.apply(config) }
            .store(in: &cancellables)

        watcher = DirectoryWatcher(url: Paths.configDir) { [weak self] in
            MainActor.assumeIsolated {
                self?.configStore.load()
                self?.pipeStore.load()
            }
        }

        Task {
            _ = await AudioRecorder.requestPermission()
            startKeyMonitor()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        let local = controller.transcription.local
        let done = DispatchSemaphore(value: 0)
        Task.detached { await local.stopServer(); done.signal() }
        _ = done.wait(timeout: .now() + 1)
    }

    private func apply(_ config: Config) {
        keyMonitor.mainSpec = HotkeySpec.parse(config.hotkey)
        keyMonitor.transformSpec = HotkeySpec.parse(config.transformHotkey)
        keyMonitor.resetState()
        controller.transcription.prewarm(config.transcription)
        updateIcon()
    }

    /// The event tap needs Accessibility. Prompt once, then keep retrying until the user grants it.
    private func startKeyMonitor() {
        if keyMonitor.start() { return }
        Permissions.promptAccessibility()
        Permissions.promptInputMonitoring()
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

        if !keyMonitor.isRunning {
            addInfo(menu, "Waiting for Accessibility permission…")
        }
        if let err = configStore.loadError ?? pipeStore.loadError { addInfo(menu, err) }
        let key = HotkeySpec.label(c.hotkey)
        addInfo(menu, "Hold \(key) to dictate, double-tap for hands-free")
        addInfo(menu, "Tap \(HotkeySpec.label(c.transformHotkey)) on selected text to transform")
        let backend = (try? TranscriptionService.plan(c.transcription).label) ?? "Transcription misconfigured"
        let pipe = c.llm.enabled ? (pipeStore.defaultPipe?.name ?? "Raw") : "Raw"
        addInfo(menu, "\(backend) · pipe: \(pipe)")
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = LoginItem.isEnabled ? .on : .off
        login.target = self
        menu.addItem(login)
        addAction(menu, "Settings…", #selector(openSettings), ",")
        addAction(menu, "Pipes…", #selector(openPipes), "")
        addAction(menu, "Open Config Folder", #selector(openConfigFolder), "")
        addAction(menu, "Reload Config", #selector(reloadConfig), "")
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
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled) }
    @objc private func openSettings() { settings.show() }
    @objc private func openPipes() { settings.show(tab: .pipes) }
    @objc private func openConfigFolder() { NSWorkspace.shared.open(Paths.configDir) }
    @objc private func reloadConfig() { configStore.load(); pipeStore.load() }
    @objc private func quit() { NSApp.terminate(nil) }
}
