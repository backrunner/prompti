import SwiftData
import SwiftUI

private enum GenerationRecovery: Equatable {
    case retry
    case modelSettings
    case adjustPractice
}

private struct GenerationFailure: Equatable {
    let message: String
    let recovery: GenerationRecovery
}

private enum GenerationPhase: Equatable {
    case preparing
    case connecting
    case reviewing
    case ready
    case failed(GenerationFailure)

    var title: String {
        switch self {
        case .preparing: "Preparing your conversation"
        case .connecting: "Creating useful questions"
        case .reviewing: "Checking safety and quality"
        case .ready: "Ready to practice"
        case .failed: "This set could not be prepared"
        }
    }

    var isWorking: Bool {
        switch self {
        case .preparing, .connecting, .reviewing: true
        case .ready, .failed: false
        }
    }

    var symbol: String {
        switch self {
        case .preparing: "text.bubble.fill"
        case .connecting: "questionmark.bubble.fill"
        case .reviewing: "checkmark.shield.fill"
        case .ready: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var stageIndex: Int {
        switch self {
        case .preparing: 0
        case .connecting: 1
        case .reviewing: 2
        case .ready: 3
        case .failed: -1
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var accessibilityID: String {
        switch self {
        case .preparing: "preparing"
        case .connecting: "generating"
        case .reviewing: "reviewing"
        case .ready: "ready"
        case .failed: "failed"
        }
    }
}

private enum GenerationStage: Int, CaseIterable, Identifiable {
    case context
    case questions
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .context: "Context"
        case .questions: "Create"
        case .review: "Check quality"
        }
    }

    var symbol: String {
        switch self {
        case .context: "text.bubble.fill"
        case .questions: "text.bubble.fill"
        case .review: "checkmark.shield.fill"
        }
    }
}

private enum GenerationOperation {
    case initial
    case fillRemaining(Int)
}

struct GenerationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PracticeFlow.self) private var practiceFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let request: TrainingRequest
    let onCancel: () -> Void

    @State private var providerSnapshot: ProviderConfiguration?
    @State private var jobID = UUID()
    @State private var phase = GenerationPhase.preparing
    @State private var records: [QuestionRecord] = []
    @State private var operationID = UUID()
    @State private var operation = GenerationOperation.initial
    @State private var shouldRunOperation = true
    @State private var showSettings = false
    @State private var routeProgress: CGFloat = 0

    var body: some View {
        ZStack {
            PromptiBackground()
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        routeCard
                        status
                        stageStrip

                        if phase == .ready {
                            readyManifest
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, PromptiSpacing.page)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 640)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(proxy.size.height - 24, 0),
                        alignment: .center
                    )
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !phase.isWorking {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left", action: onCancel)
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("generation.back")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actions
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PromptiSpacing.page)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(PromptiActionScrim())

        }
        .task(id: operationID) {
            guard shouldRunOperation else { return }
            shouldRunOperation = false
            await generate(operation)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onAppear { updateRouteProgress(for: phase) }
        .onChange(of: phase) { _, newPhase in
            updateRouteProgress(for: newPhase)
        }
        .sensoryFeedback(.success, trigger: phase == .ready)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(request.destination.localizedCity, systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .accessibilityIdentifier("generation.destination.\(request.destination.id)")
                Spacer()
                HStack(spacing: 4) {
                    Text("\(request.count)")
                        .monospacedDigit()
                    Text("questions")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.promptMuted)
            }

            PracticeJourneyVisual(
                progress: routeProgress,
                destinationSymbol: request.destination.symbol,
                isComplete: phase == .ready
            )
            .frame(height: 112)
        }
        .padding(18)
        .promptiHeroSurface()
    }

    private var status: some View {
        VStack(spacing: 10) {
            Image(systemName: phase.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(phase.isFailed ? Color.promptError : Color.promptAccent)
            Text(LocalizedStringKey(phase.title))
                .font(PromptiTypography.title)
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("generation.phase.\(phase.accessibilityID)")
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generation.status")
        .accessibilityValue(phase.accessibilityID)
    }

    private var stageStrip: some View {
        stageStripContent
            .frame(maxWidth: .infinity)
            .padding(12)
            .promptiSurface()
        .accessibilityElement(children: .contain)
    }

    private var stageStripContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(GenerationStage.allCases) { stage in
                    stageItem(stage)
                    if stage != GenerationStage.allCases.last {
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(GenerationStage.allCases) { stage in
                    stageItem(stage)
                }
            }
        }
    }

    private func stageItem(_ stage: GenerationStage) -> some View {
        let isComplete = phase.stageIndex > stage.rawValue
        let isActive = phase.stageIndex == stage.rawValue
        let localizedTitle = NSLocalizedString(stage.title, comment: "Generation stage title")
        let status = isComplete ? "complete" : isActive ? "in progress" : "up next"
        let localizedStatus = NSLocalizedString(status, comment: "Generation stage status")
        return HStack(spacing: 7) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : stage.symbol)
                .foregroundStyle(isComplete || isActive ? Color.promptAccent : Color.promptMuted)
            Text(LocalizedStringKey(stage.title))
                .font(.caption.weight(isActive ? .bold : .semibold))
                .foregroundStyle(isActive || isComplete ? Color.promptText : Color.promptMuted)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
        .accessibilityLabel("\(localizedTitle), \(localizedStatus)")
    }

    private var readyManifest: some View {
        PromptiSectionSurface() {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Practice set", systemImage: "rectangle.stack.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(records.count) / \(request.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.promptAccent)
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        manifestDetail(request.language.localName, symbol: "character.bubble.fill")
                        manifestDetail(request.difficulty.title, symbol: "gauge.with.dots.needle.67percent")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        manifestDetail(request.language.localName, symbol: "character.bubble.fill")
                        manifestDetail(request.difficulty.title, symbol: "gauge.with.dots.needle.67percent")
                    }
                }

                if !request.scenes.isEmpty {
                    Label(localizedSceneList, systemImage: "map.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.promptMuted)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generation.manifest")
        .accessibilityValue("\(records.count) of \(request.count)")
    }

    private func manifestDetail(_ text: String, symbol: String) -> some View {
        Label {
            Text(LocalizedStringKey(text))
        } icon: {
            Image(systemName: symbol)
        }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.promptMuted)
    }

    private var localizedSceneList: String {
        request.scenes
            .map(\.localizedTitle)
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch phase {
            case .ready:
                Button {
                    practiceFlow.showSession(records, request: request, configuration: providerSnapshot)
                } label: {
                    Label {
                        HStack(spacing: 5) {
                            Text("Start practice")
                            Text("· \(records.count)")
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("generation.start")

                if records.count < request.count {
                    Button("Try to add \(request.count - records.count) more", systemImage: "arrow.clockwise") {
                        run(.fillRemaining(request.count - records.count))
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityIdentifier("generation.fillRemaining")
                }
            case .failed(let failure):
                if !records.isEmpty {
                    Button("Start prepared questions · \(records.count)") {
                        practiceFlow.showSession(records, request: request, configuration: providerSnapshot)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityIdentifier("generation.startPrepared")
                }
                recoveryButton(for: failure)
            case .preparing, .connecting, .reviewing:
                Button("Cancel generation", role: .cancel, action: onCancel)
                    .buttonStyle(CompactGlassButtonStyle())
                    .accessibilityIdentifier("generation.cancel")
            }
        }
    }

    @ViewBuilder
    private func recoveryButton(for failure: GenerationFailure) -> some View {
        switch failure.recovery {
        case .retry:
            Button("Try again", systemImage: "arrow.clockwise") {
                run(remainingOperation)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityIdentifier("generation.recovery.retry")
        case .modelSettings:
            Button("Open model settings", systemImage: "gearshape") {
                showSettings = true
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityIdentifier("generation.recovery.settings")
            Button("Try again", systemImage: "arrow.clockwise") {
                providerSnapshot = dependencies.settings.provider
                run(remainingOperation)
            }
                .buttonStyle(SecondaryActionButtonStyle())
                .accessibilityIdentifier("generation.recovery.retry")
        case .adjustPractice:
            Button("Adjust practice", systemImage: "slider.horizontal.3") {
                _ = practiceFlow.cancel()
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .accessibilityIdentifier("generation.recovery.adjust")
        }
    }

    private var statusDetail: String {
        switch phase {
        case .preparing:
            String(localized: "Using approved destination facts.")
        case .connecting:
            String(localized: "Your model is generating a small, practical set.")
        case .reviewing:
            String(localized: "Nothing appears in your tray until it passes review.")
        case .ready:
            records.count == request.count
                ? String(localized: "All questions passed review.")
                : String(localized: "Start with approved questions. The rest will be prepared as you practice.")
        case .failed(let failure):
            failure.message
        }
    }

    private func run(_ operation: GenerationOperation) {
        self.operation = operation
        shouldRunOperation = true
        operationID = UUID()
    }

    private var remainingOperation: GenerationOperation {
        records.isEmpty ? .initial : .fillRemaining(max(1, request.count - records.count))
    }

    private func updateRouteProgress(for phase: GenerationPhase) {
        let target: CGFloat
        switch phase {
        case .preparing: target = 0.14
        case .connecting: target = 0.56
        case .reviewing: target = 0.84
        case .ready: target = 1
        case .failed: return
        }

        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
            routeProgress = target
        }
    }

    private func generate(_ operation: GenerationOperation) async {
        phase = .preparing
        do {
            try await Task.sleep(for: .milliseconds(250))

            let configuration = providerSnapshot ?? dependencies.settings.provider
            providerSnapshot = configuration
            var activeRequest = request
            activeRequest.count = min(configuration.kind == .apple ? 2 : 3, request.count)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-prompti-demo"), !ProcessInfo.processInfo.arguments.contains("-prompti-ui-auto-fill") { activeRequest.count = request.count }
            #endif
            if case .fillRemaining(let count) = operation {
                activeRequest.count = count
            }

            let existing = try modelContext.fetch(FetchDescriptor<QuestionRecord>()).filter {
                $0.destinationID == request.destination.id && $0.languageCode == request.language.code && $0.explanationLanguageCode == request.explanationLanguage.rawValue
            }
            activeRequest.previousPrompts = Array(existing.sorted { $0.createdAt < $1.createdAt }.suffix(30).map(\.prompt))
            let generated = try await dependencies.generation.generate(
                activeRequest,
                configuration: configuration, jobID: jobID,
                excluding: Set(existing.map { $0.question.contentSignature })
            ) { stage in
                await MainActor.run {
                    phase = stage == .generating ? .connecting : .reviewing
                }
            }
            try Task.checkCancellation()

            let saved = try QuestionInventory.save(generated, request: activeRequest, context: modelContext)
            guard !saved.isEmpty else { throw GenerationError.noApprovedQuestions }
            switch operation {
            case .initial:
                records = saved
            case .fillRemaining:
                records.append(contentsOf: saved)
            }
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(failure(for: error))
        }
    }

    private func failure(for error: Error) -> GenerationFailure {
        guard let error = error as? GenerationError else {
            return GenerationFailure(message: error.localizedDescription, recovery: .retry)
        }

        switch error {
        case .missingAPIKey, .invalidCredential, .modelUnavailable, .unsupportedProvider, .insufficientCredit, .invalidEndpoint, .permissionDenied, .modelNotFound:
            return GenerationFailure(message: error.localizedDescription, recovery: .modelSettings)
        case .invalidScene, .unsafeContent, .noApprovedQuestions, .refused, .truncatedOutput:
            return GenerationFailure(message: error.localizedDescription, recovery: .adjustPractice)
        case .rateLimited, .providerUnavailable, .malformedResponse, .timedOut, .networkUnavailable:
            return GenerationFailure(message: error.localizedDescription, recovery: .retry)
        }
    }
}
