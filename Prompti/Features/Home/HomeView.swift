import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PracticeFlow.self) private var practiceFlow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
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
        AttemptRecord.scored(in: destinationAttempts)
    }

    private var todayAttempts: [AttemptRecord] {
        scoredDestinationAttempts.filter { $0.localDayKey == PracticeMetrics.localDayKey() }
    }

    private var correctCount: Int { scoredDestinationAttempts.filter { $0.result == .correct }.count }
    private var streakCount: Int {
        PracticeMetrics.consecutiveDayCount(dayKeys: scoredDestinationAttempts.map(\.localDayKey))
    }
    private var availableQuestions: [QuestionRecord] {
        QuestionInventory.available(questions, attempts: attempts, destinationID: destination.id,
            languageCode: dependencies.settings.languageCode, explanationLanguage: dependencies.settings.explanationLanguage,
            difficulty: dependencies.settings.difficulty)
    }

    var body: some View {
        ZStack {
            PromptiBackground()
            PromptiScrollView {
                VStack(spacing: 22) {
                    header
                    tripHero
                    quickStart
                    metrics
                    recentSection
                }
                .padding(.horizontal, PromptiSpacing.page)
                .padding(.bottom, 24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 10) {
            PromptiWordmark()
            Text(LocalizedStringKey(todayAttempts.isEmpty ? "Your next conversation starts here." : "A little practice. More confidence."))
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .foregroundStyle(Color.promptAccent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(Color.promptText)
                        .frame(width: 42, height: 42)
                        .background(Color.promptSurface, in: Circle())
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
                            .background(Color.promptSurface, in: Capsule())
                    }
                }
            }
            .padding(24)
            .foregroundStyle(Color.promptText)
            .promptiHeroSurface()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose another destination")
        .accessibilityIdentifier("home.destination")
    }

    private var destinationName: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(destination.localizedCity)
                .font(PromptiTypography.hero)
                .fontDesign(.rounded)
            Text(destination.localizedCountry)
                .font(.subheadline.bold())
                .foregroundStyle(Color.promptMuted)
        }
    }

    private var destinationHeroSymbol: some View {
        DestinationArtwork(destination: destination, size: 68)
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
                    .font(.footnote).foregroundStyle(Color.promptMuted)
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
                MetricTile(value: "\(todayAttempts.count)", label: "today", symbol: "checkmark.circle.fill", tint: .promptAccent)
                MetricTile(value: "\(correctCount)", label: "correct", symbol: "checkmark.seal.fill", tint: .promptSuccess)
                MetricTile(value: "\(streakCount)", label: "streak", symbol: "flame.fill", tint: .promptAccent)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(spacing: 12) {
            SectionLabel("Question tray")
            if availableQuestions.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    PromptiBrandMark(height: 26).foregroundStyle(Color.promptAccent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A small practice goes a long way.").font(.subheadline.weight(.semibold))
                        Text("Start a set to build confidence for your next trip.")
                            .font(.footnote).foregroundStyle(Color.promptMuted)
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
                            .foregroundStyle(Color.promptAccent)
                            .frame(width: 36, height: 36)
                            .background(Color.promptSurfaceRaised, in: .rect(cornerRadius: PromptiRadius.compact))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(question.prompt).lineLimit(2).font(.subheadline.weight(.semibold))
                            Text("\(question.localizedDestinationName) · \(question.localizedSceneTitle)")
                                .font(.caption)
                                .foregroundStyle(Color.promptMuted)
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
        "\(dependencies.settings.isPreGenerationEnabled)|\(scenePhase)|\(selectedTab)|\(destination.id)|\(dependencies.settings.languageCode)|\(dependencies.settings.difficulty)|\(dependencies.settings.explanationLanguage)|\(dependencies.settings.provider)|\(dependencies.inventoryConditions.hasNetwork)|\(dependencies.inventoryConditions.usesWiFi)|\(dependencies.settings.inventoryTarget)|\(dependencies.settings.dailyPreparationLimit)|\(dependencies.settings.preparationWiFiOnly)"
    }

    private func prepareInventoryIfNeeded() async {
        let settings = dependencies.settings
        guard settings.isPreGenerationEnabled, scenePhase == .active, selectedTab == .today,
              dependencies.inventoryConditions.allowsPreparation(wifiOnly: settings.preparationWiFiOnly, onDevice: settings.provider.kind == .apple),
              availableQuestions.count < settings.inventoryTarget else { return }
        guard settings.provider.kind == .apple || dependencies.secureStore.readAPIKey(for: settings.provider) != nil else { return }
        let count = settings.reservePreparationCount(min(3, settings.inventoryTarget - availableQuestions.count))
        guard count > 0 else {
            inventoryMessage = "Advance preparation has reached today's limit. You can still start practice yourself."
            return
        }
        inventoryMessage = "Preparing a few approved questions while Prompti is open."
        let destination = dependencies.settings.selectedDestination(in: dependencies.catalog)
        let language = destination.languages.first(where: { $0.code == dependencies.settings.languageCode }) ?? destination.languages[0]
        var request = TrainingRequest(
            destination: destination,
            language: language,
            explanationLanguage: dependencies.settings.explanationLanguage,
            scenes: Array(dependencies.catalog.commonScenes.prefix(2)),
            customScene: nil,
            difficulty: dependencies.settings.difficulty,
            kinds: [.cloze, .multipleChoice],
            count: count
        )
        request.previousPrompts = Array(questions.filter { $0.destinationID == destination.id && $0.languageCode == language.code }.prefix(30).map(\.prompt))
        do {
            let generated = try await dependencies.generation.generate(request, configuration: dependencies.settings.provider,
                excluding: Set(questions.filter { $0.destinationID == destination.id && $0.languageCode == language.code }.map { $0.question.contentSignature }),
                allowsRegeneration: false)
            try Task.checkCancellation()
            _ = try QuestionInventory.save(generated, request: request, context: modelContext)
            inventoryMessage = "Your approved question tray has been topped up."
        } catch is CancellationError {
            return
        } catch {
            modelContext.rollback()
            inventoryMessage = String(localized: "Advance preparation paused: \(error.localizedDescription)")
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
