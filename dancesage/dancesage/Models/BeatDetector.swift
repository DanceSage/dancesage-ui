import Foundation
import AVFoundation
import Accelerate
import Combine

/// Detects beats in audio extracted from video
/// Target: Salsa music at 180-220 BPM
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
        
        // Detect beats using onset detection
        let sampleRate: Double = 44100
        let beats = detectOnsets(samples: allSamples, sampleRate: sampleRate)
        let bpm = calculateBPM(beats: beats)
        
        return (beats, bpm)
    }
    
    /// Simple onset detection using energy difference
    nonisolated private static func detectOnsets(samples: [Float], sampleRate: Double) -> [Double] {
        let hopSize = 512       // Samples between analysis frames
        let windowSize = 2048   // FFT window size
        
        guard samples.count > windowSize else { return [] }
        
        var energies: [Float] = []
        var position = 0
        
        // Calculate energy for each window
        while position + windowSize <= samples.count {
            let window = Array(samples[position..<(position + windowSize)])
            
            // Compute RMS energy
            var sumSquares: Float = 0
            vDSP_svesq(window, 1, &sumSquares, vDSP_Length(windowSize))
            let rms = sqrt(sumSquares / Float(windowSize))
            energies.append(rms)
            
            position += hopSize
        }
        
        guard energies.count > 1 else { return [] }
        
        // Calculate energy difference (onset strength)
        var onsetStrength: [Float] = [0]
        for i in 1..<energies.count {
            let diff = max(0, energies[i] - energies[i-1])
            onsetStrength.append(diff)
        }
        
        // Find peaks in onset strength
        let threshold = calculateAdaptiveThreshold(onsetStrength)
        var beats: [Double] = []
        
        // Minimum time between beats (assumes max 220 BPM = 0.27s)
        let minBeatInterval = 0.27
        let minSamplesBetweenBeats = Int(minBeatInterval * sampleRate / Double(hopSize))
        
        var lastBeatIndex = -minSamplesBetweenBeats
        
        for i in 1..<(onsetStrength.count - 1) {
            // Is this a local peak above threshold?
            if onsetStrength[i] > threshold &&
               onsetStrength[i] > onsetStrength[i-1] &&
               onsetStrength[i] > onsetStrength[i+1] &&
               (i - lastBeatIndex) >= minSamplesBetweenBeats {
                
                let timeInSeconds = Double(i * hopSize) / sampleRate
                beats.append(timeInSeconds)
                lastBeatIndex = i
            }
        }
        
        print("🎵 Detected \(beats.count) raw beats")
        return beats
    }
    
    /// Calculate adaptive threshold based on signal statistics
    nonisolated private static func calculateAdaptiveThreshold(_ signal: [Float]) -> Float {
        var mean: Float = 0
        var stdDev: Float = 0
        var length = vDSP_Length(signal.count)
        
        vDSP_meanv(signal, 1, &mean, length)
        
        // Calculate standard deviation
        var squaredDiffs = [Float](repeating: 0, count: signal.count)
        var negMean = -mean
        vDSP_vsadd(signal, 1, &negMean, &squaredDiffs, 1, length)
        vDSP_vsq(squaredDiffs, 1, &squaredDiffs, 1, length)
        
        var variance: Float = 0
        vDSP_meanv(squaredDiffs, 1, &variance, length)
        stdDev = sqrt(variance)
        
        // Threshold = mean + 1.5 * stdDev
        return mean + 1.5 * stdDev
    }
    
    /// Calculate BPM from beat timestamps
    nonisolated private static func calculateBPM(beats: [Double]) -> Double {
        guard beats.count >= 2 else { return 0 }
        
        // Calculate intervals between consecutive beats
        var intervals: [Double] = []
        for i in 1..<beats.count {
            intervals.append(beats[i] - beats[i-1])
        }
        
        // Filter intervals to salsa range (180-220 BPM = 0.27-0.33s per beat)
        let salsaIntervals = intervals.filter { $0 >= 0.27 && $0 <= 0.35 }
        
        guard !salsaIntervals.isEmpty else {
            // Fallback: use median of all intervals
            let sorted = intervals.sorted()
            let median = sorted[sorted.count / 2]
            return 60.0 / median
        }
        
        // Average the salsa-range intervals
        let avgInterval = salsaIntervals.reduce(0, +) / Double(salsaIntervals.count)
        return 60.0 / avgInterval
    }
}
