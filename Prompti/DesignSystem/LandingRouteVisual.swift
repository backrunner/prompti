import SwiftUI

/// A continuous journey: the plane follows the route's tangent, with a soft
/// crossfade at the ends instead of reversing or snapping across the screen.
struct LandingRouteVisual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let phase = reduceMotion ? 0.56 : elapsed.truncatingRemainder(dividingBy: 9) / 9
            GeometryReader { proxy in
                let route = LandingJourney(size: proxy.size)
                let point = route.point(at: phase)
                let opacity = reduceMotion ? 1 : min(1, min(phase / 0.08, (1 - phase) / 0.08))
                ZStack {
                    RoundedRectangle(cornerRadius: 36)
                        .fill(LinearGradient(colors: [Color.promptMint.opacity(0.28), Color.promptSky.opacity(0.14), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    // Quiet longitude rings suggest the world without competing with text.
                    ForEach(0..<4) { index in
                        Ellipse()
                            .stroke(Color.promptAccent.opacity(0.07), lineWidth: 0.75)
                            .frame(width: proxy.size.width * CGFloat(index + 2) / 3, height: 210)
                            .rotationEffect(.degrees(-24))
                    }
                    route.path
                        .stroke(Color.promptAccent.opacity(0.17), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 7]))
                    route.path.trim(from: 0, to: route.pathFraction(at: phase))
                        .stroke(LinearGradient(colors: [Color.promptMintDeep.opacity(0.03), Color.promptMintDeep.opacity(0.65)],
                                               startPoint: .bottomLeading, endPoint: .topTrailing),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    waypoint(symbol: "mappin", title: "Your next chapter", color: .promptAccent)
                        .position(x: proxy.size.width * 0.3, y: 48)
                    waypoint(symbol: "character.bubble", title: "A little practice. A world of confidence.", color: .promptAccent)
                        .frame(maxWidth: proxy.size.width - 38)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height - 35)

                    Circle().fill(Color.promptMintDeep.opacity(0.3)).frame(width: 7, height: 7)
                        .position(route.point(at: 0))
                    Circle().fill(Color.promptMintDeep.opacity(0.3)).frame(width: 7, height: 7)
                        .position(route.point(at: 1))

                    Image(systemName: "airplane")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.promptAccent)
                        .rotationEffect(.radians(route.angle(at: phase)))
                        .frame(width: 62, height: 62)
                        .modifier(LandingGlass(reduceTransparency: reduceTransparency))
                        .shadow(color: Color.promptMintDeep.opacity(0.12), radius: 16, y: 8)
                        .opacity(opacity)
                        .position(point)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(.rect(cornerRadius: 36))
            }
        }
        .frame(height: 252)
        .onAppear { start = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { start = .now } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A flight route arriving at a city")
    }

    private func waypoint(symbol: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(LocalizedStringKey(title)).foregroundStyle(.primary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground).opacity(reduceTransparency ? 1 : 0.8), in: Capsule())
    }
}

private struct LandingGlass: ViewModifier {
    let reduceTransparency: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: Circle())
        } else {
            content.background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
    }
}

struct LandingJourney {
    let size: CGSize
    private var start: CGPoint { CGPoint(x: size.width * 0.08, y: size.height * 0.67) }
    private var control1: CGPoint { CGPoint(x: size.width * 0.42, y: size.height * 0.7) }
    private var control2: CGPoint { CGPoint(x: size.width * 0.52, y: size.height * 0.19) }
    private var end: CGPoint { CGPoint(x: size.width * 0.91, y: size.height * 0.33) }

    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    func point(at fraction: Double) -> CGPoint {
        rawPoint(at: parameter(at: fraction))
    }

    private func rawPoint(at t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u*u*u*start.x + 3*u*u*t*control1.x + 3*u*t*t*control2.x + t*t*t*end.x,
                       y: u*u*u*start.y + 3*u*u*t*control1.y + 3*u*t*t*control2.y + t*t*t*end.y)
    }

    func angle(at fraction: Double) -> Double {
        let t = parameter(at: fraction)
        let u = 1 - t
        let dx = 3*u*u*(control1.x-start.x) + 6*u*t*(control2.x-control1.x) + 3*t*t*(end.x-control2.x)
        let dy = 3*u*u*(control1.y-start.y) + 6*u*t*(control2.y-control1.y) + 3*t*t*(end.y-control2.y)
        return atan2(dy, dx)
    }

    // Path.trim uses distance, not Bézier parameter t. Approximate arc length
    // so the trail and plane stay together and speed feels even on curves.
    func pathFraction(at fraction: Double) -> CGFloat {
        CGFloat(parameter(at: fraction))
    }

    private func parameter(at fraction: Double) -> Double {
        let fraction = min(1, max(0, fraction))
        var lengths: [Double] = [0]
        var previous = rawPoint(at: 0)
        for index in 1...48 {
            let current = rawPoint(at: Double(index) / 48)
            lengths.append(lengths[index - 1] + hypot(current.x - previous.x, current.y - previous.y))
            previous = current
        }
        let target = fraction * (lengths.last ?? 0)
        for index in 1...48 where lengths[index] >= target {
            let segment = lengths[index] - lengths[index - 1]
            return (Double(index - 1) + (segment > 0 ? (target - lengths[index - 1]) / segment : 0)) / 48
        }
        return 1
    }
}
