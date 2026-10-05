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
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Talky Settings"
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

@MainActor
final class SettingsTabState: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var config: ConfigStore
    @ObservedObject var pipes: PipeStore
    @ObservedObject var tabState: SettingsTabState

    var body: some View {
        TabView(selection: $tabState.tab) {
            GeneralTab(store: config).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            PipesTab(store: pipes, config: config).tabItem { Label("Pipes", systemImage: "line.3.horizontal.decrease") }.tag(SettingsTab.pipes)
        }
        .padding()
        .frame(minWidth: 900, minHeight: 640)
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject private var updater = Updater.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var permissions = PermissionState()
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    static let mainHotkeys = ["fn", "right_option", "right_command", "right_control", "ctrl+opt+space", "f13"]
    static let transformHotkeys = ["right_option", "right_command", "right_control", "ctrl+opt+t", "f14"]
    static let languages = [("auto", "Detect automatically"), ("en", "English"), ("he", "Hebrew"), ("es", "Spanish"),
                            ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"),
                            ("ru", "Russian"), ("ar", "Arabic"), ("zh", "Chinese"), ("ja", "Japanese")]
    static let models = [("claude-haiku-4-5-20251001", "Haiku 4.5 (fastest)"), ("claude-sonnet-5-5", "Sonnet 5.5"),
                         ("claude-opus-5-5", "Opus 5.5 (slowest)")]

    var body: some View {
        Form {
            if let err = store.loadError {
                Text(err).foregroundStyle(.red)
            }
            if !permissions.allGranted {
                Section("Permissions") {
                    PermissionRows(state: permissions)
                }
            }
            Section("Dictation") {
                hotkeyPicker("Dictate", $store.config.hotkey, Self.mainHotkeys)
                hotkeyPicker("Transform selected text", $store.config.transformHotkey, Self.transformHotkeys)
                choicePicker("Language", $store.config.transcription.language, Self.languages)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.set(on); launchAtLogin = LoginItem.isEnabled }
            }
            Section("API keys") {
                APIKeyField(title: "Groq", envKey: "GROQ_API_KEY", url: APIKeyField.groqURL)
                APIKeyField(title: "Anthropic", envKey: "ANTHROPIC_API_KEY", url: APIKeyField.anthropicURL)
            }
            Section("Cleanup") {
                let hasKey = AnthropicClient.apiKey != nil
                Toggle("Clean up dictation with Claude", isOn: $store.config.llm.enabled)
                    .disabled(!hasKey)
                choicePicker("Model", $store.config.llm.model, Self.models)
                    .disabled(!hasKey || !store.config.llm.enabled)
                if !hasKey {
                    Text("Add an Anthropic key to turn on cleanup and pipes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                if updater.isAvailable {
                    Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                }
                HStack {
                    Text("Talky \(AppInfo.version)").foregroundStyle(.secondary)
                    Spacer()
                    if updater.isAvailable { Button("Check for Updates…") { updater.checkNow() } }
                    Button("Uninstall Talky…") { Uninstaller.confirmAndRun() }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in permissions = PermissionState() }
    }

    func hotkeyPicker(_ title: String, _ binding: Binding<String>, _ options: [String]) -> some View {
        Picker(title, selection: binding) {
            ForEach(options, id: \.self) { Text(HotkeySpec.label($0)).tag($0) }
            if !options.contains(binding.wrappedValue) {
                Text(HotkeySpec.label(binding.wrappedValue)).tag(binding.wrappedValue)
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
    }
}

/// A secure field bound to one key in ~/.config/talky/.env. Saves when the field loses focus or on Return.
struct APIKeyField: View {
    static let groqURL = URL(string: "https://console.groq.com/keys")!
    static let anthropicURL = URL(string: "https://console.anthropic.com/settings/keys")!

    let title: String
    let envKey: String
    let url: URL
    var prompt = "Paste key"
    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            SecureField(title, text: $value, prompt: Text(prompt))
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { _, isFocused in if !isFocused { save() } }
            Link("Get a key", destination: url).font(.caption)
        }
        .onAppear { value = Env.value(envKey) ?? "" }
        .onDisappear(perform: save)
    }

    func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (Env.value(envKey) ?? "") else { return }
        Env.set(envKey, trimmed)
        NotificationCenter.default.post(name: .talkyKeysChanged, object: nil)
    }
}

extension Notification.Name {
    static let talkyKeysChanged = Notification.Name("TalkyKeysChanged")
}

/// Permission status with a button for each missing one. Shared by Settings and onboarding.
struct PermissionRows: View {
    let state: PermissionState

    var body: some View {
        row("Microphone", state.mic) { Task { _ = await AudioRecorder.requestPermission(); Permissions.openSettings("Privacy_Microphone") } }
        row("Accessibility", state.accessibility) { Permissions.promptAccessibility(); Permissions.openSettings("Privacy_Accessibility") }
        row("Input Monitoring", state.input) { Permissions.promptInputMonitoring(); Permissions.openSettings("Privacy_ListenEvent") }
    }

    func row(_ title: String, _ granted: Bool, _ grant: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title)
            Spacer()
            if !granted { Button("Allow", action: grant) }
        }
    }
}

struct PermissionState {
    var accessibility = Permissions.accessibility
    var input = Permissions.inputMonitoring
    var mic = Permissions.microphone
    var allGranted: Bool { accessibility && input && mic }
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
        VStack(alignment: .leading, spacing: 12) {
            testInput
            Divider()
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
                Text("Order sets the number key in the pill and the transform picker. 0 is always the raw transcript.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var hasKey: Bool { AnthropicClient.apiKey != nil }

    var testInput: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    .disabled(!hasKey || store.pipes.isEmpty || input.isEmpty)
                    .help("Runs the text through every pipe (⌘↩)")
            }
            TextEditor(text: $input)
                .font(.body)
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
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
            HStack(alignment: .top, spacing: 16) {
                editor.frame(maxWidth: .infinity)
                output.frame(maxWidth: .infinity)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        }
    }

    var pipe: Binding<TextPipe> { $store.pipes[index] }
    var isDefault: Bool { store.defaultPipeId == pipeId }

    var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(index < 9 ? "\(index + 1)" : "–")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                TextField("Name", text: pipe.name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                Spacer()
                if isDefault {
                    Text("Default").font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
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
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
    }

    var output: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output").font(.headline).foregroundStyle(.secondary)
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
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        }
    }
}
