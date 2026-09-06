import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PracticeFlow.self) private var practiceFlow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \AttemptRecord.createdAt, order: .reverse) private var attempts: [AttemptRecord]
    @Query(sort: \QuestionRecord.createdAt, order: .reverse) private var questions: [QuestionRecord]
    @State private var showSettings = false
    @State private var showDestinationPicker = false
    @State private var inventoryMessage: String?

    private var destination: Destination {
        dependencies.settings.selectedDestination(in: dependencies.catalog)
    }

    private var destinationAttempts: [AttemptRecord] {
        attempts.filter { $0.destinationID == destination.id }
    }

    private var scoredDestinationAttempts: [AttemptRecord] {
        destinationAttempts.filter { $0.result == .correct || $0.result == .incorrect }
    }

    private var todayAttempts: [AttemptRecord] {
        scoredDestinationAttempts.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var correctCount: Int { scoredDestinationAttempts.filter { $0.result == .correct }.count }
    private var streakCount: Int {
        PracticeMetrics.consecutiveDayCount(dates: scoredDestinationAttempts.map(\.createdAt))
    }
    private var availableQuestions: [QuestionRecord] {
        let attemptedIDs = Set(attempts.map(\.questionID))
        return questions.filter {
            !$0.isQuarantined && !attemptedIDs.contains($0.id)
                && $0.destinationID == destination.id
                && $0.languageCode == dependencies.settings.languageCode
        }
    }

    var body: some View {
        ZStack {
            PromptiBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header
                    tripHero
                    quickStart
                    metrics
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape.fill") { showSettings = true }
                    .accessibilityIdentifier("home.settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showDestinationPicker) {
            DestinationPickerView(selection: destinationBinding)
        }
        .task(id: inventoryContext) {
            await prepareInventoryIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Label {
                Text(LocalizedStringKey(todayAttempts.isEmpty ? "Ready for your next stop" : "Keep your route moving"))
            } icon: {
                Image(systemName: "airplane.departure")
                    .foregroundStyle(Color.promptMintDeep)
            }
            .font(.title3.bold())
            Spacer()
            Image(systemName: "sun.max.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.promptSun)
        }
        .padding(.top, 8)
    }

    private var tripHero: some View {
        Button {
            showDestinationPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Next stop")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.promptMintDeep)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .frame(width: 42, height: 42)
                        .background(Color(.systemBackground).opacity(0.55), in: Circle())
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) {
                        destinationName
                        Spacer()
                        destinationHeroSymbol
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        destinationHeroSymbol
                        destinationName
                    }
                }
                PromptiFlowLayout(spacing: 8) {
                    ForEach(destination.languages.prefix(3)) { language in
                        Text(language.localName)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground).opacity(0.5), in: Capsule())
                    }
                }
            }
            .padding(24)
            .foregroundStyle(Color.primary)
            .background(
                LinearGradient(
                    colors: [Color.promptMint.opacity(0.28), Color.promptSky.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: PromptiRadius.hero, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose another destination")
        .accessibilityIdentifier("home.destination")
    }

    private var destinationName: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(destination.city)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fontDesign(.rounded)
            Text(destination.country)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
    }

    private var destinationHeroSymbol: some View {
        Image(systemName: destination.symbol)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Color.promptInk)
            .frame(width: 76, height: 76)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.75), in: .rect(cornerRadius: 24))
            .accessibilityHidden(true)
    }

    private var quickStart: some View {
        VStack(spacing: 12) {
            Button { startPractice(count: dependencies.settings.questionCount) } label: {
                Label("Start practicing", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityIdentifier("home.startPractice")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { quickQuestionButton; customizeButton }
                VStack(spacing: 10) { quickQuestionButton; customizeButton }
            }
            if let inventoryMessage {
                Text(LocalizedStringKey(inventoryMessage))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var quickQuestionButton: some View {
        Button { startPractice(count: 1) } label: {
            Label("Quick question", systemImage: "bolt")
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .accessibilityIdentifier("home.quickQuestion")
    }

    private var customizeButton: some View {
        Button { selectedTab = .practice } label: {
            Label("Customize", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(SecondaryActionButtonStyle())
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            SectionLabel("This trip")
            LazyVGrid(columns: metricColumns, spacing: 10) {
                MetricTile(value: "\(todayAttempts.count)", label: "today", symbol: "checkmark.circle.fill", tint: .promptMintDeep)
                MetricTile(value: "\(correctCount)", label: "correct", symbol: "star.fill", tint: .promptSun)
                MetricTile(value: "\(streakCount)", label: "streak", symbol: "flame.fill", tint: .promptCoral)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(spacing: 12) {
            SectionLabel("Question tray")
            if availableQuestions.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles").foregroundStyle(Color.promptAccent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A small practice goes a long way.").font(.subheadline.weight(.semibold))
                        Text("Start a set to build confidence for your next trip.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
                .promptiSurface()
            } else {
                ForEach(availableQuestions.prefix(3)) { question in
                    Button {
                        openPractice { practiceFlow.startSession([question], origin: .quickQuestion) }
                    } label: {
                    HStack(spacing: 12) {
                        Image(systemName: question.question.kind.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.promptMintDeep)
                            .frame(width: 36, height: 36)
                            .background(Color.promptMint.opacity(0.35), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(question.prompt).lineLimit(2).font(.subheadline.weight(.semibold))
                            Text("\(question.destinationName) · \(question.sceneTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .promptiSurface(radius: PromptiRadius.control)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Practice this question")
                }
            }
        }
    }

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    private var destinationBinding: Binding<Destination> {
        Binding(
            get: { destination },
            set: { newValue in
                dependencies.settings.selectDestination(newValue, in: dependencies.catalog)
            }
        )
    }

    private var inventoryContext: String {
        "\(dependencies.settings.isPreGenerationEnabled)|\(destination.id)|\(dependencies.settings.languageCode)|\(dependencies.settings.provider)"
    }

    private func prepareInventoryIfNeeded() async {
        guard dependencies.settings.isPreGenerationEnabled, availableQuestions.count < 3 else { return }
        inventoryMessage = "Preparing a few approved questions while Prompti is open."
        let destination = dependencies.settings.selectedDestination(in: dependencies.catalog)
        let language = destination.languages.first(where: { $0.code == dependencies.settings.languageCode }) ?? destination.languages[0]
        let request = TrainingRequest(
            destination: destination,
            language: language,
            explanationLanguage: dependencies.settings.explanationLanguage,
            scenes: Array(dependencies.catalog.commonScenes.prefix(2)),
            customScene: nil,
            difficulty: dependencies.settings.difficulty,
            kinds: [.cloze, .multipleChoice],
            count: 3
        )
        do {
            let generated = try await dependencies.generation.generate(request, configuration: dependencies.settings.provider)
            try Task.checkCancellation()
            for (offset, question) in generated.enumerated() {
                let scene = request.scenes[offset % request.scenes.count]
                modelContext.insert(QuestionRecord(question: question, request: request, scene: scene))
            }
            try modelContext.save()
            inventoryMessage = "Your approved question tray has been topped up."
        } catch is CancellationError {
            return
        } catch {
            inventoryMessage = "Advance preparation paused: \(error.localizedDescription)"
        }
    }

    private func startPractice(count: Int) {
        let ready = Array(availableQuestions.prefix(count))
        let language = destination.languages.first(where: { $0.code == dependencies.settings.languageCode }) ?? destination.languages[0]
        let request = TrainingRequest(
            destination: destination,
            language: language,
            explanationLanguage: dependencies.settings.explanationLanguage,
            scenes: Array(dependencies.catalog.commonScenes.prefix(2)),
            customScene: nil,
            difficulty: dependencies.settings.difficulty,
            kinds: [.cloze, .multipleChoice],
            count: count
        )
        openPractice {
            if ready.count == count {
                practiceFlow.startSession(ready, origin: .quickQuestion)
            } else {
                practiceFlow.startGeneration(request, origin: .quickQuestion)
            }
        }
    }

    private func openPractice(_ action: @escaping @MainActor () -> Void) {
        selectedTab = .practice
        // Mount the practice stack before replacing its path. Switching the tab
        // and pushing a destination in the same update can leave tab animations
        // unfinished when that destination also hides the tab bar.
        Task { @MainActor in
            await Task.yield()
            guard selectedTab == .practice else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, action)

        }
    }
}
