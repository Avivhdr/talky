import AppKit
import SwiftUI

public enum RecordingMode: Equatable { case hold, handsFree }

@MainActor
public final class PillModel: ObservableObject {
    public enum Content: Equatable {
        case hidden
        case recording
        case processing(String)
        case picker
        case message(String, isError: Bool)
    }

    @Published var content: Content = .hidden
    @Published var mode: RecordingMode = .hold
    @Published var isInstruction = false
    @Published var level: Float = 0
    @Published var elapsed: TimeInterval = 0
    @Published var remaining: TimeInterval?
    @Published var pipes: [TextPipe] = []
    @Published var selectedPipeId: String?
    @Published var showPipes = true
    @Published var selectionPreview = ""
    @Published var hotkeyLabel = "fn"

    var onSelectPipe: (String?) -> Void = { _ in }
    var onPickPipe: (TextPipe) -> Void = { _ in }
    var onSpeakInstruction: () -> Void = {}
    var onStop: () -> Void = {}
    var onClose: () -> Void = {}
}

/// Borderless panel that never takes focus, so clicks on it leave the user's app (and its selection) active.
final class PillPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
public final class PillController {
    public let model = PillModel()
    private let panel = PillPanel()
    private let hosting: FirstMouseHostingView<PillRootView>
    private var hideWork: DispatchWorkItem?

    public init() {
        hosting = FirstMouseHostingView(rootView: PillRootView(model: model))
        panel.contentView = hosting
    }

    func show(_ content: PillModel.Content) {
        hideWork?.cancel()
        model.content = content
        relayout()
        panel.orderFrontRegardless()
        // SwiftUI can finish laying out wrapped text a tick later; measure again so nothing gets clipped.
        DispatchQueue.main.async { [weak self] in self?.relayout() }
    }

    public func hide() {
        hideWork?.cancel()
        model.content = .hidden
        panel.orderOut(nil)
    }

    func flash(_ text: String, isError: Bool = false, seconds: Double = 1.6) {
        show(.message(text, isError: isError))
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Size the panel to the SwiftUI content and pin it bottom-center on the screen with the mouse.
    func relayout() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 24)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

// MARK: - Views

struct PillRootView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        Group {
            switch model.content {
            case .hidden:
                Color.clear.frame(width: 1, height: 1)
            case .recording:
                HStack(alignment: .center, spacing: 8) {
                    RecordingPill(model: model)
                    if model.showPipes && !model.isInstruction && !model.pipes.isEmpty {
                        PipeChips(model: model)
                    }
                }
            case .processing(let label):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(label).lineLimit(1).truncationMode(.tail).frame(maxWidth: 380, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(Color.black.opacity(0.85)))
            case .picker:
                PickerCard(model: model)
            case .message(let text, let isError):
                HStack(spacing: 8) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(isError ? .yellow : .white.opacity(0.8))
                    Text(text)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 17).fill(Color.black.opacity(0.85)))
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(6)
        .fixedSize()
    }
}

struct RecordingPill: View {
    @ObservedObject var model: PillModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isInstruction ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text(label)
            LevelBars(level: model.level)
            Text(timeString(model.elapsed)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
            if let r = model.remaining, r <= 30 {
                Text("stops in \(Int(r.rounded()))s").foregroundStyle(.yellow)
            }
            if model.mode == .handsFree {
                Button(action: model.onStop) {
                    Image(systemName: "stop.fill").font(.system(size: 10))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Stop and transcribe")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Color.black.opacity(0.85)))
    }

    var label: String {
        if model.isInstruction { return model.mode == .handsFree ? "Instruction · hands-free" : "Instruction" }
        return model.mode == .handsFree ? "Hands-free" : "Listening"
    }
}

struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule().fill(Color.white.opacity(0.85))
                    .frame(width: 3, height: CGFloat(4 + 14 * min(1, level * weights[i])))
            }
        }
        .frame(height: 18)
        .animation(.linear(duration: 0.08), value: level)
    }
}

struct PipeChips: View {
    @ObservedObject var model: PillModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.pipes.prefix(9).enumerated()), id: \.element.id) { i, pipe in
                chip(number: i + 1, name: pipe.name, selected: model.selectedPipeId == pipe.id) {
                    model.onSelectPipe(pipe.id)
                }
            }
            chip(number: 0, name: "Raw", selected: model.selectedPipeId == nil) { model.onSelectPipe(nil) }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.85)))
    }

    func chip(number: Int, name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text("\(number)").font(.system(size: 10, weight: .bold).monospacedDigit())
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(selected ? Color.black.opacity(0.15) : Color.white.opacity(0.15)))
                Text(name).lineLimit(1)
            }
            .padding(.leading, 4).padding(.trailing, 9).padding(.vertical, 4)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background(Capsule().fill(selected ? Color.white : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PickerCard: View {
    @ObservedObject var model: PillModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Transform selection").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: model.onClose) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            }
            Text(model.selectionPreview)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(Color.white.opacity(0.15))
            ForEach(Array(model.pipes.prefix(9).enumerated()), id: \.element.id) { i, pipe in
                row(key: "\(i + 1)", title: pipe.name, icon: nil) { model.onPickPipe(pipe) }
            }
            Divider().overlay(Color.white.opacity(0.15))
            row(key: model.hotkeyLabel, title: "Speak an instruction", icon: "mic.fill", action: model.onSpeakInstruction)
            Text("Hold \(model.hotkeyLabel) and say what to do, e.g. \"make it shorter\". Esc closes.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.88)))
    }

    func row(key: String, title: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(key).font(.system(size: 11, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.15)))
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(title)
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func timeString(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%d:%02d", s / 60, s % 60)
}
