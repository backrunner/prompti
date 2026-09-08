import SwiftUI

/// A result, not animated progress: the arc always represents the actual accuracy.
struct PromptiResultVisual: View {
    let value: String
    let label: String
    let accuracy: Double?
    let isPerfect: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = PromptiTypography.resultValueSize
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 204

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.promptBorder.opacity(0.6), lineWidth: 2)
                .padding(PromptiSpacing.inline)
            if let accuracy, accuracy > 0 {
                Circle()
                    .trim(from: 0, to: min(max(accuracy, 0), 1))
                    .stroke(Color.promptAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(PromptiSpacing.inline)
                    .accessibilityHidden(true)
            }
            VStack(spacing: PromptiSpacing.inline) {
                Text(verbatim: value)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.promptText)
                Text(LocalizedStringKey(label))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.promptMuted)
            }
            .padding(PromptiSpacing.page)
        }
        .frame(width: diameter, height: diameter)
        .promptiHeroSurface(in: Circle())
        .overlay(alignment: .bottomTrailing) {
            if isPerfect {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.promptOnAction)
                    .padding(PromptiSpacing.related)
                    .background(Color.promptAction, in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A finite, deterministic burst. The owner removes it after `duration`;
/// Reduce Motion and scene inactivity remove it immediately.
struct PromptiConfettiBurst: View {
    static let duration: TimeInterval = 1.8
    @State private var startedAt = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                Canvas { context, size in
                    guard elapsed >= 0, elapsed < Self.duration else { return }
                    let colors: [Color] = [.promptAccent, .promptMint, .promptText]
                    for index in 0..<42 {
                        let delay = Double(index % 7) * 0.025
                        let age = elapsed - delay
                        guard age > 0 else { continue }
                        let side = index.isMultiple(of: 2) ? -1.0 : 1.0
                        let spread = Double((index * 17) % 23) / 22
                        let x = size.width * (side < 0 ? 0.22 : 0.78)
                            + side * (35 + spread * 105) * age
                        let y = size.height * 0.32 - (110 + spread * 160) * age + 190 * age * age
                        let fade = min(1, max(0, (Self.duration - elapsed) / 0.5))
                        var particle = context
                        particle.opacity = fade
                        particle.translateBy(x: x, y: y)
                        particle.rotate(by: .degrees(Double(index * 37) + age * side * 210))
                        let rect = CGRect(x: -3, y: -5, width: index.isMultiple(of: 3) ? 6 : 4, height: 10)
                        let path = index.isMultiple(of: 4)
                            ? Path(ellipseIn: CGRect(x: -3, y: -3, width: 6, height: 6))
                            : Path(roundedRect: rect, cornerRadius: 1)
                        particle.fill(path, with: .color(colors[index % colors.count]))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
