import SwiftUI

/// Content beyond the visible viewport, including safe-area and keyboard insets.
struct PromptiScrollOverflow: Equatable {
    let above: Bool
    let below: Bool
    let bottomInset: CGFloat

    init(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat,
         topInset: CGFloat, bottomInset: CGFloat) {
        above = offset + topInset > 1
        below = contentHeight + bottomInset - viewportHeight - offset > 1
        self.bottomInset = max(0, bottomInset)
    }

    static let none = Self(offset: 0, contentHeight: 0, viewportHeight: 0, topInset: 0, bottomInset: 0)
}

/// All app-owned vertical scrolling uses the same overflow affordance.
struct PromptiScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) { content() }
            .promptiScrollEdges()
    }
}

private struct PromptiScrollEdgesModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overflow = PromptiScrollOverflow.none

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: PromptiScrollOverflow.self) { geometry in
                PromptiScrollOverflow(
                    offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height,
                    topInset: geometry.contentInsets.top,
                    bottomInset: geometry.contentInsets.bottom
                )
            } action: { _, value in
                overflow = value
            }
            // A mask also clips the system large title drawn outside the scroll
            // viewport on recent iOS. Canvas scrims fade only the content edges.
            .overlay(alignment: .top) {
                edgeScrim(visible: overflow.above, atTop: true)
            }
            .overlay(alignment: .bottom) {
                edgeScrim(visible: overflow.below, atTop: false)
            }
    }

    private func edgeScrim(visible: Bool, atTop: Bool) -> some View {
        LinearGradient(
            colors: [Color.promptCanvas, Color.promptCanvas.opacity(0)],
            startPoint: atTop ? .top : .bottom,
            endPoint: atTop ? .bottom : .top
        )
        .frame(height: PromptiSpacing.section)
        .background(alignment: .bottom) {
            if !atTop {
                // Continue through the bottom inset, including translucent
                // search bars, so content cannot reappear after the fade.
                Color.promptCanvas
                    .frame(height: max(PromptiSpacing.section, overflow.bottomInset))
                    .offset(y: max(PromptiSpacing.section, overflow.bottomInset))
            }
        }
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Apply directly to native Forms; ordinary vertical content uses PromptiScrollView.
    func promptiScrollEdges() -> some View { modifier(PromptiScrollEdgesModifier()) }
}
