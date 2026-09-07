@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

private actor SpeechAudioSession {
    static let shared = SpeechAudioSession()
    private var owner: UUID?

    func activate(for id: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
        owner = id
    }

    func deactivate(for id: UUID) {
        guard owner == id else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        owner = nil
    }
}

@MainActor
@Observable
final class SpeechPracticeModel {
    enum PermissionState {
        case unknown
        case requesting
        case authorized
        case denied
    }

    var transcript = ""
    private(set) var isRecording = false
    private(set) var isTranscribing = false
    var errorMessage: String?
    var confidence: Float?
    private(set) var permissionState = PermissionState.unknown

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false
    private var operationID = UUID()
    private var activeAudioSessionID: UUID?
    private var finalizationTask: Task<Void, Never>?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-ui-speech-denied") {
            permissionState = .denied
            errorMessage = String(localized: "Enable microphone and speech recognition in Settings to practice speaking.")
        }
        #endif
    }

    func speak(_ text: String, languageCode: String, rate: Float = 0.44) {
        guard !isRecording, !isTranscribing else { return }
        guard let voice = AVSpeechSynthesisVoice(language: languageCode) else {
            errorMessage = String(localized: "No system voice is available for this language.")
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(0.55, max(0.3, rate))
        synthesizer.speak(utterance)
    }

    func toggleRecording(languageCode: String) async {
        if isRecording { stopRecording(); return }
        guard permissionState != .requesting, !isTranscribing else { return }
        let id = UUID()
        operationID = id
        do {
            let allowed = await requestPermissions()
            guard operationID == id, !Task.isCancelled else { return }
            guard allowed else {
                errorMessage = String(localized: "Enable microphone and speech recognition in Settings to practice speaking.")
                return
            }
            try await startRecording(languageCode: languageCode, id: id)
        } catch {
            guard operationID == id else { return }
            cancelAudio()
            errorMessage = String(localized: "Recording could not start. You can still compare the sample answer.")
        }
    }

    /// Close the microphone now, but let Speech deliver its final transcript.
    func stopRecording() {
        guard isRecording else { return }
        releaseMicrophone()
        isTranscribing = true
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        let id = operationID
        finalizationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.operationID == id, self.isTranscribing else { return }
            self.confidence = 0
            self.cancelAudio()
            self.errorMessage = String(localized: "Transcription did not finish. Try again or compare the sample answer.")
        }
    }

    func reset() {
        cancelAudio()
        synthesizer.stopSpeaking(at: .immediate)
        transcript = ""
        errorMessage = nil
        confidence = nil
    }

    func clearTranscript() { reset() }

    private func releaseMicrophone() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        isRecording = false
        if let id = activeAudioSessionID {
            activeAudioSessionID = nil
            Task { await SpeechAudioSession.shared.deactivate(for: id) }
        }
    }

    private func cancelAudio() {
        operationID = UUID()
        finalizationTask?.cancel()
        finalizationTask = nil
        releaseMicrophone()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isTranscribing = false
    }

    private func requestPermissions() async -> Bool {
        permissionState = .requesting
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { permissionState = .denied; return false }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        permissionState = microphoneAllowed ? .authorized : .denied
        return microphoneAllowed
    }

    private func startRecording(languageCode: String, id: UUID) async throws {
        synthesizer.stopSpeaking(at: .immediate)
        transcript = ""
        errorMessage = nil
        confidence = nil
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode)), recognizer.isAvailable else {
            throw GenerationError.modelUnavailable
        }
        try await SpeechAudioSession.shared.activate(for: id)
        guard operationID == id, !Task.isCancelled else {
            await SpeechAudioSession.shared.deactivate(for: id)
            throw CancellationError()
        }
        activeAudioSessionID = id
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw GenerationError.modelUnavailable }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasInstalledTap = true
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.operationID == id else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        let values = result.bestTranscription.segments.map(\.confidence)
                        self.confidence = values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
                    }
                }
                if result?.isFinal == true { self.cancelAudio() }
                else if error != nil {
                    self.confidence = 0
                    self.cancelAudio()
                    self.errorMessage = String(localized: "Transcription did not finish. Try again or compare the sample answer.")
                }
            }
        }
    }
}
