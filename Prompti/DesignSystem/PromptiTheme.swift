import SwiftUI

extension Color {
    static let promptMint = Color(red: 0.63, green: 0.93, blue: 0.82)
    static let promptMintDeep = Color(red: 0.08, green: 0.52, blue: 0.42)
    static let promptSky = Color(red: 0.56, green: 0.82, blue: 0.98)
    static let promptCoral = Color(red: 0.98, green: 0.48, blue: 0.39)
    static let promptSun = Color(red: 1.0, green: 0.78, blue: 0.25)
    static let promptInk = Color(red: 0.09, green: 0.14, blue: 0.17)
    static let promptAccent = Color.accentColor
}

enum PromptiRadius {
    static let compact: CGFloat = 14
    static let control: CGFloat = 20
    static let surface: CGFloat = 24
    static let hero: CGFloat = 32
}

struct PromptiBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(.systemGroupedBackground)
                Ellipse()
                    .fill(Color.promptMint.opacity(colorScheme == .dark ? 0.09 : 0.22))
                    .frame(width: proxy.size.width * 1.3, height: 420)
                    .blur(radius: 90)
                    .offset(x: -proxy.size.width * 0.4, y: -180)
                Ellipse()
                    .fill(Color.promptSky.opacity(colorScheme == .dark ? 0.06 : 0.18))
                    .frame(width: proxy.size.width, height: 400)
                    .blur(radius: 90)
                    .offset(x: proxy.size.width * 0.45, y: 160)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Content surfaces stay quiet and readable underneath glass controls.
struct PromptiSurfaceModifier: ViewModifier {
    var radius: CGFloat = PromptiRadius.surface
    var tint: Color = .clear
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground).opacity(reduceTransparency ? 1 : 0.86),
                        in: .rect(cornerRadius: radius))
            .background(tint, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.9), Color.primary.opacity(0.035)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.1 : 0.025), radius: 18, y: 7)
    }
}

extension View {
    func promptiSurface(radius: CGFloat = PromptiRadius.surface, tint: Color = .clear) -> some View {
        modifier(PromptiSurfaceModifier(radius: radius, tint: tint))
    }
}

/// A reading scrim lets content scroll behind floating glass actions without
/// letting labels from two layers overlap visually.
struct PromptiActionScrim: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(.systemGroupedBackground).opacity(0), location: 0),
            .init(color: Color(.systemGroupedBackground).opacity(0.96), location: 0.35),
            .init(color: Color(.systemGroupedBackground), location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.62)
            .animation(reduceMotion ? nil : .smooth(duration: 0.14), value: configuration.isPressed)

        if #available(iOS 26.0, *), !reduceTransparency {
            label.glassEffect(
                .regular.tint(isEnabled ? Color.promptMintDeep : Color.secondary.opacity(0.18)).interactive(isEnabled),
                in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
            )
        } else {
            label.background(
                isEnabled ? Color.promptMintDeep : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
            )
        }
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(reduceMotion ? nil : .smooth(duration: 0.14), value: configuration.isPressed)

        if #available(iOS 26.0, *), !reduceTransparency {
            label.glassEffect(
                .regular.tint(Color.white.opacity(0.06)).interactive(isEnabled),
                in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
            )
        } else if reduceTransparency {
            label
                .background(Color.promptSky.opacity(0.24), in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1))
                }
        } else {
            label
                .background(Color.promptSky.opacity(0.18), in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
        }
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.14), value: configuration.isPressed)

        if #available(iOS 26.0, *), !reduceTransparency {
            label.glassEffect(.regular.tint(Color.promptMint.opacity(0.18)).interactive(), in: Circle())
        } else if reduceTransparency {
            label.background(Color.promptMint.opacity(0.28), in: Circle())
        } else {
            label.background(Color.promptMint.opacity(0.2), in: Circle())
        }
    }
}

struct CompactGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.14), value: configuration.isPressed)

        if #available(iOS 26.0, *), !reduceTransparency {
            label.glassEffect(.regular.tint(Color.promptMint.opacity(0.18)).interactive(), in: Capsule())
        } else if reduceTransparency {
            label.background(Color.promptMint.opacity(0.28), in: Capsule())
        } else {
            label.background(Color.promptMint.opacity(0.2), in: Capsule())
        }
    }
}

struct ProviderChoiceButtonStyle: ButtonStyle {
    let tint: Color
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(reduceMotion ? nil : .smooth(duration: 0.14), value: configuration.isPressed)

        label
            .background(
                tint.opacity(isSelected ? 0.26 : 0.1),
                in: .rect(cornerRadius: PromptiRadius.surface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PromptiRadius.surface)
                    .strokeBorder(isSelected ? tint.opacity(0.65) : Color.primary.opacity(0.08))
            }
    }
}

struct PromptiCredentialFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: PromptiRadius.compact, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PromptiRadius.compact, style: .continuous)
                    .strokeBorder(Color.promptMintDeep.opacity(0.14))
            }
    }
}

struct PromptiSectionSurface<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color = Color.promptSky.opacity(0.12), @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .promptiSurface(tint: tint)
    }
}

struct PromptiFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct SectionLabel: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.title3.weight(.bold))
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
