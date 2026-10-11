import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private let configStore: ConfigStore
    private let pipeStore: PipeStore
    private let tabState = SettingsTabState()

    public init(configStore: ConfigStore, pipeStore: PipeStore) {
        self.configStore = configStore
        self.pipeStore = pipeStore
    }

    public func show(tab: SettingsTab = .general) {
        tabState.tab = tab
        if window == nil {
            let view = SettingsView(config: configStore, pipes: pipeStore, tabState: tabState)
            // About twice the area of the old 820x600 window, shrunk to fit smaller screens.
            let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            let size = NSSize(width: min(1200, visible.width - 40), height: min(860, visible.height - 40))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Talky Settings"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("TalkySettingsLarge")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

public enum SettingsTab: Hashable { case general, pipes }

/// Shared layout values so both Settings pages put their header band and content in the same column.
enum SettingsLayout {
    static let margin: CGFloat = 20
}

@MainActor
final class SettingsTabState: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var config: ConfigStore
    @ObservedObject var pipes: PipeStore
    @ObservedObject var tabState: SettingsTabState

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                sidebarRow(.general, "General", "gearshape.fill", Color.gray)
                sidebarRow(.pipes, "Pipes", "line.3.horizontal.decrease", Theme.violet)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    TalkyMark(size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Talky").font(.headline)
                        Text("Version \(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch tabState.tab {
            case .general: GeneralTab(store: config)
            case .pipes: PipesTab(store: pipes, config: config)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
    }

    private var selection: Binding<SettingsTab?> {
        Binding(get: { tabState.tab }, set: { if let tab = $0 { tabState.tab = tab } })
    }

    private func sidebarRow(_ tab: SettingsTab, _ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
        }
        .tag(tab)
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var speechModel = SpeechModel.shared
    @ObservedObject private var anthropicKey = AnthropicKeyEntry.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var permissions = PermissionState()
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// Suggestions in the shortcut menus. The first one is the default.
    static let mainHotkeys = ["fn", "right_option", "right_command", "right_control", "ctrl+opt+space", "f13"]
    static let transformHotkeys = ["right_option", "right_command", "right_control", "ctrl+opt+t", "f14"]
    static let languages = [("auto", "Detect automatically"), ("en", "English"), ("he", "Hebrew"), ("es", "Spanish"),
                            ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"),
                            ("ru", "Russian"), ("ar", "Arabic"), ("zh", "Chinese"), ("ja", "Japanese")]
    static let models = [("claude-haiku-4-5-20251001", "Haiku 4.5 (fastest)"), ("claude-sonnet-5-5", "Sonnet 5.5"),
                         ("claude-opus-5-5", "Opus 5.5 (slowest)")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SettingsHero(title: "General",
                             subtitle: "Hold \(HotkeySpec.label(store.config.hotkey)) to talk. Talky types wherever your cursor is.") {
                    PillPreview(label: "Hold \(HotkeySpec.label(store.config.hotkey))", pipes: [], selectedId: nil)
                }
                if let err = store.loadError {
                    Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                if !permissions.allGranted {
                    SettingsGroup("Permissions", footer: "Talky needs both. Allow opens the right pane in System Settings.") {
                        PermissionRows(state: permissions).padding(.vertical, 8)
                    }
                }
                SettingsGroup("Dictation") {
                    SettingsRow("Dictate") {
                        HotkeyField(title: "Dictate", hotkey: $store.config.hotkey, suggestions: Self.mainHotkeys,
                                    otherTitle: "Transform selected text", otherHotkey: store.config.transformHotkey)
                    }
                    Divider()
                    SettingsRow("Language") { choicePicker("Language", $store.config.transcription.language, Self.languages) }
                    Divider()
                    SettingsRow("Launch at login") {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .toggleStyle(.switch).labelsHidden()
                            .onChange(of: launchAtLogin) { _, on in LoginItem.set(on); launchAtLogin = LoginItem.isEnabled }
                    }
                }
                SettingsGroup("Speech model", footer: "Talky turns speech into text on this Mac. Your audio never leaves it.") {
                    SpeechModelRow(model: speechModel).padding(.vertical, 8)
                }
                claude
                about
            }
            .padding(SettingsLayout.margin)
        }
        .onReceive(refresh) { _ in permissions = PermissionState() }
    }

    /// Everything that needs the Anthropic key: pipes on dictation and the transform hotkey.
    var claude: some View {
        let hasKey = AnthropicClient.apiKey != nil
        let on = hasKey && store.config.llm.enabled
        return SettingsGroup("Claude", footer: "Pipes send the transcript to Anthropic to rewrite it, never your audio. "
                                 + "Without a key, Talky types exactly what you said. The key stays on this Mac in ~/.config/talky/.env.") {
            SettingsRow("Anthropic API key") {
                AnthropicKeyField(entry: anthropicKey).frame(maxWidth: 420)
            }
            HStack {
                Spacer(minLength: 16)
                AnthropicKeyStatus(entry: anthropicKey).frame(maxWidth: 420)
            }
            .padding(.bottom, 10)
            Divider()
            SettingsRow("Rewrite dictation with pipes") {
                Toggle("Rewrite dictation with pipes", isOn: $store.config.llm.enabled)
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!hasKey)
            }
            Divider()
            SettingsRow("Model") {
                choicePicker("Model", $store.config.llm.model, Self.models).disabled(!on)
            }
            Divider()
            SettingsRow("Transform selected text") {
                HotkeyField(title: "Transform selected text", hotkey: $store.config.transformHotkey,
                            suggestions: Self.transformHotkeys, otherTitle: "Dictate", otherHotkey: store.config.hotkey)
                    .disabled(!on)
            }
        }
    }

    var about: some View {
        SettingsGroup("About") {
            HStack(spacing: 12) {
                TalkyMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Talky").font(.headline)
                    Text("Version \(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if updater.isAvailable { Button("Check for Updates…") { updater.checkNow() } }
            }
            .padding(.vertical, 10)
            if updater.isAvailable {
                Divider()
                SettingsRow("Check for updates automatically") {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            Divider()
            SettingsRow("Removes Talky, its permissions and its files.", secondary: true) {
                Button("Uninstall Talky…", role: .destructive) { Uninstaller.confirmAndRun() }
            }
        }
    }

    /// A picker over fixed choices that still shows a hand-edited value from config.json.
    func choicePicker(_ title: String, _ binding: Binding<String>, _ options: [(String, String)]) -> some View {
        Picker(title, selection: binding) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            if !options.contains(where: { $0.0 == binding.wrappedValue }) {
                Text(binding.wrappedValue).tag(binding.wrappedValue)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

/// A titled panel of rows. General and Pipes share this panel language and one column.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One settings row: a label on the left, its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var secondary = false
    @ViewBuilder var control: Control

    init(_ title: String, secondary: Bool = false, @ViewBuilder control: () -> Control) {
        self.title = title
        self.secondary = secondary
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title).foregroundStyle(secondary ? .secondary : .primary)
            Spacer(minLength: 16)
            control
        }
        .frame(minHeight: 30)
        .padding(.vertical, 8)
    }
}

/// The Anthropic key field and its Test Key button. Shared by Settings and onboarding;
/// AnthropicKeyStatus shows what Anthropic said about the key.
struct AnthropicKeyField: View {
    @ObservedObject var entry: AnthropicKeyEntry
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            SecureField("Anthropic API key", text: $entry.draft, prompt: Text("Paste your key"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { entry.test() }
            Button("Test Key") { entry.test() }
                .disabled(!entry.canTest)
        }
        // A key nobody has tested yet: the saved one when the field appears, a typed one when the user leaves it.
        .onAppear { entry.testIfNeeded() }
        .onChange(of: focused) { _, isFocused in if !isFocused { entry.testIfNeeded() } }
        .onDisappear { entry.testIfNeeded() }
    }
}

/// What Anthropic said about the key, or where to get one.
struct AnthropicKeyStatus: View {
    static let consoleURL = URL(string: "https://console.anthropic.com/settings/keys")!

    @ObservedObject var entry: AnthropicKeyEntry
    var secondary: Color = .secondary
    var link: Color = .accentColor

    var body: some View {
        Group {
            switch entry.status {
            case .empty:
                Link(destination: Self.consoleURL) {
                    Text("Get a key in the Anthropic Console \(Image(systemName: "arrow.up.right"))")
                }
                .tint(link)
            case .untested:
                Text("Talky saves the key after Anthropic accepts it.").foregroundStyle(secondary)
            case .testing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Testing the key with Anthropic…")
                }
                .foregroundStyle(secondary)
            case .works:
                Label("The key works and is saved.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .rejected(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .unreachable(let reason):
                let reason = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
                Label("Talky couldn't reach Anthropic to test the key (\(reason)). Talky saved the key anyway.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Notification.Name {
    static let talkyKeysChanged = Notification.Name("TalkyKeysChanged")
}

/// The speech model's name, size and download state, with the action that fits. Shared by Settings and onboarding.
struct SpeechModelRow: View {
    @ObservedObject var model: SpeechModel
    var secondary: Color = .secondary
    /// Onboarding moves the download into its footer button, so the row only reports.
    var showsActions = true
    var showsIcon = false

    var body: some View {
        HStack(spacing: 12) {
            if showsIcon {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.indigo.gradient))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName)
                Text(detail).font(.caption).monospacedDigit()
                    .foregroundStyle(isFailed ? Color.orange : secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    private var isFailed: Bool {
        if case .failed = model.state { return true }
        return false
    }

    private var detail: String {
        switch model.state {
        case .ready:
            return "Downloaded. Works offline."
        case .missing:
            return model.expectedSize.map { "\(Self.bytes($0)), one-time download" } ?? "One-time download"
        case .downloading(let received, let total):
            return total > 0 ? "\(Self.bytes(received)) of \(Self.bytes(total))" : Self.bytes(received)
        case .failed(let message):
            return message
        }
    }

    @ViewBuilder private var trailing: some View {
        switch model.state {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon).font(.callout).foregroundStyle(.green)
        case .downloading(let received, let total):
            HStack(spacing: 8) {
                ProgressView(value: total > 0 ? Double(received) / Double(total) : 0)
                    .frame(width: 120)
                    .accessibilityLabel("Download progress")
                if showsActions {
                    Button { model.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(secondary)
                        .help("Stop the download")
                        .accessibilityLabel("Stop the download")
                }
            }
        case .missing:
            if showsActions { Button("Download") { model.download() } }
        case .failed:
            if showsActions { Button("Try Again") { model.download() } }
        }
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}

/// Permission status with a button for each missing one. Shared by Settings and onboarding.
struct PermissionRows: View {
    let state: PermissionState

    var body: some View {
        row("Microphone", "To hear you.", "mic.fill", .orange, state.mic) { Permissions.requestMicrophone() }
        // Talky is already in this list: its key monitor tries to start at launch, and that adds it.
        // So Allow only opens System Settings, without the system prompt on top of it.
        row("Accessibility", "To notice the Talky keys and type for you.", "accessibility", .blue, state.accessibility) {
            Permissions.openSettings("Privacy_Accessibility")
        }
    }

    func row(_ title: String, _ why: String, _ symbol: String, _ color: Color, _ granted: Bool,
             _ grant: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: grant)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PermissionState {
    var accessibility = Permissions.accessibility
    var mic = Permissions.microphone
    var allGranted: Bool { accessibility && mic }
    var grantedCount: Int { [accessibility, mic].filter { $0 }.count }
}

public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Talky: launch at login failed: \(error)")
        }
    }
}

// MARK: Pipes (edit and test in one place)

struct TestResult {
    /// The prompt this output came from, so edits after a run can be flagged.
    var prompt: String
    var output = ""
    var error: String?
    var seconds: Double?
    var running = true
}

struct PipesTab: View {
    @ObservedObject var store: PipeStore
    @ObservedObject var config: ConfigStore
    @State private var input = "um so i was thinking we could uh maybe move the standup to like ten thirty tomorrow if that works for everyone, no wait, eleven"
    @State private var results: [String: TestResult] = [:]
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHero(title: "Pipes",
                         subtitle: "Press a number while you talk to pick a pipe. 0 is always the raw transcript.") {
                PillPreview(label: "Hold \(HotkeySpec.label(config.config.hotkey))", pipes: store.pipes, selectedId: store.defaultPipeId)
            }
            testInput
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(store.pipes.enumerated()), id: \.element.id) { index, pipe in
                            PipeRow(store: store, index: index, pipeId: pipe.id, result: results[pipe.id])
                                .id(pipe.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: store.pipes.count) { old, new in
                    if new > old, let last = store.pipes.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            HStack {
                Button { store.add() } label: { Label("New pipe", systemImage: "plus") }
                Button("Use raw transcript by default") { store.defaultPipeId = nil }
                    .disabled(store.defaultPipeId == nil)
                Spacer()
                Text("Order sets the number key in the pill and the transform picker.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(SettingsLayout.margin)
    }

    var hasKey: Bool { AnthropicClient.apiKey != nil }

    var testInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Test text").font(.headline)
                Spacer()
                if !hasKey {
                    Text("Pipes need an Anthropic API key. Add one in General.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if task != nil {
                    Button("Stop") { task?.cancel(); task = nil }
                }
                Button { runAll() } label: { Label("Run all pipes", systemImage: "play.fill") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.select)
                    .disabled(!hasKey || store.pipes.isEmpty || input.isEmpty)
                    .help("Runs the text through every pipe (⌘↩)")
            }
            TextEditor(text: $input)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 76)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1)))
        }
    }

    func runAll() {
        task?.cancel()
        let pipes = store.pipes
        let text = input
        let llmConfig = config.config.llm
        results = Dictionary(uniqueKeysWithValues: pipes.map { ($0.id, TestResult(prompt: $0.prompt)) })
        let client = AnthropicClient()
        task = Task {
            await withTaskGroup(of: (String, Result<String, Error>, Double).self) { group in
                for pipe in pipes {
                    group.addTask {
                        let start = Date()
                        do {
                            let out = try await client.transform(text: text, instructions: pipe.prompt, config: llmConfig)
                            return (pipe.id, .success(out), Date().timeIntervalSince(start))
                        } catch {
                            return (pipe.id, .failure(error), Date().timeIntervalSince(start))
                        }
                    }
                }
                for await (id, result, secs) in group {
                    guard results[id] != nil else { continue }
                    results[id]?.running = false
                    results[id]?.seconds = secs
                    switch result {
                    case .success(let out): results[id]?.output = out
                    case .failure(let e): results[id]?.error = e.localizedDescription
                    }
                }
            }
            task = nil
        }
    }
}

/// One pipe: editable name and prompt on the left, its output for the test text on the right.
struct PipeRow: View {
    @ObservedObject var store: PipeStore
    let index: Int
    let pipeId: String
    let result: TestResult?

    var body: some View {
        if store.pipes.indices.contains(index), store.pipes[index].id == pipeId {
            HStack(alignment: .top, spacing: 18) {
                editor.frame(maxWidth: .infinity)
                output.frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(isDefault ? 0 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.select.opacity(isDefault ? 0.6 : 0), lineWidth: 1.5))
        }
    }

    var pipe: Binding<TextPipe> { $store.pipes[index] }
    var isDefault: Bool { store.defaultPipeId == pipeId }

    var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                KeyBadge(text: index < 9 ? "\(index + 1)" : "–", selected: isDefault, size: 24, onGlass: false)
                TextField("Name", text: pipe.name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                Spacer()
                if isDefault {
                    Text("Default").font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.select)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.select.opacity(0.14)))
                } else {
                    Button("Make default") { store.defaultPipeId = pipeId }
                        .buttonStyle(.link).font(.caption)
                }
                Group {
                    Button { store.move(id: pipeId, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0).help("Move up")
                    Button { store.move(id: pipeId, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == store.pipes.count - 1).help("Move down")
                    Button { store.delete(id: pipeId) } label: { Image(systemName: "trash") }
                        .help("Delete pipe")
                }
                .buttonStyle(.borderless)
            }
            TextEditor(text: pipe.prompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 130)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1)))
        }
    }

    var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let r = result {
                    if r.running { ProgressView().controlSize(.small) }
                    if !r.running, r.prompt != store.pipes[index].prompt {
                        Text("prompt edited, run again").font(.caption).foregroundStyle(.orange)
                    }
                    if let s = r.seconds { Text(String(format: "%.1fs", s)).font(.caption).foregroundStyle(.secondary) }
                    if !r.running, r.error == nil {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(r.output, forType: .string)
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                }
            }
            Group {
                if let r = result, let e = r.error {
                    Text(e).foregroundStyle(.red)
                } else if let r = result, !r.running {
                    Text(r.output)
                } else if result == nil {
                    Text("Press Run all pipes (⌘↩) to see this pipe's output.").foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }
}
