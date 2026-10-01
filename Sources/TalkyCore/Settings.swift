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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Talky Settings"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("TalkySettings")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

public enum SettingsTab: Hashable { case general, pipes, test }

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
            PipesTab(store: pipes).tabItem { Label("Pipes", systemImage: "line.3.horizontal.decrease") }.tag(SettingsTab.pipes)
            TestTab(pipes: pipes, config: config).tabItem { Label("Test", systemImage: "flask") }.tag(SettingsTab.test)
        }
        .padding()
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: General

struct GeneralTab: View {
    @ObservedObject var store: ConfigStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var permissions = PermissionState()
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    static let mainHotkeys = ["fn", "right_option", "right_command", "right_control", "ctrl+opt+space", "f13"]
    static let transformHotkeys = ["right_option", "right_command", "right_control", "ctrl+opt+t", "f14"]

    var body: some View {
        Form {
            if let err = store.loadError {
                Text(err).foregroundStyle(.red)
            }
            Section("Talky") {
                Toggle("Enabled", isOn: $store.config.enabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.set(on); launchAtLogin = LoginItem.isEnabled }
            }
            Section("Hotkeys") {
                hotkeyPicker("Dictate (hold, or double-tap for hands-free)", $store.config.hotkey, Self.mainHotkeys)
                hotkeyPicker("Transform selected text (tap)", $store.config.transformHotkey, Self.transformHotkeys)
                Text("Any name from the README works in config.json, e.g. \"cmd+shift+d\" or \"left_option\".")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Hands-free auto-stop")
                    Spacer()
                    Stepper("\(Int(store.config.handsFree.maxSeconds / 60)) min",
                            value: $store.config.handsFree.maxSeconds, in: 60...1800, step: 60)
                }
                Toggle("Show pipes next to the pill while dictating", isOn: $store.config.showPipesInPill)
            }
            Section("Transcription") {
                Picker("Backend", selection: $store.config.transcription.backend) {
                    Text("Auto (Groq, then OpenAI, then local)").tag("auto")
                    Text("Local whisper.cpp").tag("local")
                    Text("Groq").tag("groq")
                    Text("OpenAI").tag("openai")
                }
                Picker("Local model", selection: $store.config.transcription.localModel) {
                    ForEach(["small", "small.en", "medium", "medium.en"], id: \.self) { Text($0).tag($0) }
                    if !["small", "small.en", "medium", "medium.en"].contains(store.config.transcription.localModel) {
                        Text(store.config.transcription.localModel).tag(store.config.transcription.localModel)
                    }
                }
                TextField("Language (\"auto\", \"en\", \"he\", ...)", text: $store.config.transcription.language)
                TextField("Vocabulary hint (names, jargon)", text: $store.config.transcription.vocabulary)
                Toggle("Fall back to local if the cloud request fails", isOn: $store.config.transcription.fallbackToLocal)
                statusRow("Active backend", (try? TranscriptionService.plan(store.config.transcription).label) ?? "misconfigured")
                statusRow("whisper-cli", LocalWhisper.findBinary("whisper-cli", override: store.config.transcription.whisperCliPath) ?? "not found (brew install whisper-cpp)")
                statusRow("Model file", LocalWhisper().modelURL(store.config.transcription)?.lastPathComponent ?? "missing (scripts/download-model.sh \(store.config.transcription.localModel))")
            }
            Section("Cleanup (Claude)") {
                Toggle("Run dictation through the default pipe", isOn: $store.config.llm.enabled)
                TextField("Model", text: $store.config.llm.model)
                Picker("Effort", selection: $store.config.llm.effort) {
                    Text("low").tag("low"); Text("medium").tag("medium"); Text("high").tag("high")
                }
                Toggle("Restore my previous clipboard after pasting", isOn: $store.config.clipboard.restorePrevious)
                statusRow("Keys in .env", keySummary)
            }
            Section("Permissions") {
                permissionRow("Accessibility (hotkeys, paste)", permissions.accessibility, "Privacy_Accessibility")
                permissionRow("Input Monitoring (hotkeys)", permissions.input, "Privacy_ListenEvent")
                permissionRow("Microphone", permissions.mic, "Privacy_Microphone")
            }
            Section {
                HStack {
                    Button("Open config folder") { NSWorkspace.shared.open(Paths.configDir) }
                    Button("Reload config") { store.load() }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in permissions = PermissionState() }
    }

    var keySummary: String {
        let keys = [("Anthropic", "ANTHROPIC_API_KEY"), ("Groq", "GROQ_API_KEY"), ("OpenAI", "OPENAI_API_KEY")]
        let found = keys.filter { Env.value($0.1) != nil }.map(\.0)
        return found.isEmpty ? "none (offline mode)" : found.joined(separator: ", ")
    }

    func hotkeyPicker(_ title: String, _ binding: Binding<String>, _ options: [String]) -> some View {
        Picker(title, selection: binding) {
            ForEach(options, id: \.self) { Text(HotkeySpec.label($0)).tag($0) }
            if !options.contains(binding.wrappedValue) {
                Text(HotkeySpec.label(binding.wrappedValue)).tag(binding.wrappedValue)
            }
        }
    }

    func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    func permissionRow(_ title: String, _ granted: Bool, _ pane: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
            if !granted { Button("Open System Settings") { Permissions.openSettings(pane) } }
        }
    }
}

struct PermissionState {
    var accessibility = Permissions.accessibility
    var input = Permissions.inputMonitoring
    var mic = Permissions.microphone
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

// MARK: Pipes

struct PipesTab: View {
    @ObservedObject var store: PipeStore
    @State private var selection: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(Array(store.pipes.enumerated()), id: \.element.id) { i, pipe in
                        HStack {
                            Text(i < 9 ? "\(i + 1)" : " ").monospacedDigit().foregroundStyle(.secondary).frame(width: 14)
                            Text(pipe.name)
                            Spacer()
                            if store.defaultPipeId == pipe.id {
                                Text("default").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(pipe.id)
                    }
                }
                HStack(spacing: 4) {
                    Button { selection = store.add().id } label: { Image(systemName: "plus") }
                    Button {
                        if let s = selection { store.delete(id: s); selection = store.pipes.first?.id }
                    } label: { Image(systemName: "minus") }.disabled(selection == nil)
                    Spacer()
                    Button { if let s = selection { store.move(id: s, by: -1) } } label: { Image(systemName: "arrow.up") }
                    Button { if let s = selection { store.move(id: s, by: 1) } } label: { Image(systemName: "arrow.down") }
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200, maxWidth: 260)

            Group {
                if let id = selection, let index = store.pipes.firstIndex(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Name", text: $store.pipes[index].name).textFieldStyle(.roundedBorder)
                        Text("Prompt").font(.headline)
                        TextEditor(text: $store.pipes[index].prompt)
                            .font(.system(.body, design: .monospaced))
                            .border(Color.secondary.opacity(0.3))
                        HStack {
                            Button(store.defaultPipeId == id ? "Default for dictation" : "Make default for dictation") {
                                store.defaultPipeId = id
                            }
                            .disabled(store.defaultPipeId == id)
                            Button("Use raw transcript by default") { store.defaultPipeId = nil }
                                .disabled(store.defaultPipeId == nil)
                            Spacer()
                        }
                        Text("Order sets the number key: the first pipe is 1 in the pill and the transform picker. 0 is always the raw transcript.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    Text("Select a pipe or add one with +").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = store.pipes.first?.id } }
    }
}

// MARK: Test

struct TestResult: Identifiable {
    let id: String
    var name: String
    var output: String = ""
    var error: String?
    var seconds: Double?
    var running = true
}

struct TestTab: View {
    @ObservedObject var pipes: PipeStore
    @ObservedObject var config: ConfigStore
    @State private var input = "um so i was thinking we could uh maybe move the standup to like ten thirty tomorrow if that works for everyone, no wait, eleven"
    @State private var chosen: Set<String> = []
    @State private var results: [TestResult] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Input").font(.headline)
                TextEditor(text: $input)
                    .font(.body)
                    .border(Color.secondary.opacity(0.3))
                    .frame(minHeight: 120)
                Text("Pipes to compare").font(.headline)
                List {
                    ForEach(pipes.pipes) { pipe in
                        Toggle(pipe.name, isOn: Binding(
                            get: { chosen.contains(pipe.id) },
                            set: { on in if on { chosen.insert(pipe.id) } else { chosen.remove(pipe.id) } }))
                    }
                }
                .frame(minHeight: 120)
                HStack {
                    Button("All") { chosen = Set(pipes.pipes.map(\.id)) }
                    Button("None") { chosen = [] }
                    Spacer()
                    if task != nil {
                        Button("Stop") { task?.cancel(); task = nil }
                    }
                    Button("Run") { run() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(chosen.isEmpty || input.isEmpty)
                }
                if AnthropicClient.apiKey == nil {
                    Text("Add ANTHROPIC_API_KEY to ~/.config/talky/.env to run pipes.")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
            .frame(minWidth: 280, maxWidth: 360)

            ScrollView {
                if results.isEmpty {
                    Text("Pick one or more pipes and press Run (⌘↩) to see how each one transforms the input.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(results) { r in resultCard(r) }
                }
                .padding()
            }
            .frame(minWidth: 380, maxWidth: .infinity)
        }
        .onAppear { if chosen.isEmpty, let d = pipes.defaultPipeId { chosen = [d] } }
    }

    func resultCard(_ r: TestResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.name).font(.headline)
                Spacer()
                if r.running { ProgressView().controlSize(.small) }
                if let s = r.seconds { Text(String(format: "%.1fs", s)).font(.caption).foregroundStyle(.secondary) }
            }
            if let e = r.error {
                Text(e).foregroundStyle(.red).textSelection(.enabled)
            } else {
                Text(r.output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if !r.running, r.error == nil {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(r.output, forType: .string)
                }
                .buttonStyle(.link).font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }

    func run() {
        task?.cancel()
        let selected = pipes.pipes.filter { chosen.contains($0.id) }
        let text = input
        let llmConfig = config.config.llm
        results = selected.map { TestResult(id: $0.id, name: $0.name) }
        let client = AnthropicClient()
        task = Task {
            await withTaskGroup(of: (String, Result<String, Error>, Double).self) { group in
                for pipe in selected {
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
                    guard let i = results.firstIndex(where: { $0.id == id }) else { continue }
                    results[i].running = false
                    results[i].seconds = secs
                    switch result {
                    case .success(let out): results[i].output = out
                    case .failure(let e): results[i].error = e.localizedDescription
                    }
                }
            }
            task = nil
        }
    }
}
