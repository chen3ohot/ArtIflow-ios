import Foundation
import Speech
import AVFoundation

/// On-device / cloud speech recognizer used for voice follow-up. Replaces the Android
/// OpenSpeech ASR backend with the native iOS Speech framework.
final class SpeechRecognizer: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    // 录音启动失败时写入提示文案，供上层 toast 显示
    @Published var failureMessage: String? = nil

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 同时申请语音识别与麦克风权限，二者都授权才回 true
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    func startTranscription() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            failureMessage = "语音识别不可用"; return
        }
        transcript = ""
        failureMessage = nil
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            task = recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stopTranscription()
                    }
                }
            }
            isRecording = true
        } catch {
            stopTranscription()
            failureMessage = "录音启动失败，请检查麦克风权限"
        }
    }

    func stopTranscription() {
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    func reset() {
        transcript = ""
    }
}
