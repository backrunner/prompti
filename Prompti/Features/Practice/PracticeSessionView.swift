import SwiftData
import SwiftUI
import AVFoundation

struct PracticeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @Environment(AppDependencies.self) private var dependencies
    @State private var session: PracticeSessionState
    private var records: [QuestionRecord] { session.records }
    let onFinish: (() -> Void)?

    @FocusState private var editingTranscript: Bool
    @State private var index = 0
    @State private var selectedAnswer: String?
    @State private var blankSelections: [String: String] = [:]
    @State private var isEvaluating = false
    @State private var evaluationTask: Task<Void, Never>?
    @State private var evaluationID = UUID()
    @State private var providerSnapshot: ProviderConfiguration?
    @State private var transcriptEdited = false
    @State private var result: AttemptResult?
    @State private var completed = false
    @State private var counts = SessionResultCounts()
    @State private var showReport = false
    @State private var showExitConfirmation = false
    @State private var speech = SpeechPracticeModel()
    @State private var speechEvaluation: SpeechEvaluation?
    @State private var persistenceError: String?
    @State private var showPersistenceError = false
    @State private var summaryRouteProgress: CGFloat = 0
    @State private var summaryReveal = false
    @State private var summaryCelebrated = false
    @State private var correctFeedback = 0
    @State private var incorrectFeedback = 0

    init(records: [QuestionRecord], onFinish: (() -> Void)? = nil) {
        _session = State(initialValue: PracticeSessionState(records: records))
        self.onFinish = onFinish
    }

    init(session: PracticeSessionState, onFinish: (() -> Void)? = nil) {
        _session = State(initialValue: session)
        self.onFinish = onFinish
    }

    private var current: QuestionRecord { records[index] }
    private var question: GeneratedQuestion { current.question }

    var body: some View {
        ZStack {
            PromptiBackground()
            if records.isEmpty {
                PromptiEmptyState(symbol: "tray", title: "No questions available",
                                  message: "Return to practice and prepare another set.")
            } else if completed {
                summary
            } else if index >= records.count {
                waitingForQuestions
            } else {
                questionContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar { sessionToolbar }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if completed {
                Button("Done", action: finishFlow)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityIdentifier("session.done")
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, PromptiSpacing.page)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(PromptiActionScrim())

            } else if index < records.count {
                primaryQuestionAction
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .padding(.horizontal, PromptiSpacing.page).padding(.vertical, 10)
                    .background(PromptiActionScrim())
            }
        }
        .alert("Progress was not saved", isPresented: $showPersistenceError) { } message: {
            Text(persistenceError ?? "Try again.")
        }
        .onChange(of: index) { _, _ in
            speech.reset()
            speechEvaluation = nil
        }
        .task {
            providerSnapshot = session.configuration ?? dependencies.settings.provider
            session.fill(using: dependencies.generation, context: modelContext)
        }
        .onDisappear {
            speech.reset()
            cancelEvaluation()
            session.cancelFill()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                speech.reset()
                cancelEvaluation()
                session.cancelFill()
            } else {
                session.fill(using: dependencies.generation, context: modelContext)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in speech.reset() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                speech.reset()
            }
        }
        .sensoryFeedback(.success, trigger: correctFeedback)
        .sensoryFeedback(.warning, trigger: incorrectFeedback)
        .sensoryFeedback(.success, trigger: completed)
    }

    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        if !completed, !records.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Button("End practice", systemImage: "xmark") {
                    showExitConfirmation = true
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("session.close")
                .confirmationDialog(
                    "End this practice set?",
                    isPresented: $showExitConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("End practice", role: .destructive, action: finishFlow)
                        .accessibilityIdentifier("session.confirmExit")
                    Button("Keep practicing", role: .cancel) { }
                } message: {
                    Text("Completed answers are saved. The current unanswered question will not be counted.")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu("Question options", systemImage: "ellipsis") {
                    Button("Skip question", systemImage: "forward.fill", action: skip)
                        .disabled(result != nil || isEvaluating || index >= records.count)
                        .accessibilityIdentifier("session.skip")
                    Button("Question may be wrong", systemImage: "exclamationmark.bubble", role: .destructive) {
                        showReport = true
                    }
                    .disabled(isEvaluating || index >= records.count)
                }
                .accessibilityIdentifier("session.options")
                .confirmationDialog(
                    "What seems wrong?",
                    isPresented: $showReport,
                    titleVisibility: .visible
                ) {
                    ForEach(ReportReason.allCases) { reason in
                        Button(reason.title, role: .destructive) {
                            report(reason)
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("The question will be removed from future practice and will not count as a wrong answer.")
                }
            }
        }
    }

    private var questionContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                progressHeader
                questionPrompt

                if question.kind == .spoken {
                    spokenPanel
                } else if let cloze = question.cloze {
                    clozeOptions(cloze)
                } else {
                    answerOptions
                }

                if let result {
                    feedback(result)
                }

            }
            .padding(16)
            .padding(.bottom, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(index + 1) / \(session.requestedCount)")
                        .font(.subheadline.bold())
                    Spacer()
                    Label(LocalizedStringKey(current.sceneTitle), systemImage: question.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(Color.promptMuted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question \(index + 1) of \(session.requestedCount)")
                        .font(.headline)
                    Label(LocalizedStringKey(current.sceneTitle), systemImage: question.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(Color.promptMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if session.hasRemaining {
                Text("\(records.count) of \(session.requestedCount) questions prepared")
                    .font(.caption).foregroundStyle(Color.promptMuted)
                    .accessibilityIdentifier("session.preparationStatus")
            }
            ProgressView(value: Double(index + 1), total: Double(session.requestedCount))
                .tint(Color.promptAccent)
        }
        .accessibilityElement(children: .combine)
    }

    private var questionPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(question.kind.title))
                .textCase(.uppercase)
                .font(.caption.bold())
                .foregroundStyle(Color.promptAccent)
            Text(displayPrompt)
                .font(PromptiTypography.title)
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(question.translation)
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
        }
        .padding(18)
        .promptiSurface()
    }

    private var displayPrompt: String {
        guard let cloze = question.cloze, cloze.segments.count == cloze.blanks.count + 1 else { return question.prompt }
        return cloze.blanks.indices.reduce(cloze.segments[0]) {
            $0 + (blankSelections[cloze.blanks[$1].id] ?? "[\($1 + 1)]") + cloze.segments[$1 + 1]
        }
    }

    private var waitingForQuestions: some View {
        VStack(spacing: 16) {
            if session.isFilling {
                ProgressView("Preparing the remaining questions")
            } else {
                Text("Prepared questions completed").font(PromptiTypography.title)
                if let error = session.fillError { Text(error).foregroundStyle(Color.promptMuted) }
                Button("Retry remaining questions") { session.fill(using: dependencies.generation, context: modelContext) }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .accessibilityIdentifier("session.retryFill")
                Button("Finish with completed questions") { completed = true }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityIdentifier("session.finishPartial")
            }
            Text("\(records.count) of \(session.requestedCount) questions prepared")
                .font(.subheadline).foregroundStyle(Color.promptMuted)
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.waiting")
    }

    private func clozeOptions(_ cloze: ClozeContent) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(cloze.blanks.enumerated()), id: \.element.id) { offset, blank in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gap \(offset + 1)").font(.headline)
                    ForEach(blank.options, id: \.self) { option in
                        let chosen = blankSelections[blank.id] == option
                        let revealedCorrect = result != nil && option == blank.correctAnswer
                        let wrong = result != nil && chosen && option != blank.correctAnswer
                        Button { if result == nil { blankSelections[blank.id] = option } } label: {
                            HStack {
                                Text(option)
                                Spacer()
                                Image(systemName: revealedCorrect ? "checkmark.seal.fill" : wrong ? "xmark.circle.fill"
                                    : chosen ? "checkmark.circle.fill" : "circle")
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .modifier(PromptiAnswerStyle(state: wrong ? .incorrect : revealedCorrect ? .correct : chosen ? .selected : .idle))
                        }
                        .buttonStyle(PromptiAnswerButtonStyle())
                        .disabled(result != nil)
                        .accessibilityIdentifier("session.blank.\(offset).\(blank.options.firstIndex(of: option) ?? 0)")
                        .accessibilityValue(revealedCorrect ? "Correct answer" : wrong ? "Your answer, incorrect" : chosen ? "Selected" : "Not selected")
                    }
                }
            }
        }
    }

    private var answerOptions: some View {
        VStack(spacing: 9) {
            ForEach(question.options) { option in
                Button {
                    guard result == nil else { return }
                    selectedAnswer = option.text
                } label: {
                    HStack(spacing: 12) {
                        Text(option.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: optionSymbol(option.text))
                    }
                    .font(.body.bold())
                    .padding(15)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .modifier(PromptiAnswerStyle(state: optionState(option.text)))
                }
                .buttonStyle(PromptiAnswerButtonStyle())
                .disabled(result != nil)
                .accessibilityValue(optionAccessibilityValue(option.text))
                .accessibilityIdentifier("session.option.\(option.id.uuidString)")
            }
        }
    }

    private var spokenPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            InlineNotice(
                symbol: "lock.shield.fill",
                text: "Speech is transcribed for this attempt. Your model receives the transcript for meaning feedback. Raw audio is not saved or synced."
            )

            ViewThatFits(in: .horizontal) {
                HStack {
                    hearPromptButton
                    Spacer()
                    recordButton
                }
                VStack(spacing: 10) {
                    hearPromptButton
                    recordButton
                }
            }

            TextEditor(text: Binding(
                get: { speech.transcript },
                set: { speech.transcript = String($0.prefix(1000)); transcriptEdited = true }
            ))
                .disabled(result != nil || isEvaluating || speech.isRecording || speech.isTranscribing)
                .accessibilityIdentifier("session.transcript")
                .accessibilityLabel("Your transcript will appear here.")
                .focused($editingTranscript)
                .font(.body)
                .foregroundStyle(Color.promptText)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    if speech.transcript.isEmpty {
                        Text("Your transcript will appear here.")
                            .font(.body).foregroundStyle(Color.promptMuted)
                            .padding(.horizontal, 5).padding(.vertical, 8)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(12)
                .background(Color.promptSurfaceRaised, in: .rect(cornerRadius: PromptiRadius.control))

            if !speech.transcript.isEmpty, result == nil {
                Button("Record again", systemImage: "arrow.clockwise") {
                    speech.clearTranscript()
                    transcriptEdited = false
                }
                .buttonStyle(CompactGlassButtonStyle())
                .disabled(isEvaluating || speech.isRecording || speech.isTranscribing)
            }

            if speech.permissionState == .denied {
                Button("Open Settings", systemImage: "gearshape", action: openSystemSettings)
                    .buttonStyle(CompactGlassButtonStyle())
            }

            if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.promptMuted)
            }
        }
    }

    private var hearPromptButton: some View {
        Button("Hear prompt", systemImage: "speaker.wave.2.fill") {
            speech.speak(question.prompt, languageCode: current.languageCode, rate: dependencies.settings.speechRate)
        }
        .buttonStyle(CompactGlassButtonStyle())
        .disabled(speech.isRecording || speech.isTranscribing)
        .frame(minHeight: 44)
    }

    private var recordButton: some View {
        Button {
            transcriptEdited = false
            Task { await speech.toggleRecording(languageCode: current.languageCode) }
        } label: {
            if speech.isTranscribing {
                Label("Finishing transcript", systemImage: "waveform")
            } else if speech.permissionState == .requesting {
                Label("Requesting access", systemImage: "mic.badge.plus")
            } else {
                Label(
                    speech.isRecording ? "Stop recording" : "Record answer",
                    systemImage: speech.isRecording ? "stop.fill" : "mic.fill"
                )
            }
        }
        .buttonStyle(RecordingActionButtonStyle(isRecording: speech.isRecording))
        .disabled(result != nil || isEvaluating || speech.permissionState == .requesting || speech.isTranscribing)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var primaryQuestionAction: some View {
        if result == nil {
            Button(LocalizedStringKey(primaryActionTitle), action: submit)
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(primaryActionDisabled)
                .accessibilityIdentifier("session.submit")
        } else {
            Button(index == records.count - 1 && !session.hasRemaining ? "See trip summary" : "Next question", action: advance)
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("session.next")
        }
    }

    private var speechFallbackAvailable: Bool {
        question.kind == .spoken
            && speech.transcript.isEmpty
            && (speech.permissionState == .denied || speech.errorMessage != nil)
    }

    private var primaryActionTitle: String {
        if isEvaluating { return "Checking meaning" }
        if speechFallbackAvailable { return "View sample answer" }
        return question.kind == .spoken ? "Compare answer" : "Check answer"
    }

    private var primaryActionDisabled: Bool {
        if isEvaluating { return true }
        if let cloze = question.cloze { return cloze.blanks.contains { blankSelections[$0.id] == nil } }
        if question.kind != .spoken { return selectedAnswer == nil }
        return (!speechFallbackAvailable && speech.transcript.isEmpty) || speech.isRecording || speech.isTranscribing
    }

    private func feedback(_ result: AttemptResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(feedbackTitle(result), systemImage: result == .correct ? "checkmark.seal.fill" : "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(feedbackTone(result).foreground)

            if let speechEvaluation {
                Text(speechEvaluation.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.promptMuted)
                Text("Sample: \(question.sampleAnswer ?? question.correctAnswer)")
                    .font(.body.bold())
                Button("Hear sample answer", systemImage: "speaker.wave.2.fill") {
                    speech.speak(question.sampleAnswer ?? question.correctAnswer, languageCode: current.languageCode,
                                 rate: dependencies.settings.speechRate)
                }
                .buttonStyle(CompactGlassButtonStyle())
                .accessibilityIdentifier("session.hearSample")
            } else {
                if result != .correct {
                    Text("Answer: \(question.sampleAnswer ?? question.correctAnswer)")
                        .font(.body.bold())
                }
                Text(question.explanation)
                    .font(.subheadline)
                    .foregroundStyle(Color.promptMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(feedbackTone(result).background, in: .rect(cornerRadius: PromptiRadius.surface))
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    summaryHero

                    LazyVGrid(columns: summaryMetricColumns, spacing: 10) {
                        SummaryMetricCell(value: "\(counts.correct)", label: "correct", symbol: "checkmark", tint: .promptSuccess)
                        SummaryMetricCell(value: "\(counts.incorrect)", label: "review", symbol: "arrow.counterclockwise", tint: .promptWarning)
                        SummaryMetricCell(value: "\(counts.skipped)", label: "skipped", symbol: "forward.fill", tint: .promptMuted)
                        SummaryMetricCell(value: "\(counts.undetermined)", label: "not scored", symbol: "waveform", tint: .promptMuted)
                    }
                    .opacity(summaryReveal ? 1 : 0)
                    .offset(y: summaryReveal ? 0 : 10)

                    if counts.reported > 0 {
                        InlineNotice(
                            symbol: "exclamationmark.bubble.fill",
                            text: "\(counts.reported) reported question was removed from future practice.",
                            tone: .warning
                        )
                    }

                    summaryReward
                        .opacity(summaryReveal ? 1 : 0)
                        .scaleEffect(summaryReveal ? 1 : 0.94)
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
        .onAppear(perform: playSummaryCelebration)
    }

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    summaryHeaderCopy
                    Spacer(minLength: 0)
                    summaryScoreBadge
                }
                VStack(alignment: .leading, spacing: 12) {
                    summaryHeaderCopy
                    summaryScoreBadge
                }
            }

            PracticeJourneyVisual(
                progress: summaryRouteProgress,
                destinationSymbol: "flag.checkered",
                isComplete: summaryReveal
            )
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 126 : 112)
        }
        .padding(18)
        .promptiHeroSurface()
        .accessibilityElement(children: .contain)
    }

    private var summaryHeaderCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(LocalizedStringKey(session.hasRemaining ? "Prepared questions completed" : "Practice complete"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.promptAccent)
            Text("A little more confident.")
                .font(PromptiTypography.hero)
                .fontDesign(.rounded)
                .accessibilityIdentifier("session.summary")
            if session.hasRemaining {
                Text("\(records.count) of \(session.requestedCount) questions prepared")
                    .font(.subheadline).foregroundStyle(Color.promptMuted)
            }
            Text(LocalizedStringKey(summaryMessage))
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryScoreBadge: some View {
        VStack(spacing: 1) {
            Text(summaryPrimaryValue)
                .font(.title.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(LocalizedStringKey(summaryPrimaryLabel))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.promptMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.promptSurface, in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
        .scaleEffect(summaryReveal ? 1 : 0.94)
        .opacity(summaryReveal ? 1 : 0)
    }

    private var summaryReward: some View {
        VStack(spacing: 9) {
            PromptiSymbolBadge(symbol: "checkmark.bubble.fill", size: 56)
                .symbolEffect(.bounce, value: reduceMotion ? false : summaryReveal)
                .accessibilityHidden(true)
            Text("Progress saved")
                .font(.headline)
            Text("Your next conversation just got easier.")
                .font(.subheadline)
                .foregroundStyle(Color.promptMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var summaryMetricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.flexible()), GridItem(.flexible())]
        }
    }

    private var scoredCount: Int {
        counts.correct + counts.incorrect
    }

    private var accuracy: Int {
        guard scoredCount > 0 else { return 0 }
        return Int((Double(counts.correct) / Double(scoredCount) * 100).rounded())
    }

    private var summaryPrimaryValue: String {
        scoredCount > 0 ? "\(accuracy)%" : "\(records.count)"
    }

    private var summaryPrimaryLabel: String {
        scoredCount > 0 ? "accuracy" : "finished"
    }

    private var summaryMessage: String {
        guard scoredCount > 0 else {
            return "You completed the route and kept every question moving."
        }
        if accuracy >= 80 {
            return "Strong work. These phrases are ready for real conversations."
        }
        if accuracy >= 50 {
            return "Good progress. A quick review will make this route feel easier."
        }
        return "You finished the set. Review the tricky turns, then try the route again."
    }

    private func playSummaryCelebration() {
        guard !summaryCelebrated else { return }
        summaryCelebrated = true

        if reduceMotion {
            summaryRouteProgress = 1
            summaryReveal = true
            return
        }

        withAnimation(.smooth(duration: 0.85)) {
            summaryRouteProgress = 1
        }
        withAnimation(.bouncy(duration: 0.55).delay(0.28)) {
            summaryReveal = true
        }
    }

    private func submit() {
        guard result == nil, !primaryActionDisabled, index < records.count else { return }
        editingTranscript = false
        if question.kind == .spoken {
            let answer = speech.transcript
            let confidence = transcriptEdited ? nil : speech.confidence
            let activeQuestion = question
            let languageCode = current.languageCode
            let explanationLanguage = ExplanationLanguage(rawValue: current.explanationLanguageCode) ?? dependencies.settings.explanationLanguage
            let configuration = providerSnapshot ?? dependencies.settings.provider
            let operation = UUID()
            evaluationID = operation
            isEvaluating = true
            evaluationTask = Task {
                defer { if evaluationID == operation { isEvaluating = false; evaluationTask = nil } }
                do {
                    let evaluation = try await dependencies.generation.evaluateSpeech(activeQuestion,
                        transcript: answer, confidence: confidence, languageCode: languageCode,
                        explanationLanguage: explanationLanguage, configuration: configuration)
                    try Task.checkCancellation()
                    guard evaluationID == operation else { return }
                    speechEvaluation = evaluation
                    recordOutcome(evaluation.result, answer: answer)
                } catch { /* Cancellation never creates an attempt. */ }
            }
        } else if let cloze = question.cloze {
            let answer = String(decoding: (try? JSONEncoder().encode(blankSelections)) ?? Data(), as: UTF8.self)
            recordOutcome(cloze.isCorrect(blankSelections) ? .correct : .incorrect, answer: answer)
        } else {
            let answer = selectedAnswer ?? ""
            recordOutcome(answer == question.correctAnswer ? .correct : .incorrect, answer: answer)
        }
    }

    private func recordOutcome(_ outcome: AttemptResult, answer: String) {
        guard saveAttempt(outcome, answer: answer) else { return }
        counts.record(outcome)
        result = outcome
        if outcome == .correct { correctFeedback += 1 }
        else if outcome == .incorrect { incorrectFeedback += 1 }
    }

    private func cancelEvaluation() {
        evaluationID = UUID()
        evaluationTask?.cancel()
        evaluationTask = nil
        isEvaluating = false
    }

    private func skip() {
        guard result == nil, !isEvaluating, index < records.count else { return }
        guard saveAttempt(.skipped, answer: "") else { return }
        counts.record(.skipped)
        advance()
    }

    private func report(_ reason: ReportReason) {
        guard index < records.count, !isEvaluating else { return }
        current.isQuarantined = true
        guard saveAttempt(.reported, answer: "", reason: reason.rawValue) else {
            modelContext.rollback()
            return
        }
        if let result { counts.remove(result) }
        counts.record(.reported)
        advance()
    }

    private func saveAttempt(_ outcome: AttemptResult, answer: String, reason: String = "") -> Bool {
        let attempt = AttemptRecord(question: current, result: outcome, submittedAnswer: answer, reason: reason)
        attempt.sessionID = session.id
        attempt.speechConfidence = question.kind == .spoken && !transcriptEdited ? speech.confidence : nil
        attempt.feedback = speechEvaluation?.message ?? ""
        modelContext.insert(attempt)
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
            showPersistenceError = true
            return false
        }
    }

    private func advance() {
        speech.reset()
        cancelEvaluation()
        index += 1
        selectedAnswer = nil
        blankSelections = [:]
        transcriptEdited = false
        result = nil
        if index >= records.count && !session.hasRemaining { completed = true }
    }

    private func finishFlow() {
        speech.reset()
        cancelEvaluation()
        session.cancelFill()
        if let onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func feedbackTitle(_ result: AttemptResult) -> String {
        if let speechEvaluation {
            return speechEvaluation.title
        }
        return switch result {
        case .correct: String(localized: "Right on route")
        case .incorrect: String(localized: "Worth another look")
        case .undetermined: String(localized: "Compare your answer")
        case .skipped, .reported: String(localized: "Not counted")
        }
    }

    private func optionSymbol(_ option: String) -> String {
        guard let result else {
            return selectedAnswer == option ? "checkmark.circle.fill" : "circle"
        }
        if option == question.correctAnswer { return "checkmark.circle.fill" }
        if result == .incorrect && option == selectedAnswer { return "xmark.circle.fill" }
        return "circle"
    }

    private func optionAccessibilityValue(_ option: String) -> String {
        guard let result else { return selectedAnswer == option ? "Selected" : "Not selected" }
        if option == question.correctAnswer { return "Correct answer" }
        if result == .incorrect && option == selectedAnswer { return "Your answer, incorrect" }
        return "Not selected"
    }

    private func optionState(_ option: String) -> PromptiAnswerState {
        guard let result else { return selectedAnswer == option ? .selected : .idle }
        if option == question.correctAnswer { return .correct }
        if result == .incorrect && option == selectedAnswer { return .incorrect }
        return .idle
    }

    private func feedbackTone(_ result: AttemptResult) -> PromptiNoticeTone {
        switch result {
        case .correct: .success
        case .incorrect: .warning
        case .skipped, .reported, .undetermined: .neutral
        }
    }
}
