import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioSessionQueue = DispatchQueue(label: "com.marine.MeetingImporter.audio-session")
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false
    private var isStarting = false
    private var recordingAttemptID: UUID?

    func startRecording() async {
        guard !isRecording, !isStarting else { return }
        let attemptID = UUID()
        recordingAttemptID = attemptID
        isStarting = true
        defer {
            if recordingAttemptID == attemptID || recordingAttemptID == nil {
                isStarting = false
            }
        }
        errorMessage = nil

        if let simulatorMessage = simulatorUnsupportedMessage() {
            recordingAttemptID = nil
            errorMessage = simulatorMessage
            return
        }

        guard await requestSpeechPermission() else {
            guard isCurrentAttempt(attemptID) else { return }
            recordingAttemptID = nil
            errorMessage = "请在系统设置中允许“会议通知”使用语音识别。"
            return
        }
        guard isCurrentAttempt(attemptID) else { return }

        guard await requestMicrophonePermission() else {
            guard isCurrentAttempt(attemptID) else { return }
            recordingAttemptID = nil
            errorMessage = "请在系统设置中允许“会议通知”使用麦克风。"
            return
        }
        guard isCurrentAttempt(attemptID) else { return }

        guard recognizer?.isAvailable == true else {
            recordingAttemptID = nil
            errorMessage = "系统语音识别当前不可用，请稍后重试。"
            return
        }

        resetRecordingState()
        transcript = ""

        do {
            try await activateAudioSession()
            guard isCurrentAttempt(attemptID) else {
                deactivateAudioSession()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.addsPunctuation = true
            request.contextualStrings = ["会议名称", "起始日期", "结束日期", "日期", "起始时间", "时间", "地点", "参会人员", "主要内容"]
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                throw SpeechInputError.audioUnavailable
            }

            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledTap = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentAttempt(attemptID) else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || result?.isFinal == true {
                        self.finishRecognition(for: attemptID)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            guard isCurrentAttempt(attemptID) else {
                deactivateAudioSession()
                return
            }
            let message = error.localizedDescription
            cancelRecording()
            errorMessage = message
        }
    }

    func stopRecording() {
        guard isRecording else {
            recordingAttemptID = nil
            isStarting = false
            return
        }
        stopAudioCapture()
        recognitionRequest?.endAudio()
        isRecording = false
        deactivateAudioSession()
    }

    func cancelRecording() {
        recordingAttemptID = nil
        isStarting = false
        resetRecordingState()
        deactivateAudioSession()
    }

    private func finishRecognition(for attemptID: UUID) {
        guard isCurrentAttempt(attemptID) else { return }
        recordingAttemptID = nil
        stopAudioCapture()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        deactivateAudioSession()
    }

    private func isCurrentAttempt(_ attemptID: UUID) -> Bool {
        recordingAttemptID == attemptID
    }

    private func simulatorUnsupportedMessage() -> String? {
#if targetEnvironment(simulator)
        "模拟器暂不支持语音输入，请在真机上使用。"
#else
        nil
#endif
    }

    private func resetRecordingState() {
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
    }

    private func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deactivateAudioSession() {
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
    }

    private func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

private enum SpeechInputError: LocalizedError {
    case audioUnavailable

    var errorDescription: String? {
        "无法读取麦克风音频，请检查设备麦克风后重试。"
    }
}
