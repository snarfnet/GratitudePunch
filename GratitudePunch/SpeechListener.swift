import Foundation
import Speech
import AVFoundation

@Observable
final class SpeechListener {
    var isListening = false
    var lastHeardWord = ""
    var gratitudeCount = 0
    var gratitudeWords: [String] = []

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastTranscript = ""

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start() {
        guard !isListening else { return }

        let isJa = Locale.preferredLanguages.first?.hasPrefix("ja") == true
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: isJa ? "ja-JP" : "en-US"))
        guard let recognizer = recognizer, recognizer.isAvailable else { return }

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }

        request.shouldReportPartialResults = true
        request.addsPunctuation = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()

                // Check for new gratitude words since last check
                let newPart = String(transcript.dropFirst(self.lastTranscript.count))
                if !newPart.isEmpty {
                    for keyword in gratitudeKeywords {
                        if newPart.contains(keyword) {
                            DispatchQueue.main.async {
                                self.gratitudeCount += 1
                                self.lastHeardWord = keyword
                                if !self.gratitudeWords.contains(keyword) {
                                    self.gratitudeWords.append(keyword)
                                }
                            }
                        }
                    }
                }
                self.lastTranscript = transcript
            }

            if error != nil {
                self.restartRecognition()
            }
        }

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Audio engine failed: \(error)")
        }
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        isListening = false
    }

    private func restartRecognition() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    func reset() {
        gratitudeCount = 0
        gratitudeWords = []
        lastHeardWord = ""
        lastTranscript = ""
    }
}
