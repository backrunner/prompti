import SwiftUI

struct DestinationStamp: View {
    let destination: Destination
    var compact = false
    var showsDisclosure = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: destination.symbol)
                .font(.system(size: compact ? 18 : 22, weight: .semibold))
                .foregroundStyle(Color.promptInk)
                .frame(width: compact ? 38 : 48, height: compact ? 38 : 48)
                .background(Color.promptSun, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(destination.city)
                    .font(compact ? .headline : .title2.weight(.black))
                    .fontDesign(.rounded)
                Text(destination.country.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            Spacer(minLength: 0)
            Image(systemName: showsDisclosure ? "chevron.right" : "airplane.departure")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(stampAccent)
        }
        .padding(compact ? 12 : 18)
        .background(Color.promptSky.opacity(0.16), in: RoundedRectangle(cornerRadius: PromptiRadius.surface, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PromptiRadius.surface, style: .continuous)
                .strokeBorder(stampAccent.opacity(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    private var stampAccent: Color {
        colorScheme == .dark ? .promptMint : .promptMintDeep
    }
}

struct SceneChoiceButton: View {
    let scene: TravelScene
    let isSelected: Bool
    var emphasizesDestination = false

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: scene.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : sceneTint)
                .frame(width: 30, height: 30)
                .background(
                    isSelected ? Color.white.opacity(0.16) : sceneTint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: PromptiRadius.compact, style: .continuous)
                )
            Text(LocalizedStringKey(scene.title))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 4)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            isSelected ? Color.promptMintDeep : Color(.secondarySystemGroupedBackground).opacity(0.78),
            in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.07))
        }
    }

    private var sceneTint: Color {
        emphasizesDestination ? .promptCoral : .promptMintDeep
    }
}

struct FlightRouteVisual: View, Animatable {
    nonisolated var progress: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    let destinationSymbol: String
    let isComplete: Bool
    var active = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let clampedProgress = min(max(progress, 0), 1)
            let planePoint = routePoint(in: size, progress: clampedProgress)

            ZStack(alignment: .topLeading) {
                FlightRouteShape()
                    .stroke(
                        Color.primary.opacity(0.13),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 8])
                    )

                FlightRouteShape()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        Color.promptMintDeep,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.promptCoral)
                    .position(x: 22, y: size.height * 0.78)

                Image(systemName: isComplete ? "checkmark.seal.fill" : destinationSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.promptInk)
                    .frame(width: 48, height: 48)
                    .background(Color.promptSun, in: Circle())
                    .scaleEffect(isComplete ? 1 : 0.92)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isComplete)
                    .position(x: size.width - 28, y: size.height * 0.3)

                Image(systemName: "airplane")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.promptInk)
                    .padding(8)
                    .background(Color(.systemBackground).opacity(0.88), in: Circle())
                    .shadow(color: Color.promptInk.opacity(0.12), radius: 8, y: 4)
                    .rotationEffect(.radians(atan2(
                        2 * (1 - clampedProgress) * (-size.height * 0.8) + 2 * clampedProgress * (size.height * 0.32),
                        2 * (1 - clampedProgress) * (size.width * 0.48 - 22) + 2 * clampedProgress * (size.width * 0.52 - 28)
                    )))
                    .symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)
                    .scaleEffect(isComplete ? 0.72 : 1)
                    .opacity(isComplete ? 0 : 1)
                    .animation(reduceMotion ? nil : .bouncy(duration: 0.42), value: isComplete)
                    .position(planePoint)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func routePoint(in size: CGSize, progress: CGFloat) -> CGPoint {
        let start = CGPoint(x: 22, y: size.height * 0.78)
        let control = CGPoint(x: size.width * 0.48, y: -size.height * 0.02)
        let end = CGPoint(x: size.width - 28, y: size.height * 0.3)
        let inverse = 1 - progress
        return CGPoint(
            x: inverse * inverse * start.x + 2 * inverse * progress * control.x + progress * progress * end.x,
            y: inverse * inverse * start.y + 2 * inverse * progress * control.y + progress * progress * end.y
        )
    }
}

private struct FlightRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22, y: rect.height * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - 28, y: rect.height * 0.3),
            control: CGPoint(x: rect.width * 0.48, y: -rect.height * 0.02)
        )
        return path
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
                .font(.title2.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text(LocalizedStringKey(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.promptMint : Color.promptMintDeep)
                .frame(width: 72, height: 72)
                .background(Color.promptMint.opacity(0.45), in: Circle())
            Text(LocalizedStringKey(title))
                .font(.title3.bold())
            Text(LocalizedStringKey(message))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
        .padding(24)
    }
}

struct InlineNotice: View {
    let symbol: String
    let text: String
    var tint: Color = .promptSky

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.primary)
            Text(LocalizedStringKey(text))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.25), in: RoundedRectangle(cornerRadius: PromptiRadius.compact, style: .continuous))
    }
}
