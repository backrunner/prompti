import SwiftData
import SwiftUI

private enum ReviewMode: String, CaseIterable, Identifiable {
    case mistakes = "Mistakes"
    case skipped = "Skipped"
    case history = "History"
    case reported = "Reported"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .mistakes: "arrow.counterclockwise"
        case .skipped: "forward.fill"
        case .history: "clock.arrow.circlepath"
        case .reported: "exclamationmark.bubble.fill"
        }
    }
}

private enum ReviewDateFilter: String, CaseIterable, Identifiable {
    case all = "Any time"
    case week = "Last 7 days"
    case month = "Last 30 days"

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .all: nil
        case .week: 7
        case .month: 30
        }
    }
}

private struct ReviewFilterOption: Identifiable {
    let id: String
    let title: String
}

private struct ReviewStatus {
    let title: String
    let symbol: String
    let tint: Color
}

struct ReviewView: View {
    @Binding var selectedTab: AppTab
    @Query(sort: \QuestionRecord.createdAt, order: .reverse) private var questions: [QuestionRecord]
    @Query(sort: \AttemptRecord.createdAt, order: .reverse) private var attempts: [AttemptRecord]

    @State private var mode = ReviewMode.mistakes
    @State private var destinationFilter = "all"
    @State private var languageFilter = "all"
    @State private var sceneFilter = "all"
    @State private var dateFilter = ReviewDateFilter.all

    private var attemptsByQuestion: [UUID: [AttemptRecord]] {
        Dictionary(grouping: attempts, by: \AttemptRecord.questionID)
    }

    private var modeQuestions: [QuestionRecord] {
        questions.filter { question in
            let history = attemptsByQuestion[question.id] ?? []
            switch mode {
            case .mistakes:
                return !question.isQuarantined && history.contains { $0.result == .incorrect }
            case .skipped:
                return !question.isQuarantined && history.contains { $0.result == .skipped }
            case .history:
                return !question.isQuarantined && !history.isEmpty
            case .reported:
                return history.contains { $0.result == .reported }
            }
        }
    }

    private var visibleQuestions: [QuestionRecord] {
        modeQuestions.filter(matchesFilters)
    }

    private var practiceableQuestions: [QuestionRecord] {
        guard mode == .mistakes || mode == .skipped else { return [] }
        return visibleQuestions.filter { !$0.isQuarantined }
    }

    private var destinationOptions: [ReviewFilterOption] {
        Dictionary(grouping: questions, by: \QuestionRecord.destinationID)
            .compactMap { id, questions in
                questions.first.map { ReviewFilterOption(id: id, title: $0.destinationName) }
            }
            .sorted { $0.title < $1.title }
    }

    private var languageOptions: [ReviewFilterOption] {
        Set(questions.map(\.languageCode))
            .map { code in
                ReviewFilterOption(
                    id: code,
                    title: Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
                )
            }
            .sorted { $0.title < $1.title }
    }

    private var sceneOptions: [ReviewFilterOption] {
        Set(questions.map(\.sceneTitle))
            .map { ReviewFilterOption(id: $0, title: $0) }
            .sorted { $0.title < $1.title }
    }

    private var activeFilterCount: Int {
        [destinationFilter, languageFilter, sceneFilter].count(where: { $0 != "all" })
            + (dateFilter == .all ? 0 : 1)
    }

    var body: some View {
        ZStack {
            PromptiBackground()
            VStack(spacing: 14) {
                Picker("Review mode", selection: $mode) {
                    ForEach(ReviewMode.allCases) { item in
                        Text(LocalizedStringKey(item.rawValue))
                            .accessibilityIdentifier("review.mode.\(item.id.lowercased())")
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if activeFilterCount > 0 {
                    HStack {
                        Label(activeFilterSummary, systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear", action: clearFilters)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 16)
                }

                content
            }
            .padding(.top, 8)
        }
        .navigationTitle("Review")
        .accessibilityIdentifier("review.root")
        .toolbar { filterToolbar }
        .safeAreaInset(edge: .bottom) {
            if !practiceableQuestions.isEmpty {
                NavigationLink {
                    PracticeSessionView(records: practiceableQuestions)
                } label: {
                    Label(
                        mode == .mistakes ? "Practice all mistakes" : "Practice skipped questions",
                        systemImage: mode.symbol
                    )
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibleQuestions.isEmpty {
            PromptiEmptyState(
                symbol: emptyState.symbol,
                title: emptyState.title,
                message: emptyState.message
            )
            .frame(maxHeight: .infinity, alignment: .center)

            if activeFilterCount == 0, mode != .reported {
                Button("Start practicing", systemImage: "play.fill") {
                    selectedTab = .practice
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .padding(.horizontal, 16)
                .frame(maxWidth: 560)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(visibleQuestions) { question in
                        if mode == .reported {
                            reviewRow(question)
                        } else {
                            NavigationLink {
                                PracticeSessionView(records: [question])
                            } label: {
                                reviewRow(question)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func reviewRow(_ question: QuestionRecord) -> some View {
        let status = status(for: question)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(LocalizedStringKey(question.sceneTitle), systemImage: question.question.kind.symbol)
                Spacer()
                Text(question.destinationName)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(question.prompt)
                .font(.body.weight(.semibold))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Label(LocalizedStringKey(status.title), systemImage: status.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(status.tint)
                Spacer()
                if mode != .reported {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .foregroundStyle(Color.primary)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: PromptiRadius.surface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("review.question.\(question.id.uuidString)")
    }

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Destination", selection: $destinationFilter) {
                    Text("All destinations").tag("all")
                    ForEach(destinationOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                Picker("Language", selection: $languageFilter) {
                    Text("All languages").tag("all")
                    ForEach(languageOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                Picker("Scene", selection: $sceneFilter) {
                    Text("All scenes").tag("all")
                    ForEach(sceneOptions) { option in
                        Text(LocalizedStringKey(option.title)).tag(option.id)
                    }
                }
                Picker("Date", selection: $dateFilter) {
                    ForEach(ReviewDateFilter.allCases) { item in
                        Text(LocalizedStringKey(item.rawValue)).tag(item)
                    }
                }
                if activeFilterCount > 0 {
                    Divider()
                    Button("Clear filters", systemImage: "xmark.circle", action: clearFilters)
                }
            } label: {
                Image(systemName: activeFilterCount > 0
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter review")
            .accessibilityValue(activeFilterCount == 0 ? String(localized: "No active filters") : activeFilterSummary)
            .accessibilityIdentifier("review.filters")
        }
    }

    private var emptyState: (symbol: String, title: String, message: String) {
        if activeFilterCount > 0 {
            return ("line.3.horizontal.decrease.circle", "No matching questions", "Clear a filter or choose a broader review range.")
        }
        switch mode {
        case .mistakes:
            return ("checkmark.seal", "No mistakes waiting", "Questions you miss will stay here, even after you master them later.")
        case .skipped:
            return ("forward.fill", "No skipped questions", "Questions you skip will wait here when you are ready to return.")
        case .history:
            return ("clock.arrow.circlepath", "No question history yet", "Complete a practice set to build your travel phrase history.")
        case .reported:
            return ("checkmark.shield", "No reported questions", "Questions you report are isolated and listed here for reference.")
        }
    }

    private func status(for question: QuestionRecord) -> ReviewStatus {
        let history = attemptsByQuestion[question.id] ?? []
        let latest = history.first
        switch mode {
        case .mistakes:
            if latest?.result == .correct {
                return ReviewStatus(title: "Recently mastered", symbol: "checkmark.seal.fill", tint: .promptMintDeep)
            }
            return ReviewStatus(title: "Needs another look", symbol: "arrow.counterclockwise", tint: .promptCoral)
        case .skipped:
            return ReviewStatus(title: "Skipped earlier", symbol: "forward.fill", tint: .promptSky)
        case .history:
            return ReviewStatus(title: "Practice this question", symbol: "play.fill", tint: .promptMintDeep)
        case .reported:
            let reason = history.first(where: { $0.result == .reported })
                .flatMap { ReportReason(rawValue: $0.reasonRaw) }?.title
            return ReviewStatus(
                title: reason ?? "Removed from future practice",
                symbol: "exclamationmark.shield.fill",
                tint: .promptCoral
            )
        }
    }

    private func matchesFilters(_ question: QuestionRecord) -> Bool {
        guard destinationFilter == "all" || question.destinationID == destinationFilter else { return false }
        guard languageFilter == "all" || question.languageCode == languageFilter else { return false }
        guard sceneFilter == "all" || question.sceneTitle == sceneFilter else { return false }
        guard let dayCount = dateFilter.dayCount else { return true }
        let cutoff = Calendar.current.date(byAdding: .day, value: -dayCount, to: .now) ?? .distantPast
        return (attemptsByQuestion[question.id] ?? []).contains { $0.createdAt >= cutoff }
    }

    private func clearFilters() {
        destinationFilter = "all"
        languageFilter = "all"
        sceneFilter = "all"
        dateFilter = .all
    }

    private var activeFilterSummary: String {
        String.localizedStringWithFormat(
            String(localized: "%lld active filters"),
            activeFilterCount
        )
    }
}
