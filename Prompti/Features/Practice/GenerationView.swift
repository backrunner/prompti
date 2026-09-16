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

    /// Furthest pipeline index; never regresses while one fill is running.
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
        case .context: "map.fill"
        case .questions: "questionmark.bubble.fill"
        case .review: "checkmark.shield.fill"
        }
    }
}

struct GenerationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PracticeFlow.self) private var practiceFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: TrainingRequest
    let session: PracticeSessionState
    let onCancel: () -> Void

    @State private var showSettings = false
    @State private var routeProgress: CGFloat = 0
    /// Auto-entry happens once; after the user returns here, re-entering is a
    /// manual choice so swiping back never bounces them forward again.
    @State private var autoEntered = false

    private var records: [QuestionRecord] { session.records }
    /// Enough approved questions to start while the rest keep generating.
    private var readyThreshold: Int { min(3, request.count) }

    private var autoStart: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-prompti-ui-manual-start")
        #else
        return true
        #endif
    }

    private var phase: GenerationPhase {
        if session.isFilling || (records.isEmpty && session.fillError == nil) {
            switch session.furthestStage {
            case .reviewing: return .reviewing
            case .generating: return .connecting
            case nil: return .preparing
            }
        }
        if records.isEmpty, let fillError = session.fillError {
            return .failed(failure(for: fillError))
        }
        return .ready
    }

    /// Approved-question throughput with a small floor per reached stage, so
    /// the bar always moves forward even when a batch is sent back internally.
    private var progressTarget: CGFloat {
        let approved = CGFloat(records.count) / CGFloat(max(1, request.count))
        let floor: CGFloat
        switch phase {
        case .preparing: floor = 0.05
        case .connecting: floor = 0.15
        case .reviewing: floor = 0.55
        case .ready: floor = 1
        case .failed: floor = 0
        }
        if case .failed = phase { return routeProgress }
        return min(1, max(floor, approved))
    }

    var body: some View {
        ZStack {
            PromptiBackground()
            GeometryReader { proxy in
                PromptiScrollView {
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
        .task {
            session.fill(using: dependencies.generation, context: modelContext)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onAppear {
            updateRouteProgress()
            maybeOpenSession()
        }
        .onChange(of: progressTarget) { _, _ in updateRouteProgress() }
        .onChange(of: records.count) { _, _ in maybeOpenSession() }
        .onChange(of: session.isFilling) { _, _ in maybeOpenSession() }
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
                destination: request.destination,
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
            if phase.isWorking || phase == .ready {
                Text("\(records.count) of \(request.count) questions prepared")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.promptAccent)
                    .accessibilityIdentifier("generation.prepared")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("generation.status")
        .accessibilityValue(phase.accessibilityID)
    }

    /// The three pipeline steps form one progress bar: the fill tracks prepared
    /// questions and never shrinks when a batch is sent back for regeneration.
    private var stageStrip: some View {
        let progress = min(max(routeProgress, 0), 1)
        return HStack(spacing: 0) {
            ForEach(GenerationStage.allCases) { stage in
                stageItem(stage, progress: progress)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                    .fill(Color.promptSurface)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                        .fill(Color.promptAction)
                        .frame(width: proxy.size.width * progress)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous)
                .strokeBorder(Color.promptBorder.opacity(0.65), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generation.progress")
    }

    private func stageItem(_ stage: GenerationStage, progress: CGFloat) -> some View {
        let isComplete = phase.stageIndex > stage.rawValue
        let isActive = phase.stageIndex == stage.rawValue
        // Once the fill passes the middle of a stage's third, its label sits on
        // the action color and switches to the on-action ink.
        let covered = progress >= (CGFloat(stage.rawValue) + 0.5) / CGFloat(GenerationStage.allCases.count)
        let localizedTitle = NSLocalizedString(stage.title, comment: "Generation stage title")
        let status = isComplete ? "complete" : isActive ? "in progress" : "up next"
        let localizedStatus = NSLocalizedString(status, comment: "Generation stage status")
        return HStack(spacing: 7) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : stage.symbol)
                .foregroundStyle(covered ? Color.promptOnAction : isComplete || isActive ? Color.promptAccent : Color.promptMuted)
            Text(LocalizedStringKey(stage.title))
                .font(.caption.weight(isActive ? .bold : .semibold))
                .foregroundStyle(covered ? Color.promptOnAction : isActive || isComplete ? Color.promptText : Color.promptMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
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
                if let message = session.fillMessage {
                    InlineNotice(symbol: "exclamationmark.circle", text: message, tone: .warning)
                }
                Button {
                    openSession()
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

                if session.hasRemaining {
                    Button("Try to add \(request.count - records.count) more", systemImage: "arrow.clockwise") {
                        session.fill(using: dependencies.generation, context: modelContext)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityIdentifier("generation.fillRemaining")
                }
            case .failed(let failure):
                if !records.isEmpty {
                    Button("Start prepared questions · \(records.count)") {
                        openSession()
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
                retryFill()
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
                retryFill()
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

    private func retryFill() {
        session.configuration = dependencies.settings.provider
        session.fill(using: dependencies.generation, context: modelContext)
    }

    private func openSession() {
        autoEntered = true
        practiceFlow.openSession(session)
    }

    private func maybeOpenSession() {
        guard autoStart, !autoEntered else { return }
        guard records.count >= readyThreshold || (!session.isFilling && !records.isEmpty) else { return }
        openSession()
    }

    private func updateRouteProgress() {
        // The journey marker only moves forward: a top-up retry after ready, or
        // a batch sent back to generation, must not visibly regress the bar.
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) {
            routeProgress = max(routeProgress, progressTarget)
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
