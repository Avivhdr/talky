import AppKit
import Combine
import SwiftUI

/// First-run window. Setup is finished only after a real sentence comes back as text.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let doneKey = "onboardingDone"
    public static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    private var window: NSWindow?
    private let onFinish: () -> Void
    private var didFinish = false

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in self?.finish() }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
                             styleMask: [.titled, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.title = "Welcome to Talky"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {}

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        onFinish()
        window?.close()
    }
}

struct OnboardingView: View {
    enum Step { case welcome, permissions, speech, cleanup, test }

    let onFinish: () -> Void
    @State private var step = Step.welcome
    @State private var permissions = PermissionState()
    @State private var anthropicState = KeyState.empty
    @State private var modelReady = WhisperModel.isInstalled(WhisperModel.setupName)
    @State private var whisperCLI = LocalWhisper.findBinary("whisper-cli", override: nil) != nil
    @State private var downloading = false
    @State private var downloadFraction: Double?
    @State private var downloadError: String?
    @State private var downloadTask: Task<Void, Never>?
    @State private var recorder = AudioRecorder()
    @State private var recording = false
    @State private var level: Float = 0
    @State private var transcribing = false
    @State private var transcript = ""
    @State private var testError: String?
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let transcription = TranscriptionService()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case .welcome: welcome
                    case .permissions: permissionsStep
                    case .speech: speechStep
                    case .cleanup: cleanupStep
                    case .test: testStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 36)
                .padding(.top, 44)
                .padding(.bottom, 12)
            }
            footer
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .frame(width: 540, height: 580)
        .onReceive(refresh) { _ in
            permissions = PermissionState()
            if step == .speech { refreshLocalTools() }
        }
        .onDisappear { downloadTask?.cancel(); if recording { recorder.cancel() } }
    }

    // MARK: Steps

    var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform").font(.system(size: 48, weight: .medium)).foregroundStyle(Color.accentColor)
            Text("Talky").font(.largeTitle.bold())
            Text("Hold fn, talk, let go. The text appears wherever your cursor is.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Talky hears you on this Mac. A key is only for cleanup, and you can skip it.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer(minLength: 24)
        }
    }

    var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Permissions", "Allow each one. A check appears when macOS grants it.")
            Form { PermissionRows(state: permissions) }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: 170)
            Text("If tapping fn opens the emoji picker, set Keyboard › \"Press 🌐 key to\" to Do Nothing.")
                .font(.caption).foregroundStyle(.secondary)
            if !permissions.allGranted {
                Text("Talky continues when all three show a check.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var speechStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Speech on this Mac", "Talky downloads a speech model once. It is about 500 MB. Dictation needs no key.")
            localSpeech
        }
    }

    var localSpeech: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !whisperCLI {
                Text("This copy of Talky is missing its speech engine. Quit Talky and open it again from the new build.")
                    .font(.callout)
            } else if modelReady {
                Label("The speech model is on this Mac.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("One download. About 500 MB. Talky keeps it on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                if downloading {
                    if let downloadFraction {
                        ProgressView(value: downloadFraction)
                        Text("\(Int(downloadFraction * 100)) percent").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Download speech model") { startDownload() }
                        .buttonStyle(.borderedProminent)
                }
                if let downloadError {
                    Text(downloadError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    var cleanupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Cleanup", "Optional. With an Anthropic key, Talky cleans up your words and turns on pipes. With no key, Talky pastes exactly what you said.")
            Form {
                Section {
                    APIKeyField(title: "Anthropic", envKey: "ANTHROPIC_API_KEY", url: APIKeyField.anthropicURL, verifies: .anthropic) {
                        anthropicState = $0
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 170)
            if case .invalid = anthropicState {
                Text("Clear the key to skip cleanup, or paste a key that works.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var testStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Try a sentence", "Record one sentence here. Setup finishes when the text comes back.")
            HStack(spacing: 12) {
                Button(recording ? "Stop and check" : "Record") { toggleRecording() }
                    .buttonStyle(.borderedProminent)
                    .disabled(transcribing)
                if recording {
                    ProgressView(value: Double(level))
                        .frame(width: 120)
                }
                if transcribing {
                    ProgressView()
                    Text("Transcribing…").foregroundStyle(.secondary)
                }
            }
            if !transcript.isEmpty {
                Text("Talky heard").font(.headline)
                Text(transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            if let testError {
                Text(testError).font(.callout).foregroundStyle(.red)
            }
        }
    }

    // MARK: Footer

    var footer: some View {
        HStack {
            if let back = backStep {
                Button("Back") { step = back }
            }
            Spacer()
            Button(primaryTitle) { goForward() }
                .disabled(!canGoForward)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    var backStep: Step? {
        switch step {
        case .welcome: return nil
        case .permissions: return .welcome
        case .speech: return .permissions
        case .cleanup: return .speech
        case .test: return .cleanup
        }
    }

    var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .permissions, .speech: return "Continue"
        case .cleanup: return anthropicState == .empty ? "Skip" : "Continue"
        case .test: return "Finish"
        }
    }

    var canGoForward: Bool {
        switch step {
        case .welcome: return true
        case .permissions: return permissions.allGranted
        case .speech: return whisperCLI && modelReady && !downloading
        case .cleanup: return anthropicState == .empty || anthropicState == .valid
        case .test: return !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !transcribing
        }
    }

    func goForward() {
        switch step {
        case .welcome: step = .permissions
        case .permissions: step = .speech
        case .speech: step = .cleanup
        case .cleanup: step = .test
        case .test: onFinish()
        }
    }

    func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Local model

    func refreshLocalTools() {
        whisperCLI = LocalWhisper.findBinary("whisper-cli", override: nil) != nil
        modelReady = WhisperModel.isInstalled(WhisperModel.setupName)
    }

    func startDownload() {
        downloadError = nil
        downloading = true
        downloadFraction = 0
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                try await WhisperModel.download(WhisperModel.setupName) { fraction in
                    Task { @MainActor in downloadFraction = fraction }
                }
                await MainActor.run {
                    downloading = false
                    modelReady = true
                }
            } catch is CancellationError {
                await MainActor.run { downloading = false }
            } catch {
                await MainActor.run {
                    downloading = false
                    downloadError = error.localizedDescription
                }
            }
        }
    }

    // MARK: Test recording

    func toggleRecording() {
        if recording { stopAndTranscribe(); return }
        testError = nil
        transcript = ""
        do {
            recorder.onLevel = { level = $0 }
            try recorder.start()
            recording = true
        } catch {
            testError = error.localizedDescription
        }
    }

    func stopAndTranscribe() {
        recording = false
        let captured = recorder.stop()
        guard captured.duration >= 0.4, captured.peak > 0.01 else {
            testError = "That was too short. Say a full sentence, then stop."
            return
        }
        transcribing = true
        testError = nil
        let service = transcription
        Task {
            do {
                let wav = try WAV.writeTemp(samples: captured.samples)
                defer { try? FileManager.default.removeItem(at: wav) }
                let text = try await service.transcribe(wav: wav, config: Config().transcription)
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                transcribing = false
                if cleaned.isEmpty {
                    testError = "Talky heard silence. Try again, closer to the microphone."
                } else {
                    transcript = cleaned
                }
            } catch {
                transcribing = false
                testError = error.localizedDescription
            }
        }
    }
}
