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
    /// Tracks cumulative keyword hits from the full transcript to handle revisions
    private var prevKeywordCounts: [String: Int] = [:]

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

                // Count all keyword occurrences in the full transcript,
                // then emit only the delta vs. previous counts.
                // This handles speech recognizer revisions correctly.
                for keyword in gratitudeKeywords {
                    let count = self.occurrences(of: keyword, in: transcript)
                    let prev = self.prevKeywordCounts[keyword] ?? 0
                    if count > prev {
                        let delta = count - prev
                        self.prevKeywordCounts[keyword] = count
                        DispatchQueue.main.async {
                            self.gratitudeCount += delta
                            self.lastHeardWord = keyword
                            if !self.gratitudeWords.contains(keyword) {
                                self.gratitudeWords.append(keyword)
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
        prevKeywordCounts = [:]
    }

    private func occurrences(of keyword: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: keyword, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }
}
