import Foundation
import AVFoundation
import Combine

/// Detects a stable musical pulse in audio extracted from video.
/// Processing stays entirely on device and does not require a backend.
@MainActor
class BeatDetector: ObservableObject {
    @Published var beats: [Double] = []  // Beat timestamps in seconds
    @Published var bpm: Double = 0
    @Published var isProcessing = false
    
    /// Detect beats from a video file
    func detectBeats(from videoURL: URL, completion: @escaping ([Double], Double) -> Void) {
        isProcessing = true
        beats = []
        bpm = 0
        
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try await Self.extractAndAnalyzeAudio(from: videoURL)
                }.value
                
                self.beats = result.beats
                self.bpm = result.bpm
                self.isProcessing = false
                print("🎵 Beat detection complete: \(result.beats.count) beats at \(Int(result.bpm)) BPM")
                completion(result.beats, result.bpm)
            } catch {
                print("❌ Beat detection error: \(error)")
                self.isProcessing = false
                completion([], 0)
            }
        }
    }
    
    nonisolated private static func extractAndAnalyzeAudio(from videoURL: URL) async throws -> (beats: [Double], bpm: Double) {
        let asset = AVURLAsset(url: videoURL)
        
        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            print("⚠️ No audio track found")
            return ([], 0)
        }
        
        // Setup reader
        let reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()
        
        // Collect all audio samples
        var allSamples: [Float] = []
        
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                
                if let data = dataPointer {
                    let floatCount = length / MemoryLayout<Float>.size
                    let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
                    let buffer = UnsafeBufferPointer(start: floatPointer, count: floatCount)
                    allSamples.append(contentsOf: buffer)
                }
            }
        }
        
        print("🎵 Extracted \(allSamples.count) audio samples")
        
        guard allSamples.count > 0 else {
            return ([], 0)
        }
        
        // Estimate the onset envelope, tempo, and a tempo-consistent beat sequence.
        let sampleRate: Double = 44100
        return trackBeats(samples: allSamples, sampleRate: sampleRate)
    }

    /// Lightweight beat tracking inspired by the Ellis dynamic-programming tracker.
    /// It separates onset detection from tempo estimation so a missing drum hit does
    /// not permanently shift the displayed dance count.
    nonisolated private static func trackBeats(
        samples: [Float],
        sampleRate: Double
    ) -> (beats: [Double], bpm: Double) {
        let hopSize = 512       // Samples between analysis frames
        let windowSize = 2048
        let frameDuration = Double(hopSize) / sampleRate

        guard samples.count > windowSize else { return ([], 0) }

        var logEnergy: [Double] = []
        var logPercussiveEnergy: [Double] = []
        var position = 0

        // RMS captures broad accents. The first-difference energy adds sensitivity
        // to sharp percussion without requiring an expensive spectral transform.
        while position + windowSize <= samples.count {
            var sumSquares = 0.0
            var differenceSquares = 0.0
            var previous = Double(samples[position])

            for index in position..<(position + windowSize) {
                let sample = Double(samples[index])
                sumSquares += sample * sample
                if index > position {
                    let difference = sample - previous
                    differenceSquares += difference * difference
                }
                previous = sample
            }

            let rms = sqrt(sumSquares / Double(windowSize))
            let differenceRMS = sqrt(differenceSquares / Double(windowSize - 1))
            logEnergy.append(log1p(rms * 1_000))
            logPercussiveEnergy.append(log1p(differenceRMS * 1_000))
            position += hopSize
        }

        guard logEnergy.count > 2 else { return ([], 0) }

        var rawOnsets = [Double](repeating: 0, count: logEnergy.count)
        for index in 1..<logEnergy.count {
            let energyChange = max(0, logEnergy[index] - logEnergy[index - 1])
            let percussiveChange = max(
                0,
                logPercussiveEnergy[index] - logPercussiveEnergy[index - 1]
            )
            rawOnsets[index] = (0.65 * energyChange) + (0.35 * percussiveChange)
        }

        let onsetEnvelope = locallyNormalize(
            rawOnsets,
            radius: max(1, Int(1.5 / frameDuration))
        )

        guard let tempo = estimateTempo(
            onsetEnvelope: onsetEnvelope,
            frameDuration: frameDuration
        ) else {
            return ([], 0)
        }

        let beatFrames = selectBeatSequence(
            onsetEnvelope: onsetEnvelope,
            period: tempo.period
        )
        let beats = beatFrames.map {
            (Double($0) * frameDuration) + (Double(windowSize) / (2 * sampleRate))
        }

        let formattedBPM = String(format: "%.1f", tempo.bpm)
        let formattedConfidence = String(format: "%.2f", tempo.confidence)
        print(
            "🎵 Tracked \(beats.count) beats at \(formattedBPM) BPM " +
            "(tempo confidence \(formattedConfidence))"
        )
        return (beats, tempo.bpm)
    }

    /// Removes the changing local noise floor and scales the useful onset range.
    nonisolated private static func locallyNormalize(
        _ signal: [Double],
        radius: Int
    ) -> [Double] {
        guard !signal.isEmpty else { return [] }

        var prefix = [Double](repeating: 0, count: signal.count + 1)
        for index in signal.indices {
            prefix[index + 1] = prefix[index] + signal[index]
        }

        var normalized = [Double](repeating: 0, count: signal.count)
        for index in signal.indices {
            let lower = max(0, index - radius)
            let upper = min(signal.count, index + radius + 1)
            let localMean = (prefix[upper] - prefix[lower]) / Double(upper - lower)
            normalized[index] = max(0, signal[index] - localMean)
        }

        let positiveValues = normalized.filter { $0 > 0 }.sorted()
        guard !positiveValues.isEmpty else { return normalized }

        // A percentile is more robust than the maximum when one transient is huge.
        let scaleIndex = min(
            positiveValues.count - 1,
            Int(Double(positiveValues.count - 1) * 0.9)
        )
        let scale = max(positiveValues[scaleIndex], 0.000_001)
        return normalized.map { min($0 / scale, 2) }
    }

    /// Estimates the dominant pulse from normalized onset autocorrelation.
    /// The broad range supports slower practice tracks as well as fast salsa music.
    nonisolated private static func estimateTempo(
        onsetEnvelope: [Double],
        frameDuration: Double
    ) -> (period: Double, bpm: Double, confidence: Double)? {
        let minimumBPM = 70.0
        let maximumBPM = 240.0
        let minimumLag = max(2, Int((60 / maximumBPM) / frameDuration))
        let maximumLag = min(
            onsetEnvelope.count / 2,
            Int((60 / minimumBPM) / frameDuration)
        )

        guard maximumLag > minimumLag else { return nil }

        var correlations = [Double](repeating: 0, count: maximumLag + 1)
        for lag in minimumLag...maximumLag {
            var product = 0.0
            var currentEnergy = 0.0
            var delayedEnergy = 0.0
            for index in lag..<onsetEnvelope.count {
                let current = onsetEnvelope[index]
                let delayed = onsetEnvelope[index - lag]
                product += current * delayed
                currentEnergy += current * current
                delayedEnergy += delayed * delayed
            }
            correlations[lag] = product / max(
                sqrt(currentEnergy * delayedEnergy),
                0.000_001
            )
        }

        // Reward a candidate whose multiples are also periodic. This reduces the
        // common half-tempo error when every second musical beat is accented most.
        func tempoScore(for lag: Int) -> Double {
            var score = correlations[lag]
            if (lag * 2) <= maximumLag {
                score += 0.5 * correlations[lag * 2]
            }
            if (lag * 3) <= maximumLag {
                score += 0.25 * correlations[lag * 3]
            }
            return score
        }

        guard let bestLag = (minimumLag...maximumLag).max(by: {
            tempoScore(for: $0) < tempoScore(for: $1)
        }) else { return nil }

        let confidence = correlations[bestLag]
        guard confidence >= 0.03 else { return nil }

        // Parabolic interpolation reduces BPM quantization caused by the hop size.
        var refinedLag = Double(bestLag)
        if bestLag > minimumLag, bestLag < maximumLag {
            let left = correlations[bestLag - 1]
            let center = correlations[bestLag]
            let right = correlations[bestLag + 1]
            let denominator = left - (2 * center) + right
            if abs(denominator) > 0.000_001 {
                refinedLag += 0.5 * (left - right) / denominator
            }
        }

        return (
            period: refinedLag,
            bpm: 60 / (refinedLag * frameDuration),
            confidence: confidence
        )
    }

    /// Finds the beat path that balances strong onsets with tempo consistency.
    nonisolated private static func selectBeatSequence(
        onsetEnvelope: [Double],
        period: Double
    ) -> [Int] {
        guard !onsetEnvelope.isEmpty else { return [] }

        let minimumStep = max(1, Int(period * 0.55))
        let maximumStep = max(minimumStep, Int(period * 1.8))
        var scores = onsetEnvelope
        var predecessors = [Int](repeating: -1, count: onsetEnvelope.count)

        for frame in onsetEnvelope.indices {
            let earliest = max(0, frame - maximumStep)
            let latest = frame - minimumStep
            guard latest >= earliest else { continue }

            for previous in earliest...latest {
                let ratio = Double(frame - previous) / period
                let timingPenalty = 2.0 * pow(log2(ratio), 2)
                let candidate = scores[previous] + onsetEnvelope[frame] - timingPenalty
                if candidate > scores[frame] {
                    scores[frame] = candidate
                    predecessors[frame] = previous
                }
            }
        }

        guard let endpoint = scores.indices.max(by: { scores[$0] < scores[$1] }) else {
            return []
        }

        var frames: [Int] = []
        var frame = endpoint
        while frame >= 0 {
            frames.append(frame)
            frame = predecessors[frame]
        }
        frames.reverse()

        // Continue the inferred pulse through quiet intros/outros. This also keeps
        // playback counting stable when percussion briefly drops out.
        if let first = frames.first {
            var earlier = first - Int(period.rounded())
            while earlier >= 0 {
                frames.insert(earlier, at: 0)
                earlier -= Int(period.rounded())
            }
        }
        if let last = frames.last {
            var later = last + Int(period.rounded())
            while later < onsetEnvelope.count {
                frames.append(later)
                later += Int(period.rounded())
            }
        }

        return frames
    }
}
