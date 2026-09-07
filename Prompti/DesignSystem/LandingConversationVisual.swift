import SwiftUI

/// A quiet conversation composition. Entrance motion belongs to the welcome page;
/// the brand itself stays upright and still, including in Reduce Motion mode.
struct LandingConversationVisual: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: PromptiRadius.hero)
                    .fill(Color.promptHero)
                greeting("Hello.")
                    .rotationEffect(.degrees(-5))
                    .position(x: width * 0.23, y: 46)
                greeting("こんにちは")
                    .rotationEffect(.degrees(5))
                    .position(x: width * 0.75, y: 62)
                PromptiBrandMark(height: 84)
                    .foregroundStyle(Color.promptCream)
                    .frame(width: 124, height: 132)
                    .background(Color.promptInk, in: .rect(cornerRadius: PromptiRadius.hero))
                    .position(x: width * 0.5, y: 126)
                greeting("Hola.")
                    .rotationEffect(.degrees(-4))
                    .position(x: width * 0.2, y: 174)
                Image(systemName: "mappin.and.ellipse")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.promptAccent)
                    .position(x: width * 0.83, y: 166)
                Text("A little practice. A world of confidence.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.promptMuted)
                    .multilineTextAlignment(.center)
                    .frame(width: width - 32)
                    .position(x: width * 0.5, y: 224)
            }
        }
        .frame(height: 252)
        .accessibilityHidden(true)
    }

    private func greeting(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.promptText)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color.promptSurface, in: .rect(cornerRadius: PromptiRadius.control))
    }
}
