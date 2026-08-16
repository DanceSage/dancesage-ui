import AVFoundation

/// Speaks coaching feedback out loud. Dancers listen; they rarely read mid-practice.
@MainActor
final class CoachVoice {
    static let shared = CoachVoice()

    private let synthesizer = AVSpeechSynthesizer()

    /// The most natural English voice installed on this device. The synthesizer's
    /// default is the compact robotic voice; premium and enhanced neural voices
    /// sound far closer to a person and cost nothing — they just have to be asked
    /// for. Users can install more under Settings > Accessibility > Spoken
    /// Content > Voices.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        func rank(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
            switch quality {
            case .premium: return 2
            case .enhanced: return 1
            default: return 0
            }
        }

        let best = englishVoices.max { rank($0.quality) < rank($1.quality) }
        return best ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

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
            utterance.voice = voice
            utterance.rate = 0.47
            utterance.pitchMultiplier = 1.03
            utterance.postUtteranceDelay = 0.3
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
