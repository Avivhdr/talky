import AppKit
import SwiftUI

/// A hotkey setting in Settings. Click the field and press the new keys, or pick a suggestion from the menu.
/// The two Talky hotkeys can't be the same key, so each field knows the other one.
struct HotkeyField: View {
    let title: String
    @Binding var hotkey: String
    /// The first one is the default.
    let suggestions: [String]
    let otherTitle: String
    let otherHotkey: String

    @StateObject private var recorder = HotkeyRecorder()
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    static let fieldHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            control
            if let note = recorder.note {
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(note.isProblem ? Color.orange : .secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        // The row centers its label on the field, so a note under the field grows the row downward only.
        .alignmentGuide(VerticalAlignment.center) { _ in Self.fieldHeight / 2 }
        .animation(.easeOut(duration: 0.15), value: recorder.isRecording)
        .animation(.easeOut(duration: 0.15), value: recorder.note)
        .onDisappear { recorder.stop() }
    }

    private var control: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return HStack(spacing: 0) {
            field
            Divider().frame(height: 16)
            suggestionsMenu
        }
        .frame(height: Self.fieldHeight)
        .background(shape.fill(Color(nsColor: .textBackgroundColor)))
        .overlay(shape.strokeBorder(recorder.isRecording ? Color.accentColor : Color.primary.opacity(hovering ? 0.2 : 0.12)))
        .overlay(shape.inset(by: -1.5).stroke(Color.accentColor.opacity(recorder.isRecording ? 0.35 : 0), lineWidth: 3))
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
    }

    private var field: some View {
        Button {
            if recorder.isRecording { recorder.stop() } else { recorder.start(accept: accept) }
        } label: {
            HStack(spacing: 4) {
                if !recorder.isRecording {
                    caps(HotkeySpec.keycaps(hotkey))
                } else if recorder.held.isEmpty {
                    Text("Press keys…").foregroundStyle(.secondary).padding(.leading, 3)
                } else {
                    caps(recorder.held)
                }
            }
            .padding(.horizontal, 4)
            // At least 150pt, wider for a long chord such as ⌃⌥⇧⌘Space.
            .frame(minWidth: 150, minHeight: Self.fieldHeight, maxHeight: Self.fieldHeight, alignment: .leading)
            .fixedSize()
            .contentShape(Rectangle())
            .background(AnchorView(view: recorder.anchor))
        }
        .buttonStyle(.plain)
        .help(recorder.isRecording ? HotkeyRecorder.instructions : "Click, then press the keys you want for \(title).")
        .accessibilityLabel("\(title) shortcut")
        .accessibilityValue(recorder.isRecording ? "Recording" : HotkeySpec.label(hotkey))
        .accessibilityHint("Click, then press the new keys.")
    }

    private func caps(_ keys: [String]) -> some View {
        ForEach(Array(keys.enumerated()), id: \.offset) { Keycap($0.element, plain: true) }
    }

    private var suggestionsMenu: some View {
        Menu {
            Section("Suggested") {
                ForEach(suggestions, id: \.self) { key in
                    Toggle(isOn: Binding(get: { Self.same(key, hotkey) }, set: { _ in choose(key) })) {
                        Text(key == suggestions.first ? "\(HotkeySpec.label(key)) (Default)" : HotkeySpec.label(key))
                    }
                    .disabled(Self.same(key, otherHotkey))
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: Self.fieldHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Suggested shortcuts")
        .accessibilityLabel("Suggested \(title) shortcuts")
    }

    private func choose(_ key: String) {
        recorder.stop()
        guard !Self.same(key, otherHotkey) else { return }
        hotkey = key
    }

    /// Saves the recorded hotkey, or returns why it can't be used.
    private func accept(_ name: String) -> String? {
        if Self.same(name, otherHotkey) { return "\(otherTitle) uses \(HotkeySpec.label(otherHotkey)) already." }
        hotkey = name
        return nil
    }

    /// "fn" and "globe" are the same key, so compare what the names parse to.
    static func same(_ a: String, _ b: String) -> Bool {
        guard let spec = HotkeySpec.parse(a) else { return a == b }
        return spec == HotkeySpec.parse(b)
    }
}

/// Records the next keys pressed in the Settings window as a hotkey name, through HotkeyCapture.
/// While it records, the global key monitor is paused, so the current hotkeys reach Settings
/// instead of starting a dictation. Esc, a click outside the field, or another window stops it.
@MainActor
final class HotkeyRecorder: ObservableObject {
    struct Note: Equatable {
        var text: String
        var isProblem: Bool
    }

    static let instructions = "Press one modifier key by itself, or a key with ⌃, ⌥ or ⌘. Esc cancels."

    @Published private(set) var isRecording = false
    /// The modifiers held now, shown in the field while the user builds a chord.
    @Published private(set) var held: [String] = []
    @Published private(set) var note: Note?

    /// Sits behind the field. A click outside it stops the recording.
    let anchor = PassThroughView()
    private var capture = HotkeyCapture()
    private var accept: ((String) -> String?)?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// Only one field records at a time.
    private static weak var current: HotkeyRecorder?

    /// accept saves the hotkey, or returns why it can't be used. Recording then goes on, with that reason shown.
    func start(accept: @escaping (String) -> String?) {
        Self.current?.stop()
        Self.current = self
        self.accept = accept
        capture = HotkeyCapture()
        held = []
        note = Note(text: Self.instructions, isProblem: false)
        isRecording = true
        KeyMonitor.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else {
                KeyMonitor.isPaused = false
                return event
            }
            return self.handle(event)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: anchor.window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        accept = nil
        isRecording = false
        held = []
        note = nil
        KeyMonitor.isPaused = false
        if Self.current === self { Self.current = nil }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let flags = event.cgEvent?.flags ?? CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let result: HotkeyCapture.Result?
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            let inside = event.window === anchor.window
                && anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
            if !inside { stop() }
            return event
        case .keyDown where event.keyCode == UInt16(KeyMonitor.escapeCode) && flags.intersection(HotkeySpec.chordMask).isEmpty:
            stop()
            return nil
        case .keyDown:
            result = capture.keyDown(keyCode: Int64(event.keyCode), flags: flags)
        default:
            result = capture.flagsChanged(keyCode: Int64(event.keyCode), flags: flags)
        }
        held = capture.heldKeycaps
        switch result {
        case .captured(let name)?:
            if let problem = accept?(name) { note = Note(text: problem, isProblem: true) } else { stop() }
        case .rejected(let problem)?:
            note = Note(text: problem, isProblem: true)
        case nil:
            break
        }
        // Keys are recorded, not typed. Modifier changes go on, so the window keeps the real modifier state.
        return event.type == .keyDown ? nil : event
    }
}

/// An invisible view that marks a frame in the window and lets clicks through.
final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Puts an existing AppKit view behind SwiftUI content, so code outside SwiftUI can find its frame.
struct AnchorView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
