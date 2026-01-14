import Foundation
import AVFoundation
import Vision
import UIKit
import Combine

/// Video processor using Apple Vision for reliable pose detection
class VideoProcessor: ObservableObject {
    @Published var keypoints: [[[CGPoint]]] = []
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    
    // 17-point format matching VisionPoseDetector
    private let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]
    
    func processVideo(url: URL) {
        print("🎬 STARTING VIDEO PROCESSING (Apple Vision)")

        isProcessing = true
        keypoints = []
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
                
                print("🎬 Video duration: \(duration) seconds, frame rate: \(frameRate) fps")
                print("🎬 Expected frames: ~\(Int(duration * Double(frameRate)))")
                
                await extractFrames(from: asset, frameRate: frameRate, duration: duration)
            } catch {
                print("❌ Error loading video: \(error)")
                await MainActor.run { self.isProcessing = false }
            }
        }
    }
    
    private func extractFrames(from asset: AVAsset, frameRate: Float, duration: Double) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Process at ~15fps for speed (skip frames if video is higher fps)
        let targetFPS: Double = 15
        let frameInterval = max(1.0 / Double(frameRate), 1.0 / targetFPS)
        var currentTime = 0.0
        var allKeypoints: [[[CGPoint]]] = []
        var frameCount = 0
        var detectedCount = 0
        
        while currentTime < duration {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let (cgImage, _) = try await generator.image(at: time)
                frameCount += 1
                
                if let frameKeypoints = detectPose(in: cgImage) {
                    allKeypoints.append(frameKeypoints)
                    detectedCount += 1
                }
                
                if frameCount % 30 == 0 {
                    print("🍎 Frame \(frameCount): detected \(detectedCount) poses so far")
                }
                
            } catch {
                print("❌ Frame extraction error at \(currentTime)s: \(error)")
            }
            
            currentTime += frameInterval
            
            await MainActor.run {
                self.progress = min(currentTime / duration, 1.0)
            }
        }
        
        await MainActor.run {
            self.keypoints = allKeypoints
            self.isProcessing = false
            print("✅ Processed \(frameCount) frames, detected poses in \(allKeypoints.count) frames")
        }
    }
    
    private func detectPose(in cgImage: CGImage) -> [[CGPoint]]? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results, !observations.isEmpty else {
                return nil
            }
            
            // Detect ALL people - Vision can detect multiple people per frame
            var allPeople: [[CGPoint]] = []
            
            print("👥 Vision detected \(observations.count) person(s) in this frame")
            
            for (index, observation) in observations.enumerated() {
                var points: [CGPoint] = []
                
                for joint in jointOrder {
                    if let point = try? observation.recognizedPoint(joint), point.confidence > 0.1 {
                        // Flip Y for screen coordinates
                        let screenPoint = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
                        points.append(screenPoint)
                    } else {
                        points.append(CGPoint(x: -1, y: -1))
                    }
                }
                
                allPeople.append(points)
                let validPoints = points.filter { $0.x >= 0 && $0.y >= 0 }.count
                print("  Person \(index + 1): \(validPoints)/17 valid keypoints")
            }
            
            // Sort by X position (leftmost person first) for consistent coloring
            allPeople.sort { person1, person2 in
                let hip1 = person1.count > 11 ? person1[11] : CGPoint(x: 0.5, y: 0.5)
                let hip2 = person2.count > 11 ? person2[11] : CGPoint(x: 0.5, y: 0.5)
                return hip1.x < hip2.x
            }
            
            return allPeople
            
        } catch {
            print("❌ Vision detection error: \(error)")
            return nil
        }
    }
}
