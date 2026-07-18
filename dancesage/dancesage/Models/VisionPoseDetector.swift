import Foundation
import Vision
import UIKit
import Combine
import CoreVideo

/// Apple Vision-based pose detector - much better for multi-person detection
class VisionPoseDetector: ObservableObject {
    @Published var keypoints: [[CGPoint]] = []
    @Published var recordedKeypoints: [[[CGPoint]]] = []
    @Published var recordedFrameTimes: [Double] = []
    @Published var isRecording = false
    
    private var sequenceHandler = VNSequenceRequestHandler()
    private var recordingStartedAt: TimeInterval?
    private let tracker = PartnerPoseTracker()
    
    /// Detect poses from pixel buffer (used by live camera for accurate coordinates)
    func detectPoses(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
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
        
        let allPoses = tracker.update(with: observations)
        
        DispatchQueue.main.async {
            self.keypoints = allPoses
            
            if self.isRecording {
                self.recordedKeypoints.append(allPoses)
                let startedAt = self.recordingStartedAt ?? ProcessInfo.processInfo.systemUptime
                self.recordedFrameTimes.append(ProcessInfo.processInfo.systemUptime - startedAt)
            }
        }
        
    }

    func resetTracking() {
        tracker.reset()
    }
    
    // Recording controls
    func startRecording() {
        recordedKeypoints = []
        recordedFrameTimes = []
        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        isRecording = true
        print("🔴 Recording started (Vision)")
    }
    
    func stopRecording() {
        isRecording = false
        recordingStartedAt = nil
        print("⏹️ Recording stopped - captured \(recordedKeypoints.count) frames")
    }
    
    func clearRecording() {
        recordedKeypoints = []
        recordedFrameTimes = []
        recordingStartedAt = nil
        tracker.reset()
        print("🗑️ Recording cleared")
    }
}
