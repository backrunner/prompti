import SwiftUI
import UIKit

/// Brand roles, rather than decorative colors, are the only palette exposed to views.
/// Keep AccentColor.colorset aligned with promptAccent (see the brand contract).
extension Color {
    static let promptAccent = Color.accentColor
    static let promptInk = Color(hex: 0x103F38)
    static let promptCream = Color(hex: 0xF7FFEA)
    static let promptMint = Color(hex: 0xA3F2CE)
    static let promptCanvas = adaptive(light: 0xF5F6F0, dark: 0x101C18)
    static let promptSurface = adaptive(light: 0xFFFFFF, dark: 0x1A2A24)
    static let promptSurfaceRaised = adaptive(light: 0xEAF0E6, dark: 0x263B32)
    static let promptHero = adaptive(light: 0xE3EDDE, dark: 0x203B2E)
    static let promptText = adaptive(light: 0x173D33, dark: 0xEDF4EB)
    static let promptMuted = adaptive(light: 0x52675B, dark: 0xB2C5B7)
    static let promptBorder = adaptive(light: 0xCEDACB, dark: 0x3A5044)
    // Always pair a filled action/selection with promptOnAction, including in dark mode.
    static let promptAction = adaptive(light: 0x08765D, dark: 0xA3F2CE)
    static let promptOnAction = adaptive(light: 0xF7FFEA, dark: 0x103F38)
    static let promptSelection = adaptive(light: 0xDFEEE3, dark: 0x264538)
    static let promptSuccess = adaptive(light: 0x176C47, dark: 0xA3F2CE)
    static let promptSuccessSurface = adaptive(light: 0xE5F1E6, dark: 0x213C2C)
    static let promptWarning = adaptive(light: 0x815710, dark: 0xE9C67D)
    static let promptWarningSurface = adaptive(light: 0xF8EFD8, dark: 0x3C3221)
    static let promptError = adaptive(light: 0xAE392F, dark: 0xFFAEA0)
    static let promptErrorSurface = adaptive(light: 0xFAE9E4, dark: 0x442B27)

    private init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

enum PromptiRadius {
    static let compact: CGFloat = 14
    static let control: CGFloat = 20
    static let surface: CGFloat = 24
    static let hero: CGFloat = 32
}

enum PromptiSpacing {
    static let inline: CGFloat = 8
    static let related: CGFloat = 12
    static let page: CGFloat = 20
    static let section: CGFloat = 24
}

enum PromptiTypography {
    static let resultValueSize: CGFloat = 56
    static let hero = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    static let section = Font.system(.title3, design: .rounded, weight: .semibold)
}

struct PromptiBackground: View {
    var body: some View {
        Color.promptCanvas.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Opaque reading surfaces are deliberately independent of the system glass controls.
struct PromptiSurfaceModifier: ViewModifier {
    var radius: CGFloat = PromptiRadius.surface
    var tint: Color = .clear

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.promptSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.promptBorder.opacity(0.65), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func promptiSurface(radius: CGFloat = PromptiRadius.surface, tint: Color = .clear) -> some View {
        modifier(PromptiSurfaceModifier(radius: radius, tint: tint))
    }

    func promptiHeroSurface() -> some View {
        promptiHeroSurface(in: RoundedRectangle(cornerRadius: PromptiRadius.hero))
    }

    func promptiHeroSurface<S: InsettableShape>(in shape: S) -> some View {
        background(Color.promptHero, in: shape)
            .overlay {
                shape
                    .strokeBorder(Color.promptBorder.opacity(0.6), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct PromptiActionScrim: View {
    var body: some View {
        Color.promptCanvas.ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.promptOnAction : Color.promptMuted)
            .tint(isEnabled ? Color.promptOnAction : Color.promptMuted)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Color.promptAction : Color.promptSurfaceRaised,
                        in: .rect(cornerRadius: PromptiRadius.control))
            .contentShape(.rect(cornerRadius: PromptiRadius.control))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.promptAccent : Color.promptMuted)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.promptSurface, in: .rect(cornerRadius: PromptiRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: PromptiRadius.control)
                    .strokeBorder(Color.promptBorder, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: PromptiRadius.control))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.6)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Reserve Liquid Glass for compact floating controls, navigation and toolbars.
struct GlassIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .foregroundStyle(Color.promptAccent)
            .frame(width: 48, height: 48).contentShape(Circle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
        if #available(iOS 26.0, *), !reduceTransparency {
            label.glassEffect(.regular.interactive(isEnabled), in: Circle())
        } else {
            label.background(Color.promptSurfaceRaised, in: Circle())
        }
    }
}

struct CompactGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.promptAccent)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 44).contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
        if #available(iOS 26.0, *), !reduceTransparency {
            label.glassEffect(.regular.interactive(isEnabled), in: Capsule())
        } else {
            label.background(Color.promptSurfaceRaised, in: Capsule())
        }
    }
}

struct PromptiCredentialFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body).foregroundStyle(Color.promptText).textFieldStyle(.plain)
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(Color.promptSurfaceRaised, in: .rect(cornerRadius: PromptiRadius.compact))
            .overlay {
                RoundedRectangle(cornerRadius: PromptiRadius.compact)
                    .strokeBorder(Color.promptBorder, lineWidth: 0.75)
            }
    }
}

struct RecordingActionButtonStyle: ButtonStyle {
    let isRecording: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isRecording ? Color.promptError : Color.promptOnAction)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(isRecording ? Color.promptErrorSurface : Color.promptAction,
                        in: .rect(cornerRadius: PromptiRadius.control))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}

struct PromptiSectionSurface<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color = .clear, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content.padding(18).promptiSurface(tint: tint)
    }
}

struct PromptiFlowLayout: Layout {
    var spacing: CGFloat = 8

    private func size(of subview: LayoutSubview, availableWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard availableWidth > 0, ideal.width > availableWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = size(of: subview, availableWidth: width)
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
            let size = size(of: subview, availableWidth: bounds.width)
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
                .font(PromptiTypography.section)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(Color.promptMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
