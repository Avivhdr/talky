import SwiftUI

/// Talky's visual world: Apple's glass over one deep color field. The website uses the same values.
enum Theme {
    static let navy = Color(red: 0x0B / 255, green: 0x1A / 255, blue: 0x3A / 255)
    static let indigo = Color(red: 0x14 / 255, green: 0x1A / 255, blue: 0x4A / 255)
    static let violet = Color(red: 0x6B / 255, green: 0x4B / 255, blue: 0xFF / 255)
    static let blue = Color(red: 0x1E / 255, green: 0x5B / 255, blue: 0xFF / 255)
    static let peach = Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0x6B / 255)
    /// Only for "the mic is live". Nothing else uses it.
    static let live = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
    /// The number badge of the selected pipe.
    static let select = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
}

/// The color field every glass surface sits on.
struct TalkyBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let s = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [Theme.navy, Theme.indigo, Color(red: 0.04, green: 0.07, blue: 0.19)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                glow(Theme.violet, 0.95, size: s * 0.9, x: geo.size.width * 0.86, y: geo.size.height * 0.12)
                glow(Theme.peach, 0.8, size: s * 0.75, x: geo.size.width * 0.06, y: geo.size.height * 0.86)
                glow(Theme.blue, 0.75, size: s * 0.9, x: geo.size.width * 0.55, y: geo.size.height * 1.1)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, _ opacity: Double, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .position(x: x, y: y)
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later; a material with a light rim before that.
    /// `veil` is a fill laid over the glass. Use it where white text must stay readable over any
    /// background: Liquid Glass turns light over white content even when tinted.
    @ViewBuilder
    func talkyGlass<S: Shape>(_ shape: S, tint: Color? = nil, veil: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            background { if let veil { shape.fill(veil) } }
                .glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint) }
                    if let veil { shape.fill(veil) }
                    shape.strokeBorderCompat(Color.white.opacity(0.22))
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            }
        }
    }

    /// The prominent button: glass on macOS 26 and later, the bordered prominent style before that.
    @ViewBuilder
    func talkyPrimaryButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func talkySecondaryButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

private extension Shape {
    /// A 1pt inner rim. `strokeBorder` needs InsettableShape, so this insets the stroke by hand.
    func strokeBorderCompat(_ color: Color) -> some View {
        stroke(color, lineWidth: 1).padding(0.5)
    }
}

/// Groups glass shapes so they render and morph together on macOS 26; a plain stack before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// The number key for a pipe. Selected badges turn blue.
struct KeyBadge: View {
    let text: String
    var selected = false
    var size: CGFloat = 20
    /// Glass badges sit on the dark pill; plain badges sit on normal window backgrounds.
    var onGlass = true

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.52, weight: .bold).monospacedDigit())
            .foregroundStyle(selected || onGlass ? Color.white : Color.primary)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, text.count > 1 ? 5 : 0)
            .background(Capsule().fill(selected ? Theme.select : onGlass ? Color.white.opacity(0.16) : Color.primary.opacity(0.1)))
    }
}

/// The Talky mark: a white rounded square with three waveform bars.
struct TalkyMark: View {
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(.white)
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).stroke(Color.black.opacity(0.08)))
            .frame(width: size, height: size)
            .overlay {
                HStack(spacing: size * 0.12) {
                    bar(0.24); bar(0.46); bar(0.14)
                }
            }
            .accessibilityHidden(true)
    }

    private func bar(_ h: CGFloat) -> some View {
        Capsule().fill(Theme.navy).frame(width: size * 0.09, height: size * h)
    }
}

/// Waveform bars driven by one input level. Shaped so the middle bars move most.
struct WaveBars: View {
    let level: Float
    var count = 9
    var maxHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let center = Float(count - 1) / 2
                let shape = 1 - abs(Float(i) - center) / (center + 1.5)
                Capsule().fill(Color.white.opacity(0.92))
                    .frame(width: 2.5, height: 3 + (maxHeight - 3) * CGFloat(min(1, level * shape * 1.25)))
            }
        }
        .frame(height: maxHeight)
        .animation(.linear(duration: 0.08), value: level)
    }
}

/// A still picture of the pill on the color field, built from real settings. Used in onboarding and Settings.
/// It shows the idle pill: the red dot means "the mic is live" and appears only while Talky records.
struct PillPreview: View {
    /// Nil shows the pipe chips alone.
    var label: String?
    var pipes: [TextPipe]
    var selectedId: String?
    var showsRaw = true
    /// Makes the chips buttons, for an example the user can click through.
    var onSelect: ((String?) -> Void)? = nil

    @Namespace private var selection
    /// The key of the chip under the pointer. Raw has no pipe id, so chips go by key.
    @State private var hoveredKey: String?

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                if let label {
                    HStack(spacing: 9) {
                        Circle().fill(Color.white.opacity(0.5)).frame(width: 8, height: 8)
                        Text(label)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .talkyGlass(Capsule(), tint: Color.black.opacity(0.18))
                }

                if !pipes.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(pipes.prefix(4).enumerated()), id: \.element.id) { i, pipe in
                            chip("\(i + 1)", pipe.name, id: pipe.id)
                        }
                        if showsRaw { chip("0", "Raw", id: nil) }
                    }
                    .padding(4)
                    // The white selection glides to the new chip instead of blinking from one to the other.
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: selectedId)
                    .talkyGlass(Capsule(), tint: Color.black.opacity(0.18))
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: onSelect == nil ? .ignore : .contain)
        .accessibilityLabel("Preview of the Talky pill")
    }

    @ViewBuilder
    private func chip(_ key: String, _ name: String, id: String?) -> some View {
        let selected = selectedId == id
        let hovered = onSelect != nil && hoveredKey == key && !selected
        let face = HStack(spacing: 6) {
            KeyBadge(text: key, selected: selected, size: 18)
            Text(name).lineLimit(1).fixedSize()
        }
        .padding(.leading, 4).padding(.trailing, 10)
        .frame(height: 30)
        .foregroundStyle(selected ? Theme.navy : .white.opacity(hovered ? 1 : 0.85))
        .background {
            if selected {
                Capsule().fill(Color.white.opacity(0.94))
                    .matchedGeometryEffect(id: "selection", in: selection)
            } else if hovered {
                Capsule().fill(Color.white.opacity(0.14))
            }
        }
        .contentShape(Capsule())
        if let onSelect {
            Button { onSelect(id) } label: { face }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hoveredKey = key } else if hoveredKey == key { hoveredKey = nil }
                }
                .linkPointer()
                .accessibilityLabel("\(name), key \(key)")
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            face
        }
    }
}

extension View {
    /// The pointing hand over something clickable that doesn't look like a standard button.
    @ViewBuilder
    func linkPointer() -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(.link)
        } else {
            self
        }
    }
}

/// The top band of each Settings page: the page name over the color field, with the pill as your settings make it.
struct SettingsHero<Preview: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var preview: Preview

    var body: some View {
        // Side by side when the window is wide; the pill moves under the title when it is not.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                titles
                Spacer(minLength: 0)
                preview.fixedSize()
            }
            VStack(alignment: .leading, spacing: 16) {
                titles
                preview.fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(TalkyBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 26, weight: .bold)).tracking(-0.4)
            Text(subtitle).font(.callout).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
