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
        
        Task {
            do {
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    print("❌ No video track found")
                    await MainActor.run { self.isProcessing = false }
                    return
                }
                
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                let duration = try await asset.load(.duration).seconds
                
                print("🎬 Duration: \(String(format: "%.1f", duration))s at \(String(format: "%.0f", frameRate))fps")
                
                await extractAndProcess(from: asset, frameRate: frameRate, duration: duration)
            } catch {
                print("❌ Error loading video: \(error)")
                await MainActor.run { self.isProcessing = false }
            }
        }
    }
    
    private func extractAndProcess(from asset: AVAsset, frameRate: Float, duration: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter  = CMTime(value: 1, timescale: 30)
        
        let targetFPS: Double = 15
        let frameInterval = 1.0 / targetFPS
        var currentTime = 0.0
        var allKeypoints: [[[CGPoint]]] = []
        var allFrameTimes: [Double] = []
        var frameCount = 0
        var detectedCount = 0
        
        while currentTime < duration {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let (cgImage, _) = try await generator.image(at: time)
                frameCount += 1
                
                let poses = isPartnerMode
                    ? detectPoseVision(in: cgImage)
                    : detectPoseMediaPipe(in: cgImage)
                
                allKeypoints.append(poses ?? [])
                allFrameTimes.append(currentTime)
                if poses != nil {
                    detectedCount += 1
                }
                
                if frameCount % 30 == 0 {
                    print("🎬 Frame \(frameCount): \(detectedCount) poses so far")
                }
                
            } catch {
                print("⚠️ Frame at \(String(format: "%.2f", currentTime))s skipped")
            }
            
            currentTime += frameInterval
            
            await MainActor.run {
                self.progress = min(currentTime / duration, 1.0)
            }
        }
        
        await MainActor.run {
            self.keypoints = allKeypoints
            self.frameTimes = allFrameTimes
            self.isProcessing = false
            print("✅ Done — \(frameCount) frames, \(detectedCount) with poses")
        }
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
