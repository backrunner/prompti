import SwiftUI

/// Never redraw the logo here. Generate its template PDF with GenerateAppIcon.swift.
struct PromptiBrandMark: View {
    var height: CGFloat = 32

    var body: some View {
        Image("BrandMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: height * 620 / 720, height: height)
            .accessibilityHidden(true)
    }
}

struct PromptiWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            PromptiBrandMark(height: compact ? 26 : 34)
            Text(verbatim: "Prompti")
                .font(.system(compact ? .headline : .title2, design: .rounded, weight: .bold))
        }
        .foregroundStyle(Color.promptAccent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prompti")
    }
}

/// Functional icons use one treatment; the P remains exclusive to brand identity.
struct PromptiSymbolBadge: View {
    let symbol: String
    var size: CGFloat = 48
    var tint: Color = .promptAccent

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Color.promptSurfaceRaised, in: .rect(cornerRadius: PromptiRadius.compact))
            .accessibilityHidden(true)
    }
}

enum PromptiAnswerState {
    case idle, selected, correct, incorrect
}

/// Submitted answers stay readable while disabled; they are still learning content.
struct PromptiAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.88 : 1)
    }
}

/// Used by both cloze and multiple choice; icons and accessibility values carry meaning too.
struct PromptiAnswerStyle: ViewModifier {
    let state: PromptiAnswerState
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var colors: (foreground: Color, background: Color, border: Color) {
        if differentiateWithoutColor, state == .correct || state == .incorrect {
            return (.promptText, .promptSurfaceRaised, .promptMuted)
        }
        switch state {
        case .idle: return (.promptText, .promptSurface, .promptBorder)
        case .selected: return (.promptText, .promptSelection, .promptAccent)
        case .correct: return (.promptSuccess, .promptSuccessSurface, .promptSuccess)
        case .incorrect: return (.promptError, .promptErrorSurface, .promptError)
        }
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(colors.foreground)
            .background(colors.background, in: .rect(cornerRadius: PromptiRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: PromptiRadius.control)
                    .strokeBorder(colors.border, lineWidth: state == .idle ? 0.75 : 1.5)
                    .allowsHitTesting(false)
            }
    }
}
