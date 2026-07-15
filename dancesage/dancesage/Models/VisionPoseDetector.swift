import Foundation
import Vision
import UIKit
import Combine
import CoreVideo

/// Apple Vision-based pose detector - much better for multi-person detection
class VisionPoseDetector: ObservableObject {
    @Published var keypoints: [[CGPoint]] = []
    @Published var recordedKeypoints: [[[CGPoint]]] = []
    @Published var isRecording = false
    
    private var sequenceHandler = VNSequenceRequestHandler()
    
    // Tracking: store previous frame's hip centers to match people across frames
    private var previousHipCenters: [CGPoint] = []
    
    // Store video dimensions for coordinate transformation
    private var videoWidth: CGFloat = 0
    private var videoHeight: CGFloat = 0
    
    // Map Vision body landmarks to indices similar to MediaPipe for compatibility
    // Vision has 19 body points (17 body + 2 for head)
    private let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose,              // 0
        .leftEye,           // 1
        .rightEye,          // 2
        .leftEar,           // 3
        .rightEar,          // 4
        .leftShoulder,      // 5 (MediaPipe: 11)
        .rightShoulder,     // 6 (MediaPipe: 12)
        .leftElbow,         // 7 (MediaPipe: 13)
        .rightElbow,        // 8 (MediaPipe: 14)
        .leftWrist,         // 9 (MediaPipe: 15)
        .rightWrist,        // 10 (MediaPipe: 16)
        .leftHip,           // 11 (MediaPipe: 23)
        .rightHip,          // 12 (MediaPipe: 24)
        .leftKnee,          // 13 (MediaPipe: 25)
        .rightKnee,         // 14 (MediaPipe: 26)
        .leftAnkle,         // 15 (MediaPipe: 27)
        .rightAnkle,        // 16 (MediaPipe: 28)
    ]
    
    /// Detect poses from pixel buffer (used by live camera for accurate coordinates)
    func detectPoses(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        // Store video dimensions (after rotation)
        // For .right orientation, width and height are swapped
        videoWidth = CGFloat(CVPixelBufferGetHeight(pixelBuffer))  // Swapped due to rotation
        videoHeight = CGFloat(CVPixelBufferGetWidth(pixelBuffer))  // Swapped due to rotation
        
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            self?.handlePoseDetection(request: request, error: error)
        }
        
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)
        } catch {
            print("❌ Vision detection error: \(error)")
        }
    }
    
    /// Detect poses from UIImage (used for video processing)
    func detectPoses(in image: UIImage) {
        guard let cgImage = image.cgImage else {
            print("❌ Failed to get CGImage")
            return
        }
        
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            self?.handlePoseDetection(request: request, error: error)
        }
        
        do {
            try sequenceHandler.perform([request], on: cgImage, orientation: .up)
        } catch {
            print("❌ Vision detection error: \(error)")
        }
    }
    
    private func handlePoseDetection(request: VNRequest, error: Error?) {
        if let error = error {
            print("❌ Pose detection error: \(error)")
            return
        }
        
        guard let observations = request.results as? [VNHumanBodyPoseObservation] else {
            DispatchQueue.main.async {
                self.keypoints = []
            }
            return
        }
        
        print("🍎 Vision detected \(observations.count) person(s)")
        
        // Extract all poses with their hip centers for tracking
        var posesWithCenters: [(points: [CGPoint], hipCenter: CGPoint)] = []
        
        for observation in observations {
            var points: [CGPoint] = []
            
            for joint in jointOrder {
                if let point = try? observation.recognizedPoint(joint), point.confidence > 0.1 {
                    // Vision coordinates are normalized (0-1) with origin at bottom-left
                    // Transform to match resizeAspectFill preview
                    let transformed = transformForAspectFill(point: point.location)
                    points.append(transformed)
                } else {
                    // Use invalid point for missing joints
                    points.append(CGPoint(x: -1, y: -1))
                }
            }
            
            // Calculate hip center for tracking (indices 11 and 12 are hips)
            let hipCenter = calculateHipCenter(points: points)
            posesWithCenters.append((points: points, hipCenter: hipCenter))
        }
        
        // Sort poses to maintain consistent ordering based on previous frame
        let sortedPoses = sortPosesForConsistency(posesWithCenters)
        
        // Update previous hip centers for next frame
        previousHipCenters = sortedPoses.map { $0.hipCenter }
        
        let allPoses = sortedPoses.map { $0.points }
        
        for (personIndex, pose) in allPoses.enumerated() {
            print("  Person \(personIndex + 1): \(pose.filter { $0.x >= 0 }.count) valid landmarks")
        }
        
        DispatchQueue.main.async {
            self.keypoints = allPoses
            
            if self.isRecording {
                self.recordedKeypoints.append(allPoses)
                // Send frame to backend immediately
                let frameIndex = self.recordedKeypoints.count - 1
            }
        }
        
        print("👥 Total detected: \(allPoses.count) person(s)")
    }
    
    /// Transform Vision coordinates to match resizeAspectFill preview
    private func transformForAspectFill(point: CGPoint) -> CGPoint {
        // Vision returns normalized coordinates (0-1) in video frame space
        // The preview uses resizeAspectFill which crops to fill the screen
        
        // Get screen aspect ratio (portrait phone ~9:19.5 or ~0.46)
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let screenAspect = screenWidth / screenHeight
        
        // Video aspect ratio (after rotation to portrait)
        let videoAspect = videoWidth / videoHeight
        
        var x = point.x
        var y = 1.0 - point.y  // Flip Y for screen coordinates
        
        if videoAspect > screenAspect {
            // Video is wider - sides are cropped
            let visibleWidth = screenAspect / videoAspect
            let cropAmount = (1.0 - visibleWidth) / 2.0
            x = (point.x - cropAmount) / visibleWidth
        } else {
            // Video is taller - top/bottom are cropped
            let visibleHeight = videoAspect / screenAspect
            let cropAmount = (1.0 - visibleHeight) / 2.0
            y = ((1.0 - point.y) - cropAmount) / visibleHeight
        }
        
        return CGPoint(x: x, y: y)
    }
    
    /// Calculate the center point between hips for tracking
    private func calculateHipCenter(points: [CGPoint]) -> CGPoint {
        // Hip indices are 11 (left) and 12 (right)
        let leftHip = points.count > 11 ? points[11] : CGPoint(x: -1, y: -1)
        let rightHip = points.count > 12 ? points[12] : CGPoint(x: -1, y: -1)
        
        // If both hips valid, use center
        if leftHip.x >= 0 && rightHip.x >= 0 {
            return CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        }
        // If only one hip valid, use it
        if leftHip.x >= 0 { return leftHip }
        if rightHip.x >= 0 { return rightHip }
        
        // Fallback to nose (index 0) or shoulder center
        let nose = points.count > 0 ? points[0] : CGPoint(x: -1, y: -1)
        if nose.x >= 0 { return nose }
        
        // Last resort: use first valid point
        return points.first { $0.x >= 0 } ?? CGPoint(x: 0.5, y: 0.5)
    }
    
    /// Sort poses to match previous frame's ordering (keeps colors consistent)
    private func sortPosesForConsistency(_ poses: [(points: [CGPoint], hipCenter: CGPoint)]) -> [(points: [CGPoint], hipCenter: CGPoint)] {
        guard !previousHipCenters.isEmpty && poses.count > 1 else {
            // First frame or single person: sort by X position (left person = green, right = red)
            return poses.sorted { $0.hipCenter.x < $1.hipCenter.x }
        }
        
        var remainingPoses = poses
        var sortedPoses: [(points: [CGPoint], hipCenter: CGPoint)] = []
        
        // Match each previous position to closest current pose
        for prevCenter in previousHipCenters {
            if remainingPoses.isEmpty { break }
            
            // Find closest pose to this previous position
            var closestIndex = 0
            var closestDistance = CGFloat.infinity
            
            for (index, pose) in remainingPoses.enumerated() {
                let distance = hypot(pose.hipCenter.x - prevCenter.x, pose.hipCenter.y - prevCenter.y)
                if distance < closestDistance {
                    closestDistance = distance
                    closestIndex = index
                }
            }
            
            // Only match if reasonably close (within 30% of screen)
            if closestDistance < 0.3 {
                sortedPoses.append(remainingPoses.remove(at: closestIndex))
            }
        }
        
        // Add any unmatched poses (new people entering frame)
        sortedPoses.append(contentsOf: remainingPoses.sorted { $0.hipCenter.x < $1.hipCenter.x })
        
        return sortedPoses
    }
    
    // Recording controls
    func startRecording() {
        recordedKeypoints = []
        isRecording = true
        print("🔴 Recording started (Vision)")
    }
    
    func stopRecording() {
        isRecording = false
        print("⏹️ Recording stopped - captured \(recordedKeypoints.count) frames")
    }
    
    func clearRecording() {
        recordedKeypoints = []
        print("🗑️ Recording cleared")
    }
}

