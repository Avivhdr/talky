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
    /// The picker row that ↑ and ↓ move and Return runs: a pipe, or after the pipes, "Speak an instruction".
    @Published var highlighted = 0
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
        // The root view pads 14pt for the shadow, so the visible pill still sits 24pt above the Dock.
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 10)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

// MARK: - Views

/// Navy tint for the pill's glass.
private let pillTint = Color(red: 0.03, green: 0.05, blue: 0.14).opacity(0.5)
/// Dark layer over the glass so white text stays readable over white documents.
private let pillVeil = Color(red: 0.03, green: 0.05, blue: 0.14).opacity(0.55)

struct PillRootView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        GlassGroup(spacing: 8) {
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
                ProcessingPill(label: label)
            case .picker:
                PickerCard(model: model)
            case .message(let text, let isError):
                HStack(spacing: 9) {
                    Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(isError ? .yellow : .white.opacity(0.85))
                    Text(text)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .talkyGlass(RoundedRectangle(cornerRadius: 19, style: .continuous), tint: pillTint, veil: pillVeil)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // Room for the fallback material's shadow; Liquid Glass draws its own depth.
        .padding(14)
        .fixedSize()
    }
}

struct RecordingPill: View {
    @ObservedObject var model: PillModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(model.isInstruction ? Color.orange : Theme.live)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text(label)
            WaveBars(level: model.level)
            Text(timeString(model.elapsed)).monospacedDigit().foregroundStyle(.white.opacity(0.72))
            if let r = model.remaining, r <= 30 {
                Text("stops in \(Int(r.rounded()))s").foregroundStyle(.yellow)
            }
            if model.mode == .handsFree {
                Button(action: model.onStop) {
                    Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.2)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop and transcribe")
                .accessibilityLabel("Stop and transcribe")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .talkyGlass(Capsule(), tint: pillTint, veil: pillVeil)
    }

    var label: String {
        if model.isInstruction { return model.mode == .handsFree ? "Instruction · hands-free" : "Instruction" }
        return model.mode == .handsFree ? "Hands-free" : "Listening"
    }
}

/// While Talky works. The bars from the recording stay, and a band of light reads through them and on
/// across the label, so the voice visibly turns into text.
struct ProcessingPill: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { context in
            ProcessingFrame(label: label, time: context.date.timeIntervalSince(start), width: width, still: reduceMotion)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .talkyGlass(Capsule(), tint: pillTint, veil: pillVeil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The processing pill's content at `time` seconds. `width` is the width of this content.
struct ProcessingFrame: View {
    let label: String
    let time: Double
    let width: CGFloat
    /// Reduce Motion: nothing travels. The bars hold an arch and the pill slowly brightens and dims.
    var still = false

    static let barCount = 9
    static let barWidth: CGFloat = 2.5
    static let barGap: CGFloat = 2
    /// One read across the pill, then a rest before the next.
    static let sweep = 1.2
    static let rest = 0.25
    static let bandWidth: CGFloat = 84
    /// The dimmest the text gets. 70% white keeps 13pt text above 4.5:1 over white documents.
    static let floor = 0.7

    var body: some View {
        let x = lightX
        HStack(spacing: 10) {
            HStack(spacing: Self.barGap) {
                ForEach(0..<Self.barCount, id: \.self) { i in
                    let swell = swell(bar: i, lightX: x)
                    Capsule()
                        .fill(Color.white.opacity(0.6 + 0.4 * swell))
                        .frame(width: Self.barWidth, height: 4.5 + 2.5 * ripple(bar: i) + 11 * swell)
                }
            }
            .frame(height: 18)
            Text(label).lineLimit(1).truncationMode(.tail).frame(maxWidth: 380, alignment: .leading)
        }
        .mask(alignment: .leading) {
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(floorNow))
                if !still {
                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.bandWidth)
                        .offset(x: x - Self.bandWidth / 2)
                }
            }
        }
    }

    /// The center of the band of light, in points from the leading edge. It eases out of the bars,
    /// speeds across the label and slows as it leaves the last letters.
    var lightX: CGFloat {
        let p = min(1, time.truncatingRemainder(dividingBy: Self.sweep + Self.rest) / Self.sweep)
        let eased = CGFloat(p * p * (3 - 2 * p))
        let from: CGFloat = -14
        return from + (width + Self.bandWidth / 2 - from) * eased
    }

    /// How much a bar rises: 1 under the band of light, 0 away from it.
    func swell(bar i: Int, lightX: CGFloat) -> CGFloat {
        let middle = CGFloat(Self.barCount - 1) / 2
        if still { return 0.7 * (1 - abs(CGFloat(i) - middle) / (middle + 1)) }
        let center = CGFloat(i) * (Self.barWidth + Self.barGap) + Self.barWidth / 2
        let d = (center - lightX) / 9
        return exp(-d * d)
    }

    /// A small wave along the bars, so they stay alive between reads.
    func ripple(bar i: Int) -> CGFloat {
        if still { return 0 }
        return CGFloat(0.5 + 0.5 * sin(time * 2 * .pi / 1.1 - Double(i) * 0.7))
    }

    var floorNow: Double {
        guard still else { return Self.floor }
        return Self.floor + (1 - Self.floor) * (0.5 + 0.5 * cos(time * 2 * .pi / 1.8))
    }
}

struct PipeChips: View {
    @ObservedObject var model: PillModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.pipes.prefix(9).enumerated()), id: \.element.id) { i, pipe in
                chip(number: i + 1, name: pipe.name, selected: model.selectedPipeId == pipe.id) {
                    model.onSelectPipe(pipe.id)
                }
            }
            chip(number: 0, name: "Raw", selected: model.selectedPipeId == nil) { model.onSelectPipe(nil) }
        }
        .padding(4)
        .talkyGlass(Capsule(), tint: pillTint, veil: pillVeil)
    }

    func chip(number: Int, name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                KeyBadge(text: "\(number)", selected: selected, size: 18)
                Text(name).lineLimit(1)
            }
            .padding(.leading, 4).padding(.trailing, 10)
            .frame(height: 30)
            .foregroundStyle(selected ? Theme.navy : Color.white.opacity(0.85))
            .background(Capsule().fill(selected ? Color.white.opacity(0.94) : Color.clear))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.18), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), key \(number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PickerCard: View {
    @ObservedObject var model: PillModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Transform selection").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: model.onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                .help("Close (Esc)")
                .accessibilityLabel("Close")
            }
            Text(model.selectionPreview)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
            let pipes = Array(model.pipes.prefix(9))
            ForEach(Array(pipes.enumerated()), id: \.element.id) { i, pipe in
                PickerRow(model: model, index: i, key: "\(i + 1)", title: pipe.name, icon: nil) { model.onPickPipe(pipe) }
            }
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1).padding(.vertical, 4)
            PickerRow(model: model, index: pipes.count, key: model.hotkeyLabel, title: "Speak an instruction", icon: "mic.fill",
                      action: model.onSpeakInstruction)
            Text("Hold \(model.hotkeyLabel) and say what to do, e.g. \"make it shorter\". ↑ ↓ and Return pick a row. Esc closes.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 330)
        .talkyGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: pillTint, veil: pillVeil)
    }
}

/// One picker row. The keyboard and the pointer share one highlight, as in a menu.
struct PickerRow: View {
    @ObservedObject var model: PillModel
    let index: Int
    let key: String
    let title: String
    let icon: String?
    let action: () -> Void

    var body: some View {
        let highlighted = model.highlighted == index
        Button(action: action) {
            HStack(spacing: 10) {
                KeyBadge(text: key, size: 20)
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(highlighted ? 0.16 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { model.highlighted = index } }
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }
}

func timeString(_ t: TimeInterval) -> String {
    let s = Int(t)
    return String(format: "%d:%02d", s / 60, s % 60)
}
