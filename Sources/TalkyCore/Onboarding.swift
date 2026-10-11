import AppKit
import Combine
import SwiftUI

/// First-run window. Dictation first (speech model, permissions), then pipes as an option, then a real try.
@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let doneKey = "onboardingDone"
    public static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    private var window: NSWindow?
    /// Gets true when the user finished the last step, and false when they closed the window early.
    private let onFinish: (_ completed: Bool) -> Void
    private var completed = false

    /// The transform hotkey as the user sees it, such as "right ⌥".
    private let transformKey: String

    public init(transformKey: String, onFinish: @escaping (_ completed: Bool) -> Void) {
        self.transformKey = transformKey
        self.onFinish = onFinish
    }

    public func show() {
        if window == nil {
            let view = OnboardingView(transformKey: transformKey) { [weak self] in self?.finish() }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: OnboardingView.size.width, height: OnboardingView.size.height),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            // The window always sits on Talky's dark color field, so its controls use the dark appearance.
            w.appearance = NSAppearance(named: .darkAqua)
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
        completed = true
        window?.close()
        markDone()
    }

    private func markDone() {
        guard !Self.isDone else { return }
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        onFinish(completed)
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, speech, permissions, pipes, tryIt, tryTransform }
    static let size = CGSize(width: 600, height: 680)

    let transformKey: String
    let onFinish: () -> Void
    @ObservedObject private var model = SpeechModel.shared
    @State private var step = Step.welcome
    @State private var permissions = PermissionState()
    @ObservedObject private var anthropicKey = AnthropicKeyEntry.shared
    @State private var hasKey = AnthropicClient.apiKey != nil
    @State private var examplePipe: String? = "clean"
    /// The user picked a chip, so the example stops moving on by itself.
    @State private var exampleTouched = false
    @State private var exampleHovered = false
    @State private var tryText = ""
    @FocusState private var tryFocused: Bool
    @State private var draftText = PipeExample.draft
    @FocusState private var draftFocused: Bool
    /// A pipe has replaced text in the draft box.
    @State private var transformed = false
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(start: Step = .welcome, transformKey: String = HotkeySpec.label(Config().transformHotkey),
         onFinish: @escaping () -> Void) {
        self.transformKey = transformKey
        self.onFinish = onFinish
        _step = State(initialValue: start)
    }

    var body: some View {
        ZStack {
            TalkyBackdrop()
            VStack(spacing: 0) {
                progress.padding(.top, 18)
                Group {
                    switch step {
                    case .welcome: welcome
                    case .speech: speechStep
                    case .permissions: permissionsStep
                    case .pipes: pipesStep
                    case .tryIt: tryStep
                    case .tryTransform: transformStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .transition(.opacity)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.25), value: step)
        .onReceive(refresh) { _ in
            permissions = PermissionState()
            hasKey = AnthropicClient.apiKey != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .talkyKeysChanged)) { _ in
            hasKey = AnthropicClient.apiKey != nil
        }
        // The user turns on a permission in System Settings, so bring setup back in front of it.
        .onChange(of: permissions.grantedCount) { old, new in
            if step == .permissions, new > old { NSApp.activate(ignoringOtherApps: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .talkySelectionTransformed)) { _ in
            if step == .tryTransform { transformed = true }
        }
    }

    /// Pipes need a key, so without one the setup ends after the dictation try.
    private var steps: [Step] { hasKey ? Step.allCases : Step.allCases.filter { $0 != .tryTransform } }

    /// One dot per step: where you are in setup.
    var progress: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { s in
                Capsule()
                    .fill(Color.white.opacity(s == step ? 0.95 : 0.3))
                    .frame(width: s == step ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
    }

    // MARK: Steps

    /// What Talky does. Nothing here is interactive, so nothing looks like a control: the try is the last step.
    var welcome: some View {
        VStack(spacing: 0) {
            // Two spacers center the mark, the title and the three beats between the dots and the caption.
            Spacer(minLength: 0)
            TalkyMark(size: 56)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            Text("Welcome to Talky")
                .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                .padding(.top, 18)
            Text("Talk instead of typing. Your words appear wherever your cursor is, in any app.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            howItWorks
                .padding(.top, 40)
            Spacer(minLength: 0)
            Text("Dictation is free and private. You try it at the end of setup, in about a minute.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.bottom, 18)
            footer(primary: "Get Started") { step = .speech }
        }
    }

    var speechStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Speech stays on this Mac",
                   "Talky turns your voice into text with Whisper, a speech model that runs on your Mac. "
                   + "It works offline, and your audio never leaves the Mac.")
            panel {
                SpeechModelRow(model: model, secondary: .white.opacity(0.72), showsActions: false, showsIcon: true)
            }
            if let note = speechNote {
                Text(note).font(.caption).foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
            switch model.state {
            case .ready, .downloading:
                footer(primary: "Continue", back: .welcome) { step = .permissions }
            case .missing:
                footer(primary: "Download and Continue", back: .welcome, skip: { step = .permissions }) {
                    model.download()
                    step = .permissions
                }
            case .failed:
                footer(primary: "Try Again", back: .welcome, skip: { step = .permissions }) { model.download() }
            }
        }
    }

    private var speechNote: String? {
        switch model.state {
        case .downloading: return "You can go on. The download continues while you set up the rest."
        case .missing, .failed: return "Dictation needs this model. You can also download it later in Settings."
        case .ready: return nil
        }
    }

    var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Permissions", "Talky needs these to hear you and to type for you.")
            panel { PermissionRows(state: permissions) }
            Spacer()
            footer(primary: permissions.allGranted ? "Continue" : "Skip for Now", back: .speech) { step = .pipes }
        }
    }

    /// The second layer. The same pill as on the welcome step, now with pipe chips the user can click through.
    var pipesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Pipes").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    Text("Optional")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .talkyGlass(Capsule(), tint: Color.black.opacity(0.15))
                }
                Text("Dictation already works. With pipes, Claude also rewrites your text: what you say, and text you select in any app.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            panel { pipeExample }
            pipeFacts
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To turn on pipes, add your Anthropic API key").font(.headline)
                    Text("Pipes send the text to Anthropic, never your audio. Anthropic bills your account for what you use.")
                        .font(.caption).foregroundStyle(.white.opacity(0.72))
                }
                AnthropicKeyField(entry: anthropicKey)
                AnthropicKeyStatus(entry: anthropicKey, secondary: .white.opacity(0.72), link: .white)
            }
            Spacer()
            pipesFooter
        }
    }

    /// An empty field skips pipes. A typed key gets tested first; Continue goes on when Anthropic accepts it.
    @ViewBuilder var pipesFooter: some View {
        switch anthropicKey.status {
        case .empty:
            footer(primary: "Skip for Now", back: .permissions) { step = .tryIt }
        case .untested, .testing:
            footer(primary: "Continue", back: .permissions) {
                anthropicKey.test { if step == .pipes { step = .tryIt } }
            }
        case .works, .unreachable:
            footer(primary: "Continue", back: .permissions) { step = .tryIt }
        case .rejected:
            // Talky didn't save the key, so the way on is a new key or no pipes.
            footer(primary: "Continue", back: .permissions, skip: { step = .tryIt }, enabled: false) {}
        }
    }

    var pipeExample: some View {
        VStack(alignment: .leading, spacing: 12) {
            exampleLine("You say", PipeExample.spoken, italic: true)
            PillPreview(label: nil, pipes: DefaultPipes.all, selectedId: examplePipe) { id in
                exampleTouched = true
                examplePipe = id
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Talky types").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
                RewriteText(text: PipeExample.output(examplePipe)).font(.system(size: 15))
            }
            .frame(minHeight: 60, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { exampleHovered = $0 }
        .task(id: exampleTouched) { await cycleExample() }
    }

    /// Two more things pipes do, in their own tiles so they don't read as part of the example.
    var pipeFacts: some View {
        HStack(alignment: .top, spacing: 12) {
            factTile("character.cursor.ibeam", Theme.select, "Selected text too",
                     Text("Select text in any app and tap \(Text(transformKey).fontWeight(.semibold))."))
            factTile("plus", .indigo, "Your own pipes", Text(PipeExample.ownPipesNote))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func factTile(_ symbol: String, _ color: Color, _ title: String, _ text: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            text.font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .talkyGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), tint: Color.black.opacity(0.15))
        .accessibilityElement(children: .combine)
    }

    /// Moves the example to the next chip every few seconds, to show that the chips are there to click.
    /// It waits while the pointer is over the example, and stops for good when the user picks a chip.
    private func cycleExample() async {
        let ids: [String?] = DefaultPipes.all.prefix(4).map { Optional($0.id) } + [nil]
        while !exampleTouched {
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled, !exampleTouched else { return }
            if exampleHovered { continue }
            let i = ids.firstIndex(of: examplePipe) ?? -1
            examplePipe = ids[(i + 1) % ids.count]
        }
    }

    var tryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Try dictation", "Click in the box, hold fn and say a sentence. Let go, and Talky types it.")
            tryBox
            tryStatus
            Spacer()
            Label {
                Text("If holding fn opens the emoji picker, set Keyboard › “Press \(Image(systemName: "globe")) key to” to Do Nothing. ")
                + Text("[Open Keyboard Settings](x-apple.systempreferences:com.apple.Keyboard-Settings.extension)")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
            .tint(.white)
            if hasKey {
                footer(primary: "Continue", back: .pipes) { step = .tryTransform }
            } else {
                footer(primary: tryText.isEmpty ? "Finish" : "Start Using Talky", back: .pipes, action: onFinish)
            }
        }
        .onAppear { tryFocused = canTry }
        .onChange(of: canTry) { _, ready in if ready { tryFocused = true } }
    }

    private var canTry: Bool { permissions.allGranted && model.isReady }

    var tryBox: some View {
        TextEditor(text: $tryText)
            .font(.system(size: 17))
            .scrollContentBackground(.hidden)
            .focused($tryFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(height: 132)
            .overlay(alignment: .topLeading) {
                if tryText.isEmpty {
                    Text(canTry ? "Your words appear here." : "Talky isn't ready yet.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .talkyGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: Color.black.opacity(0.18))
            .disabled(!canTry)
            .accessibilityLabel("Try Talky here")
    }

    /// One line under the try box: what blocks Talky, or how to use it, or that it worked.
    @ViewBuilder var tryStatus: some View {
        if !permissions.allGranted {
            HStack(spacing: 10) {
                Label("Talky needs both permissions first.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Show Permissions") { step = .permissions }.controlSize(.small)
            }
            .font(.callout)
        } else if !model.isReady {
            SpeechModelRow(model: model, secondary: .white.opacity(0.72), showsActions: true)
                .font(.callout)
        } else if !tryText.isEmpty {
            Label("That's Talky. It works the same in every app.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 18) {
                    hint(["fn"], "Hold to talk")
                    hint(["fn", "fn"], "Tap twice for hands-free")
                    hint(["esc"], "Cancel")
                }
                if hasKey { hint(["1–9"], "Pick a pipe while you talk. 0 types it raw.") }
            }
        }
    }

    /// The second try: a pipe on text that is already there. Only with a key; the box starts with a draft.
    var transformStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Try a pipe on your text",
                   "Pipes also rewrite text you already wrote, in any app. Select text, tap \(transformKey) and pick a pipe.")
            draftBox
            transformStatus
            Spacer()
            footer(primary: transformed ? "Start Using Talky" : "Finish", back: .tryIt, action: onFinish)
        }
        .onAppear { if canTransform { selectDraft() } }
        .onChange(of: canTransform) { _, ready in if ready { selectDraft() } }
    }

    /// The transform key needs the key monitor, which needs Accessibility. It doesn't record, so no microphone.
    private var canTransform: Bool { permissions.accessibility && hasKey }

    var draftBox: some View {
        TextEditor(text: $draftText)
            .font(.system(size: 17))
            .scrollContentBackground(.hidden)
            .focused($draftFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(height: 160)
            .talkyGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: Color.black.opacity(0.18))
            .disabled(!canTransform)
            .accessibilityLabel("Text to try a pipe on")
    }

    /// Focuses the draft and selects all of it, so the first tap of the transform key already works.
    private func selectDraft(attempt: Int = 0) {
        draftFocused = true
        // The text view takes the focus a moment later, and later still while the step fades in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let view = NSApp.keyWindow?.firstResponder as? NSTextView, !view.isFieldEditor, view.string == draftText {
                view.selectAll(nil)
            } else if attempt < 5 {
                selectDraft(attempt: attempt + 1)
            }
        }
    }

    @ViewBuilder var transformStatus: some View {
        if !hasKey {
            HStack(spacing: 10) {
                Label("Pipes need an Anthropic key.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Add a Key") { step = .pipes }.controlSize(.small)
            }
            .font(.callout)
        } else if !permissions.accessibility {
            HStack(spacing: 10) {
                Label("Talky needs Accessibility to notice \(transformKey).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Show Permissions") { step = .permissions }.controlSize(.small)
            }
            .font(.callout)
        } else if transformed {
            HStack(spacing: 10) {
                Label("Claude rewrote it. Select text in any app to do the same.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if draftText != PipeExample.draft {
                    Button("Restore the Text") {
                        draftText = PipeExample.draft
                        selectDraft()
                    }
                    .controlSize(.small)
                }
            }
            .font(.callout)
        } else {
            HStack(spacing: 18) {
                hint([transformKey], "Show the pipes")
                hint(["1–9"], "Pick one")
                hint(["esc"], "Close")
            }
        }
    }

    // MARK: Pieces

    /// Hold, speak, let go: dictation in three beats.
    var howItWorks: some View {
        HStack(alignment: .top, spacing: 14) {
            beat("Hold fn") { Keycap("fn", large: true) }
            beatArrow
            beat("Speak") { Image(systemName: "waveform").font(.system(size: 24, weight: .medium)) }
            beatArrow
            beat("Let go. Talky types.") { Image(systemName: "text.cursor").font(.system(size: 24, weight: .medium)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold fn, speak, let go, and Talky types.")
    }

    func beat<Icon: View>(_ label: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 10) {
            icon().frame(height: 36)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(width: 140)
    }

    var beatArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(height: 36)
    }

    func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.4)
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .talkyGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), tint: Color.black.opacity(0.15))
    }

    func exampleLine(_ label: String, _ text: String, italic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
            Text(text).font(.system(size: 15)).italic(italic)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    func hint(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in Keycap(key) }
            Text(text).foregroundStyle(.white.opacity(0.78))
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    func footer(primary: String, back: Step? = nil, skip: (() -> Void)? = nil, enabled: Bool = true,
                action: @escaping () -> Void) -> some View {
        HStack {
            if let back {
                Button("Back") { step = back }
                    .controlSize(.large)
                    .talkySecondaryButton()
            }
            Spacer()
            if let skip {
                Button("Skip for Now", action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.trailing, 12)
            }
            Button(primary, action: action)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .talkyPrimaryButton()
                .tint(Theme.select)
                .disabled(!enabled)
        }
        .padding(.bottom, 28)
    }
}

/// The pipes step's example: one spoken sentence and what each default pipe makes of it.
/// The same sentence as the website's pipes demo.
enum PipeExample {
    /// The pipes in the example come with Talky; this says so, and that the user can write more.
    static var ownPipesNote: String {
        let names = DefaultPipes.all.prefix(4).map(\.name)
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.joined()
        return "\(list) come with Talky. Write more in Settings."
    }

    static let spoken = "um so can we move tomorrow’s standup to like eleven, the design review runs late"

    /// The transform try's starting text: a quick message typed in a hurry, so each pipe visibly changes it.
    static let draft = "hey, quick update on the launch. design review found 3 issues, we fixed 2 and the last one "
        + "should be done by wed so launch moves to thursday. let me know if thats a problem for anyone"

    static func output(_ pipeId: String?) -> String {
        switch pipeId {
        case "clean": return "Can we move tomorrow’s standup to 11:00? The design review runs late."
        case "formal": return "Could we move tomorrow’s standup to 11:00? The design review is running late."
        case "bullets": return "• Move tomorrow’s standup to 11:00\n• The design review runs late"
        default: return spoken
        }
    }
}

/// Text that writes itself in when it changes: the old text blurs away, then each word comes up
/// out of a blur, one after the other. With Reduce Motion, or before macOS 15, it cross-fades.
struct RewriteText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .id(text)
                .transition(.asymmetric(insertion: reduceMotion ? .opacity : .identity, removal: .blurAway))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(.easeOut(duration: 0.2), value: text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    @ViewBuilder private var content: some View {
        if #available(macOS 15.0, *) {
            if reduceMotion { Text(text) } else { WordReveal(text: text) }
        } else {
            Text(text)
        }
    }
}

private extension AnyTransition {
    static var blurAway: AnyTransition {
        .modifier(active: BlurFade(radius: 8, opacity: 0), identity: BlurFade(radius: 0, opacity: 1))
    }
}

private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

/// Plays the word-by-word entrance once, when it appears. RewriteText gives each new text a new one.
@available(macOS 15.0, *)
private struct WordReveal: View {
    let text: String
    @State private var elapsed = 0.0

    var body: some View {
        let words = Self.words(text)
        let duration = WordRevealRenderer.duration(words: words.count)
        Self.join(words)
            .textRenderer(WordRevealRenderer(elapsed: elapsed))
            .onAppear { withAnimation(.linear(duration: duration)) { elapsed = duration } }
    }

    /// Each word keeps the spaces after it, so the words join back into the same text.
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for ch in text {
            if !ch.isWhitespace, current.last?.isWhitespace == true {
                words.append(current)
                current = ""
            }
            current.append(ch)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// One Text with each word marked by its place, so the renderer can time the words one by one.
    static func join(_ words: [String]) -> Text {
        words.enumerated().reduce(Text(verbatim: "")) { text, item in
            let word = Text(verbatim: item.element).customAttribute(WordIndex(index: item.offset))
            return Text("\(text)\(word)")
        }
    }
}

@available(macOS 15.0, *)
private struct WordIndex: TextAttribute {
    let index: Int
}

/// Draws each word as it arrives: it fades in, comes into focus and settles 4pt up.
@available(macOS 15.0, *)
private struct WordRevealRenderer: TextRenderer, Animatable {
    /// Gives the old text time to blur away before the first word.
    static let delay = 0.12
    static let stagger = 0.045
    static let wordDuration = 0.5

    static func duration(words: Int) -> Double { delay + Double(max(words - 1, 0)) * stagger + wordDuration }

    var elapsed: Double
    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }
    /// Room for the blur and the settle, so they aren't cut at the text's edges.
    var displayPadding: EdgeInsets { EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let start = Self.delay + Double(run[WordIndex.self]?.index ?? 0) * Self.stagger
                let t = min(max((elapsed - start) / Self.wordDuration, 0), 1)
                guard t > 0 else { continue }
                let settle = 1 - pow(1 - t, 3) // ease out
                var word = context
                word.opacity = min(1, t * 1.8)
                if settle < 1 { word.addFilter(.blur(radius: 7 * (1 - settle))) }
                word.translateBy(x: 0, y: 4 * (1 - settle))
                word.draw(run)
            }
        }
    }
}

/// A small key cap for key names in hints.
struct Keycap: View {
    let key: String
    var large = false
    init(_ key: String, large: Bool = false) {
        self.key = key
        self.large = large
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: large ? 8 : 5, style: .continuous)
        Text(key)
            .font(.system(size: large ? 15 : 11, weight: .semibold).monospacedDigit())
            .padding(.horizontal, large ? 10 : 6)
            .frame(minWidth: large ? 44 : 22, minHeight: large ? 36 : 20)
            .background(shape.fill(Color.white.opacity(0.16)))
            .overlay(shape.stroke(Color.white.opacity(0.26), lineWidth: 1))
    }
}
