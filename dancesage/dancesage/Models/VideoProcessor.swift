import Foundation
import AVFoundation
import Vision
import UIKit
import Combine
import MediaPipeTasksVision

class VideoProcessor: ObservableObject {
    @Published var keypoints: [[[CGPoint]]] = []
    @Published var frameTimes: [Double] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    
    private var poseLandmarker: PoseLandmarker?  // MediaPipe — styling only
    private var isPartnerMode: Bool = false
    private let processingQueue = DispatchQueue(label: "com.dancesage.video-processing", qos: .utility)
    
    // Apple Vision joint order — 17 points — partner mode
    private let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]
    
    init() {
        setupMediaPipe()
    }
    
    func setPartnerMode(_ enabled: Bool) {
        isPartnerMode = enabled
    }
    
    private func setupMediaPipe() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task") else {
            print("❌ Model file not found")
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.numPoses = 1
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
        let mode = isPartnerMode ? "Apple Vision (Partner)" : "MediaPipe 33pt (Styling)"
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
                
                let poses: [[CGPoint]]?
                if partnerMode {
                    poses = detectPoseVision(in: cgImage)
                } else {
                    poses = detectPoseMediaPipe(in: cgImage)
                }

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
    
    // MARK: - MediaPipe — Styling (33 points, single person)
    private func detectPoseMediaPipe(in cgImage: CGImage) -> [[CGPoint]]? {
        guard let poseLandmarker = poseLandmarker else { return nil }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let mpImage = try? MPImage(uiImage: uiImage) else { return nil }
        
        do {
            let result = try poseLandmarker.detect(image: mpImage)
            guard !result.landmarks.isEmpty else { return nil }
            
            return result.landmarks.map { pose in
                pose.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            }
        } catch {
            print("❌ MediaPipe error: \(error)")
            return nil
        }
    }
    
    // MARK: - Apple Vision — Partner (17 points, multi-person)
    private func detectPoseVision(in cgImage: CGImage) -> [[CGPoint]]? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results, !observations.isEmpty else { return nil }
            
            var allPeople: [[CGPoint]] = observations.map { observation in
                jointOrder.map { joint in
                    if let point = try? observation.recognizedPoint(joint), point.confidence > 0.1 {
                        return CGPoint(x: point.location.x, y: 1.0 - point.location.y)
                    }
                    return CGPoint(x: -1, y: -1)
                }
            }
            
            // Sort by hip X — leftmost person first
            allPeople.sort { a, b in
                let hipA = a.count > 11 ? a[11].x : 0.5
                let hipB = b.count > 11 ? b[11].x : 0.5
                return hipA < hipB
            }
            
            return allPeople
            
        } catch {
            print("❌ Vision error: \(error)")
            return nil
        }
    }
}
