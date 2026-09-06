@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

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
    var isRecording = false
    var errorMessage: String?
    var confidence: Float?
    private(set) var permissionState = PermissionState.unknown

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-ui-speech-denied") {
            permissionState = .denied
            errorMessage = String(localized: "Enable microphone and speech recognition in Settings to practice speaking.")
        }
        #endif
    }

    func speak(_ text: String, languageCode: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = 0.44
        synthesizer.speak(utterance)
    }

    func toggleRecording(languageCode: String) async {
        if isRecording {
            stopRecording()
            return
        }
        do {
            guard await requestPermissions() else {
                errorMessage = String(localized: "Enable microphone and speech recognition in Settings to practice speaking.")
                return
            }
            try startRecording(languageCode: languageCode)
        } catch {
            stopRecording()
            errorMessage = String(localized: "Recording could not start. You can still compare the sample answer.")
        }
    }

    func stopRecording() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }

    func reset() {
        stopRecording()
        transcript = ""
        errorMessage = nil
        confidence = nil
    }

    func clearTranscript() {
        stopRecording()
        transcript = ""
        confidence = nil
        errorMessage = nil
    }

    private func requestPermissions() async -> Bool {
        permissionState = .requesting
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            permissionState = .denied
            return false
        }
        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        permissionState = microphoneAllowed ? .authorized : .denied
        return microphoneAllowed
    }

    private func startRecording(languageCode: String) throws {
        stopRecording()
        transcript = ""
        errorMessage = nil

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageCode))
        guard let recognizer, recognizer.isAvailable else {
            throw GenerationError.modelUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasInstalledTap = true
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    let confidences = result.bestTranscription.segments.map(\.confidence)
                    if !confidences.isEmpty {
                        self.confidence = confidences.reduce(0, +) / Float(confidences.count)
                    }
                }
                if error != nil || result?.isFinal == true { self.stopRecording() }
            }
        }
    }
}
