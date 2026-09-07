import SwiftUI

struct DestinationSummaryCard: View {
    let destination: Destination
    var compact = false
    var showsDisclosure = false

    var body: some View {
        HStack(spacing: 14) {
            PromptiSymbolBadge(symbol: destination.symbol, size: compact ? 40 : 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.city)
                    .font(compact ? .headline : .title2.weight(.bold))
                    .fontDesign(.rounded)
                Text(destination.country)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.promptMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: showsDisclosure ? "chevron.right" : "mappin.and.ellipse")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.promptAccent)
        }
        .padding(compact ? 12 : 18)
        .promptiSurface()
    }

}

struct SceneChoiceButton: View {
    let scene: TravelScene
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: scene.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.promptOnAction : Color.promptAccent)
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? Color.promptOnAction.opacity(0.16) : Color.promptAccent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: PromptiRadius.compact, style: .continuous)
                )
            Text(LocalizedStringKey(scene.title))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.promptOnAction : Color.promptText)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 4)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.promptOnAction : Color.promptMuted.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            isSelected ? Color.promptAction : Color.promptSurface,
            in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                .strokeBorder(isSelected ? Color.clear : Color.promptBorder)
        }
    }

}

/// A sequence of conversations, with no decorative flight path or invented percentage.
struct PracticeJourneyVisual: View, Animatable {
    nonisolated var progress: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    let destinationSymbol: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 16) {
            PromptiBrandMark(height: 46)
                .foregroundStyle(Color.promptAccent)
                .frame(width: 68, height: 76)
                .background(Color.promptSurface, in: .rect(cornerRadius: PromptiRadius.control))
            GeometryReader { proxy in
                let value = min(max(progress, 0), 1)
                ZStack {
                    Capsule().fill(Color.promptBorder).frame(height: 2)
                    HStack(spacing: 0) {
                        Capsule().fill(Color.promptAccent)
                            .frame(width: proxy.size.width * value, height: 2)
                        Spacer(minLength: 0)
                    }
                    HStack {
                        ForEach(0..<3) { index in
                            if index > 0 { Spacer(minLength: 0) }
                            Image(systemName: isComplete ? "checkmark" : "text.bubble.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.promptAccent)
                                .frame(width: 28, height: 28)
                                .background(Color.promptHero, in: Circle())
                                .opacity(value >= CGFloat(index + 1) / 4 ? 1 : 0.35)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            PromptiSymbolBadge(symbol: isComplete ? "checkmark.bubble.fill" : destinationSymbol, size: 52)
        }
        .padding(.vertical, 16)
        .accessibilityHidden(true)
    }
}

struct MetricTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: PromptiRadius.compact))
            Text(value)
                .font(PromptiTypography.title)
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.promptMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
        .padding(.horizontal, 8)
        .promptiSurface(radius: PromptiRadius.control)
        .accessibilityElement(children: .combine)
    }
}

struct SummaryMetricCell: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: PromptiRadius.compact, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(PromptiTypography.section)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text(LocalizedStringKey(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.promptMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                .strokeBorder(tint.opacity(0.12))
        }
        .accessibilityElement(children: .combine)
    }
}

struct PromptiEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.promptAccent)
                .frame(width: 72, height: 72)
                .background(Color.promptHero, in: .rect(cornerRadius: PromptiRadius.surface))
            Text(LocalizedStringKey(title))
                .font(PromptiTypography.section)
            Text(LocalizedStringKey(message))
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
        .padding(24)
    }
}

enum PromptiNoticeTone {
    case neutral, success, warning, error

    var foreground: Color {
        switch self {
        case .neutral: .promptAccent
        case .success: .promptSuccess
        case .warning: .promptWarning
        case .error: .promptError
        }
    }

    var background: Color {
        switch self {
        case .neutral: .promptSurfaceRaised
        case .success: .promptSuccessSurface
        case .warning: .promptWarningSurface
        case .error: .promptErrorSurface
        }
    }
}

struct InlineNotice: View {
    let symbol: String
    let text: String
    var tone: PromptiNoticeTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tone.foreground)
            Text(LocalizedStringKey(text))
                .font(.footnote).foregroundStyle(Color.promptText)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tone.background, in: .rect(cornerRadius: PromptiRadius.compact))
    }
}

struct PromptiRecoveryView: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            PromptiEmptyState(symbol: symbol, title: title, message: message)
            Button(LocalizedStringKey(actionTitle), action: action)
                .buttonStyle(PrimaryActionButtonStyle())
        }
        .padding(PromptiSpacing.page)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PromptiBackground())
    }
}
