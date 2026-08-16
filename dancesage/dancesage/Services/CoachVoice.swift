import AVFoundation

/// Speaks coaching feedback out loud. Dancers listen; they rarely read mid-practice.
@MainActor
final class CoachVoice {
    static let shared = CoachVoice()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(score: Int, cues: [String]) {
        stop()
        // Playback category so feedback is audible even alongside music apps.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        var lines = ["You scored \(score) out of one hundred."]
        lines.append(contentsOf: cues)
        for line in lines {
            let utterance = AVSpeechUtterance(string: line)
            utterance.rate = 0.48
            utterance.postUtteranceDelay = 0.25
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
