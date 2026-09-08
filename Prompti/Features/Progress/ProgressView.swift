import Charts
import SwiftData
import SwiftUI

private struct DayProgress: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private struct ProgressDistributionItem: Identifiable {
    let id: String
    let label: String
    let count: Int
}

struct ProgressDashboardView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \AttemptRecord.createdAt) private var attempts: [AttemptRecord]

    private var scored: [AttemptRecord] { AttemptRecord.scored(in: attempts) }
    private var correct: Int { scored.filter { $0.result == .correct }.count }
    private var accuracy: Int { scored.isEmpty ? 0 : Int((Double(correct) / Double(scored.count) * 100).rounded()) }
    private var streakCount: Int { PracticeMetrics.consecutiveDayCount(dayKeys: scored.map(\.localDayKey)) }
    private var dayProgress: [DayProgress] {
        let calendar = Calendar.current
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return nil }
            let count = scored.count(where: { $0.localDayKey == PracticeMetrics.localDayKey(for: day) })
            return DayProgress(date: day, count: count)
        }
    }
    private var languageProgress: [ProgressDistributionItem] {
        distribution(for: scored.map(\.languageCode)) { code in
            Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
        }
    }
    private var sceneProgress: [ProgressDistributionItem] {
        distribution(for: scored.map(\.sceneTitle)) { title in
            scored.first(where: { $0.sceneTitle == title })?.localizedSceneTitle ?? title
        }
    }

    var body: some View {
        ZStack {
            PromptiBackground()
            PromptiScrollView {
                VStack(spacing: 20) {
                    if scored.isEmpty {
                        VStack(spacing: 14) {
                            PromptiEmptyState(
                                symbol: "chart.line.uptrend.xyaxis",
                                title: "Your progress starts here",
                                message: "Complete a scored question to unlock accuracy and weekly trends."
                            )
                            Button("Start practicing", systemImage: "play.fill") {
                                selectedTab = .practice
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                        }
                        .frame(maxWidth: 560)
                    } else {
                        LazyVGrid(columns: metricColumns, spacing: 10) {
                            MetricTile(value: "\(accuracy)%", label: "accuracy", symbol: "scope", tint: .promptAccent)
                            MetricTile(value: "\(scored.count)", label: "answered", symbol: "text.book.closed.fill", tint: .promptMuted)
                            MetricTile(value: "\(streakCount)", label: "streak", symbol: "flame.fill", tint: .promptAccent)
                        }
                        .accessibilityIdentifier("progress.metrics")

                        VStack(alignment: .leading, spacing: 16) {
                            SectionLabel("Last 7 days", subtitle: "Answered questions, excluding skips")
                            Chart(dayProgress) { day in
                                BarMark(
                                    x: .value(String(localized: "Day"), day.date, unit: .day),
                                    y: .value(String(localized: "Questions"), day.count)
                                )
                                .foregroundStyle(Color.promptAccent.gradient)
                                .cornerRadius(4)
                            }
                            .chartYAxis { AxisMarks(position: .leading) { AxisGridLine(); AxisValueLabel() } }
                            .frame(height: 190)
                            .accessibilityLabel("Questions answered during the last 7 days")
                        }
                        .padding(16)
                        .promptiSurface()

                        practiceMix
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("How Prompti counts")
                        InlineNotice(symbol: "forward.fill", text: "Skipped and reported questions never reduce your accuracy.")
                        InlineNotice(symbol: "waveform", text: "Spoken answers with uncertain transcription are saved for practice but not scored.", tone: .neutral)
                    }
                }
                .padding(16)
                .padding(.bottom, 96)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Progress")
        .accessibilityIdentifier("progress.root")
    }

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    private var practiceMix: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Practice mix", subtitle: "Your most practiced languages and situations")
            PromptiSectionSurface() {
                VStack(spacing: 18) {
                    distributionGroup("Languages", symbol: "character.bubble.fill", items: languageProgress)
                    Divider()
                    distributionGroup("Scenes", symbol: "map.fill", items: sceneProgress)
                }
            }
        }
        .accessibilityIdentifier("progress.mix")
    }

    private func distributionGroup(
        _ title: String,
        symbol: String,
        items: [ProgressDistributionItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(LocalizedStringKey(title), systemImage: symbol)
                .font(.subheadline.bold())
            ForEach(items.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.label)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(item.count)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(Color.promptMuted)
                    }
                    ProgressView(value: Double(item.count), total: Double(max(scored.count, 1)))
                        .tint(Color.promptAccent)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func distribution(
        for values: [String],
        label: (String) -> String
    ) -> [ProgressDistributionItem] {
        Dictionary(grouping: values, by: { $0 })
            .map { key, values in
                ProgressDistributionItem(id: key, label: label(key), count: values.count)
            }
            .sorted {
                if $0.count == $1.count { return $0.label < $1.label }
                return $0.count > $1.count
            }
    }
}
