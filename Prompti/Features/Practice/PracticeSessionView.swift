import SwiftData
import SwiftUI

struct PracticeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let records: [QuestionRecord]
    let onFinish: (() -> Void)?

    @State private var index = 0
    @State private var selectedAnswer: String?
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
        self.records = records
        self.onFinish = onFinish
    }

    private var current: QuestionRecord { records[index] }
    private var question: GeneratedQuestion { current.question }

    var body: some View {
        ZStack {
            PromptiBackground()
            if records.isEmpty {
                ContentUnavailableView(
                    "No questions available",
                    systemImage: "tray",
                    description: Text("Return to practice and prepare another set.")
                )
            } else if completed {
                summary
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
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(PromptiActionScrim())

            } else if !records.isEmpty {
                primaryQuestionAction
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .padding(.horizontal, 16).padding(.vertical, 10)
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
        .onDisappear { speech.stopRecording() }
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
                        .accessibilityIdentifier("session.skip")
                    Button("Question may be wrong", systemImage: "exclamationmark.bubble", role: .destructive) {
                        showReport = true
                    }
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
                    Text("\(index + 1) / \(records.count)")
                        .font(.subheadline.bold())
                    Spacer()
                    Label(LocalizedStringKey(current.sceneTitle), systemImage: question.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question \(index + 1) of \(records.count)")
                        .font(.headline)
                    Label(LocalizedStringKey(current.sceneTitle), systemImage: question.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProgressView(value: Double(index + 1), total: Double(records.count))
                .tint(Color.promptMintDeep)
        }
        .accessibilityElement(children: .combine)
    }

    private var questionPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(question.kind.title))
                .textCase(.uppercase)
                .font(.caption.bold())
                .foregroundStyle(Color.promptMintDeep)
            Text(question.prompt)
                .font(.title2.bold())
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(question.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .promptiSurface()
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
                    .foregroundStyle(optionColor(option.text))
                    .padding(15)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(optionBackground(option.text), in: .rect(cornerRadius: PromptiRadius.control))
                }
                .buttonStyle(.plain)
                .accessibilityValue(optionAccessibilityValue(option.text))
                .accessibilityIdentifier("session.option.\(option.id.uuidString)")
            }
        }
    }

    private var spokenPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            InlineNotice(
                symbol: "lock.shield.fill",
                text: "Speech is transcribed for this attempt. Raw audio is not saved or synced."
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

            Text(
                speech.transcript.isEmpty
                    ? String(localized: "Your transcript will appear here.")
                    : speech.transcript
            )
                .font(.body)
                .foregroundStyle(speech.transcript.isEmpty ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .padding(12)
                .background(.secondary.opacity(0.08), in: .rect(cornerRadius: PromptiRadius.control))

            if !speech.transcript.isEmpty, result == nil {
                Button("Record again", systemImage: "arrow.clockwise") {
                    speech.clearTranscript()
                }
                .buttonStyle(.bordered)
            }

            if speech.permissionState == .denied {
                Button("Open Settings", systemImage: "gearshape", action: openSystemSettings)
                    .buttonStyle(.bordered)
            }

            if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hearPromptButton: some View {
        Button("Hear prompt", systemImage: "speaker.wave.2.fill") {
            speech.speak(question.prompt, languageCode: current.languageCode)
        }
        .buttonStyle(.bordered)
        .disabled(speech.isRecording)
        .frame(minHeight: 44)
    }

    private var recordButton: some View {
        Button {
            Task { await speech.toggleRecording(languageCode: current.languageCode) }
        } label: {
            if speech.permissionState == .requesting {
                Label("Requesting access", systemImage: "mic.badge.plus")
            } else {
                Label(
                    speech.isRecording ? "Stop recording" : "Record answer",
                    systemImage: speech.isRecording ? "stop.fill" : "mic.fill"
                )
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(speech.isRecording ? .promptCoral : .promptMintDeep)
        .disabled(speech.permissionState == .requesting)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var primaryQuestionAction: some View {
        if result == nil {
            Button(primaryActionTitle, action: submit)
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(primaryActionDisabled)
                .accessibilityIdentifier("session.submit")
        } else {
            Button(index == records.count - 1 ? "See trip summary" : "Next question", action: advance)
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
        if speechFallbackAvailable { return "View sample answer" }
        return question.kind == .spoken ? "Compare answer" : "Check answer"
    }

    private var primaryActionDisabled: Bool {
        if question.kind != .spoken { return selectedAnswer == nil }
        return (!speechFallbackAvailable && speech.transcript.isEmpty) || speech.isRecording
    }

    private func feedback(_ result: AttemptResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(feedbackTitle(result), systemImage: result == .correct ? "checkmark.seal.fill" : "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(result == .correct ? Color.promptMintDeep : Color.promptCoral)

            if let speechEvaluation {
                Text(speechEvaluation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Sample: \(question.sampleAnswer ?? question.correctAnswer)")
                    .font(.body.bold())
            } else {
                if result != .correct {
                    Text("Answer: \(question.sampleAnswer ?? question.correctAnswer)")
                        .font(.body.bold())
                }
                Text(question.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Color.promptSun.opacity(0.18), in: .rect(cornerRadius: PromptiRadius.surface))
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    summaryHero

                    LazyVGrid(columns: summaryMetricColumns, spacing: 10) {
                        SummaryMetricCell(value: "\(counts.correct)", label: "correct", symbol: "checkmark", tint: .promptMintDeep)
                        SummaryMetricCell(value: "\(counts.incorrect)", label: "review", symbol: "arrow.counterclockwise", tint: .promptCoral)
                        SummaryMetricCell(value: "\(counts.skipped)", label: "skipped", symbol: "forward.fill", tint: .promptSky)
                        SummaryMetricCell(value: "\(counts.undetermined)", label: "not scored", symbol: "waveform", tint: .promptSun)
                    }
                    .opacity(summaryReveal ? 1 : 0)
                    .offset(y: summaryReveal ? 0 : 10)

                    if counts.reported > 0 {
                        InlineNotice(
                            symbol: "exclamationmark.bubble.fill",
                            text: "\(counts.reported) reported question was removed from future practice.",
                            tint: .promptCoral
                        )
                    }

                    summaryReward
                        .opacity(summaryReveal ? 1 : 0)
                        .scaleEffect(summaryReveal ? 1 : 0.94)
                }
                .padding(.horizontal, 16)
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

            FlightRouteVisual(
                progress: summaryRouteProgress,
                destinationSymbol: "flag.checkered",
                isComplete: summaryReveal
            )
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 126 : 112)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.promptMint.opacity(0.38), Color.promptSky.opacity(0.18), Color.promptSun.opacity(0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: PromptiRadius.hero, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PromptiRadius.hero, style: .continuous)
                .strokeBorder(Color.promptMintDeep.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryHeaderCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Route complete", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.promptMintDeep)
            Text("Practice landed")
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .accessibilityIdentifier("session.summary")
            Text(LocalizedStringKey(summaryMessage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.58), in: RoundedRectangle(cornerRadius: PromptiRadius.control, style: .continuous))
        .scaleEffect(summaryReveal ? 1 : 0.94)
        .opacity(summaryReveal ? 1 : 0)
    }

    private var summaryReward: some View {
        VStack(spacing: 9) {
            Image(systemName: "medal.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.promptInk)
                .frame(width: 56, height: 56)
                .background(Color.promptSun, in: Circle())
                .symbolEffect(.bounce, value: reduceMotion ? false : summaryReveal)
                .accessibilityHidden(true)
            Text("Progress saved")
                .font(.headline)
            Text("Your next conversation just got easier.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        speech.stopRecording()
        let outcome: AttemptResult
        let answer: String

        if question.kind == .spoken {
            answer = speech.transcript
            let evaluation = SpeechAnswerEvaluator.evaluate(
                transcript: answer,
                reference: question.sampleAnswer ?? question.correctAnswer,
                confidence: speech.confidence
            )
            speechEvaluation = evaluation
            outcome = evaluation.result
        } else {
            answer = selectedAnswer ?? ""
            outcome = answer == question.correctAnswer ? .correct : .incorrect
        }

        guard saveAttempt(outcome, answer: answer) else { return }
        counts.record(outcome)
        result = outcome
        if outcome == .correct {
            correctFeedback += 1
        } else if outcome == .incorrect {
            incorrectFeedback += 1
        }
    }

    private func skip() {
        guard saveAttempt(.skipped, answer: "") else { return }
        counts.record(.skipped)
        advance()
    }

    private func report(_ reason: ReportReason) {
        current.isQuarantined = true
        guard saveAttempt(.reported, answer: "", reason: reason.rawValue) else {
            modelContext.rollback()
            return
        }
        counts.record(.reported)
        advance()
    }

    private func saveAttempt(_ outcome: AttemptResult, answer: String, reason: String = "") -> Bool {
        modelContext.insert(AttemptRecord(question: current, result: outcome, submittedAnswer: answer, reason: reason))
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
        if index == records.count - 1 {
            completed = true
        } else {
            index += 1
            selectedAnswer = nil
            result = nil
        }
    }

    private func finishFlow() {
        speech.stopRecording()
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

    private func optionColor(_ option: String) -> Color {
        guard let result else { return selectedAnswer == option ? .white : .primary }
        if option == question.correctAnswer { return .white }
        if result == .incorrect && option == selectedAnswer { return .white }
        return .primary
    }

    private func optionBackground(_ option: String) -> Color {
        guard let result else { return selectedAnswer == option ? .promptMintDeep : Color(.secondarySystemBackground) }
        if option == question.correctAnswer { return .promptMintDeep }
        if result == .incorrect && option == selectedAnswer {
            return differentiateWithoutColor ? Color.secondary : .promptCoral
        }
        return Color(.secondarySystemBackground)
    }
}
