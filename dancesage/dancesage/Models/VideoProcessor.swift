import Foundation
import AVFoundation
import UIKit
import Combine
import MediaPipeTasksVision

class VideoProcessor: ObservableObject {
    @Published var keypoints: [[[CGPoint]]] = []
    @Published var frameTimes: [Double] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    
    /// MediaPipe for both modes: one pose for styling, two for partner work.
    private var poseLandmarker: PoseLandmarker?
    private var isPartnerMode: Bool = false
    private let processingQueue = DispatchQueue(label: "com.dancesage.video-processing", qos: .utility)
    
    init() {
        setupMediaPipe(numPoses: 1)
    }
    
    func setPartnerMode(_ enabled: Bool) {
        guard enabled != isPartnerMode else { return }
        isPartnerMode = enabled
        setupMediaPipe(numPoses: enabled ? 2 : 1)
    }
    
    private func setupMediaPipe(numPoses: Int) {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task") else {
            print("❌ Model file not found")
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.numPoses = numPoses
        options.minPoseDetectionConfidence = 0.3
        options.minPosePresenceConfidence = 0.3
        options.minTrackingConfidence = 0.3
        
        do {
            poseLandmarker = try PoseLandmarker(options: options)
            print("✅ VideoProcessor MediaPipe initialized")
        } catch {
            print("❌ Error creating PoseLandmarker: \(error)")
        }
    }
    
    func processVideo(url: URL) {
        let mode = isPartnerMode ? "MediaPipe 33pt x2 (Partner)" : "MediaPipe 33pt (Styling)"
        print("🎬 STARTING VIDEO PROCESSING — \(mode)")
        
        isProcessing = true
        keypoints = []
        frameTimes = []
        progress = 0.0
        
        let asset = AVURLAsset(url: url)
        let partnerMode = isPartnerMode

        processingQueue.async { [weak self] in
            guard let self else { return }
            let duration = asset.duration.seconds
            guard duration.isFinite, duration > 0,
                  let videoTrack = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async { self.isProcessing = false }
                return
            }

            let frameRate = videoTrack.nominalFrameRate
            print("🎬 Duration: \(String(format: "%.1f", duration))s at \(String(format: "%.0f", frameRate))fps")
            self.extractAndProcess(from: asset, duration: duration, partnerMode: partnerMode)
        }
    }
    
    private func extractAndProcess(from asset: AVAsset, duration: Double, partnerMode: Bool) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter  = CMTime(value: 1, timescale: 30)
        
        let targetFPS: Double = 15
        let frameInterval = 1.0 / targetFPS
        var currentTime = 0.0
        var frameCount = 0
        var detectedCount = 0
        var pendingKeypoints: [[[CGPoint]]] = []
        var pendingFrameTimes: [Double] = []
        var lastPublishTime = 0.0
        let partnerTracker = PartnerPoseTracker()

        func publishPending(progress frameTime: Double, finished: Bool = false) {
            guard !pendingFrameTimes.isEmpty || finished else { return }

            let keypointBatch = pendingKeypoints
            let timeBatch = pendingFrameTimes
            pendingKeypoints.removeAll(keepingCapacity: true)
            pendingFrameTimes.removeAll(keepingCapacity: true)

            DispatchQueue.main.async {
                self.keypoints.append(contentsOf: keypointBatch)
                self.frameTimes.append(contentsOf: timeBatch)
                self.progress = finished ? 1 : min(frameTime / duration, 1)
                if finished {
                    self.isProcessing = false
                    print("✅ Done — \(frameCount) frames, \(detectedCount) with poses")
                }
            }
        }
        
        while currentTime < duration {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                frameCount += 1
                
                let poses = detectPoseMediaPipe(in: cgImage,
                                                tracker: partnerMode ? partnerTracker : nil)

                if poses != nil {
                    detectedCount += 1
                }

                pendingKeypoints.append(poses ?? [])
                pendingFrameTimes.append(currentTime)

                // Publish at most twice per second so SwiftUI and AVPlayer stay responsive.
                if currentTime - lastPublishTime >= 0.5 {
                    publishPending(progress: currentTime)
                    lastPublishTime = currentTime
                }
                
                if frameCount % 30 == 0 {
                    print("🎬 Frame \(frameCount): \(detectedCount) poses so far")
                }
                
            } catch {
                print("⚠️ Frame at \(String(format: "%.2f", currentTime))s skipped")
            }
            
            currentTime += frameInterval
        }

        publishPending(progress: duration, finished: true)
    }
    
    // MARK: - MediaPipe (33 points; two people in partner mode)
    private func detectPoseMediaPipe(in cgImage: CGImage,
                                     tracker: PartnerPoseTracker?) -> [[CGPoint]]? {
        guard let poseLandmarker = poseLandmarker else { return nil }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let mpImage = try? MPImage(uiImage: uiImage) else { return nil }
        
        do {
            let result = try poseLandmarker.detect(image: mpImage)
            let poses = result.landmarks.map { pose in
                pose.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            }
            guard let tracker else { return poses.isEmpty ? nil : poses }
            // Partner clips keep each dancer in their own slot, frame to frame.
            let visibility = result.landmarks.map { pose -> Float in
                let seen = pose.compactMap { $0.visibility?.floatValue }
                return seen.isEmpty ? 1 : seen.reduce(0, +) / Float(seen.count)
            }
            let tracked = tracker.update(poses: poses, visibility: visibility)
            return tracked.isEmpty ? nil : tracked
        } catch {
            print("❌ MediaPipe error: \(error)")
            return nil
        }
    }
}
