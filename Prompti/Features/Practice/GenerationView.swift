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
    case paused
    case failed(GenerationFailure)

    var title: String {
        switch self {
        case .preparing: "Preparing your conversation"
        case .connecting: "Creating useful questions"
        case .reviewing: "Checking safety and quality"
        case .ready: "Ready to practice"
        case .paused: "Preparation paused"
        case .failed: "This set could not be prepared"
        }
    }

    var isWorking: Bool {
        switch self {
        case .preparing, .connecting, .reviewing: true
        case .ready, .paused, .failed: false
        }
    }

    var symbol: String {
        switch self {
        case .preparing: "text.bubble.fill"
        case .connecting: "questionmark.bubble.fill"
        case .reviewing: "checkmark.shield.fill"
        case .ready: "checkmark.seal.fill"
        case .paused: "pause.circle"
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
        case .paused, .failed: -1
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
        case .paused: "paused"
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
    @Environment(\.scenePhase) private var scenePhase

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
    private var readyThreshold: Int { 1 }

    private var autoStart: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-prompti-ui-manual-start")
        #else
        return true
        #endif
    }

    private var phase: GenerationPhase {
        if session.isPaused { return .paused }
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

    /// Only saved, approved questions move the journey forward.
    private var progressTarget: CGFloat {
        CGFloat(records.count) / CGFloat(max(1, request.count))
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

                        if !records.isEmpty {
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
            session.fillIfNeeded(using: dependencies.generation, context: modelContext)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .onAppear {
            updateRouteProgress()
            maybeOpenSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.cancelFill() }
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
                isComplete: records.count == request.count
            )
            .frame(height: 112)
        }
        .padding(18)
        .promptiHeroSurface()
    }

    private var status: some View {
        VStack(spacing: 10) {
            Group {
                if phase.isWorking && !reduceMotion {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.promptAccent)
                } else {
                    Image(systemName: phase.isWorking ? "hourglass" : phase.symbol)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(phase.isFailed ? Color.promptError : Color.promptAccent)
                }
            }
            .frame(height: 36)
            .accessibilityHidden(true)
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
            if phase.isWorking {
                PreparationActivity(session: session, showsIndicator: false)
            }
            if !records.isEmpty {
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

    private var stageStrip: some View {
        HStack(spacing: PromptiSpacing.related) {
            ForEach(GenerationStage.allCases) { stage in
                Label(LocalizedStringKey(stage.title), systemImage: stage.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phase.stageIndex == stage.rawValue ? Color.promptText : Color.promptMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PromptiSpacing.related)
                    .background(phase.stageIndex == stage.rawValue ? Color.promptSelection : .clear,
                                in: RoundedRectangle(cornerRadius: PromptiRadius.compact))
                    .accessibilityValue(Text(LocalizedStringKey(phase.stageIndex > stage.rawValue
                        ? "complete" : phase.stageIndex == stage.rawValue ? "in progress" : "up next")))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("generation.progress")
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
            if !records.isEmpty {
                if let message = session.fillMessage {
                    InlineNotice(symbol: "exclamationmark.circle", text: message, tone: .warning)
                }
                Button(action: openSession) {
                    Label {
                        HStack(spacing: 5) {
                            Text("Start practice")
                            Text("· \(records.count)").monospacedDigit()
                        }
                    } icon: { Image(systemName: "play.fill") }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("generation.start")

                if session.isFilling {
                    Button("Pause preparation", systemImage: "pause.fill") { session.cancelFill() }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .accessibilityIdentifier("generation.pause")
                } else if session.hasRemaining {
                    Button("Try to add \(request.count - records.count) more", systemImage: "arrow.clockwise", action: retryFill)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .accessibilityIdentifier("generation.fillRemaining")
                }
            } else {
                switch phase {
                case .failed(let failure):
                    recoveryButton(for: failure)
                case .paused:
                    Button("Continue preparation", systemImage: "play.fill", action: retryFill)
                        .buttonStyle(PrimaryActionButtonStyle())
                        .accessibilityIdentifier("generation.resume")
                default:
                    EmptyView()
                }
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
        case .paused:
            String(localized: "Prepared questions are saved. Continue whenever you’re ready.")
        case .ready:
            records.count == request.count
                ? String(localized: "All questions passed review.")
                : String(localized: "Start with approved questions, or retry to prepare the rest.")
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
        if let error = error as? TypeSafeReviewError {
            return GenerationFailure(message: error.localizedDescription, recovery: error.needsSettings ? .modelSettings : .retry)
        }
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

/// Shared, observable progress for initial generation and an in-session wait.
/// Counts describe active requests, never an estimated completion percentage.
struct PreparationActivity: View {
    let session: PracticeSessionState
    var showsIndicator = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: PromptiSpacing.related) {
            HStack(spacing: PromptiSpacing.related) {
                if showsIndicator {
                    if reduceMotion { Image(systemName: "hourglass") }
                    else { ProgressView().tint(Color.promptAction) }
                }
                if session.generatingCount + session.reviewingCount > 0 {
                    Text("Creating \(session.generatingCount) · Checking \(session.reviewingCount)")
                } else {
                    Text("Waiting for your model")
                }
            }
            .font(.subheadline)
            if let startedAt = session.fillStartedAt {
                HStack(spacing: PromptiSpacing.inline) {
                    Text("Elapsed")
                    Text(startedAt, style: .timer).monospacedDigit()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(Color.promptMuted)
        .accessibilityIdentifier("generation.activity")
    }
}
