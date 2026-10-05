import AppKit
import Combine
import SwiftUI

/// First-run window: permissions, then API keys, then a prompt to try it.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let doneKey = "onboardingDone"
    public static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    private var window: NSWindow?
    private let onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in self?.finish() }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                             styleMask: [.titled, .closable, .fullSizeContentView],
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

    /// Closing the window early counts as finishing; Settings has everything onboarding sets.
    public func windowWillClose(_ notification: Notification) { markDone() }

    private func finish() {
        window?.close()
        markDone()
    }

    private func markDone() {
        guard !Self.isDone else { return }
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        onFinish()
    }
}

struct OnboardingView: View {
    enum Step { case welcome, permissions, keys, done }

    let onFinish: () -> Void
    @State private var step = Step.welcome
    @State private var permissions = PermissionState()
    @State private var keysVersion = 0
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .permissions: permissionsStep
                case .keys: keysStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 44)
        }
        .frame(width: 520, height: 460)
        .onReceive(refresh) { _ in permissions = PermissionState() }
        .onReceive(NotificationCenter.default.publisher(for: .talkyKeysChanged)) { _ in keysVersion += 1 }
    }

    // MARK: Steps

    var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform").font(.system(size: 48, weight: .medium)).foregroundStyle(Color.accentColor)
            Text("Talky").font(.largeTitle.bold())
            Text("Hold fn, talk, let go. The text appears wherever your cursor is.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            footer(primary: "Get started") { step = .permissions }
        }
    }

    var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Permissions", "Talky needs these to hear you and type for you.")
            Form { PermissionRows(state: permissions) }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: 170)
            Text("If tapping fn opens the emoji picker, set Keyboard › \"Press 🌐 key to\" to Do Nothing.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            footer(primary: permissions.allGranted ? "Continue" : "Skip for now", back: .welcome) { step = .keys }
        }
    }

    var keysStep: some View {
        let _ = keysVersion   // re-check canTranscribe after a key is saved
        return VStack(alignment: .leading, spacing: 16) {
            header("API keys", "Both are optional. You can add them later in Settings.")
            Form {
                Section {
                    APIKeyField(title: "Groq", envKey: "GROQ_API_KEY", url: APIKeyField.groqURL)
                } footer: {
                    Text("Turns speech into text. The free tier is enough for dictation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    APIKeyField(title: "Anthropic", envKey: "ANTHROPIC_API_KEY", url: APIKeyField.anthropicURL)
                } footer: {
                    Text("Removes filler words and runs pipes. Without it Talky pastes exactly what you said.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 210)
            if !Self.canTranscribe {
                Text("Without a Groq key, Talky transcribes on this Mac and needs whisper.cpp: brew install whisper-cpp")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            footer(primary: "Continue", back: .permissions) { step = .done }
        }
    }

    var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
            Text("You're set").font(.largeTitle.bold())
            Text("Click into any text field, hold fn and say something.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if AnthropicClient.apiKey == nil {
                Text("Cleanup and pipes are off until you add an Anthropic key in Settings.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            Spacer()
            footer(primary: "Done", back: .keys, action: onFinish)
        }
    }

    // MARK: Pieces

    static var canTranscribe: Bool {
        Env.value("GROQ_API_KEY") != nil || Env.value("OPENAI_API_KEY") != nil
            || LocalWhisper.findBinary("whisper-cli", override: nil) != nil
    }

    func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    func footer(primary: String, back: Step? = nil, action: @escaping () -> Void) -> some View {
        HStack {
            if let back { Button("Back") { step = back } }
            Spacer()
            Button(primary, action: action)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.bottom, 24)
    }
}
