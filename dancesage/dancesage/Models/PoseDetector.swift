import Foundation
import Combine
import MediaPipeTasksVision
import UIKit

class PoseDetector: NSObject, ObservableObject {
    @Published var keypoints: [[CGPoint]] = []
    @Published var recordedKeypoints: [[[CGPoint]]] = []
    @Published var isRecording = false
    
    private var poseLandmarker: PoseLandmarker?
    private var currentNumPoses: Int = 1  // Default to single person
    
    override init() {
        super.init()
        setupPoseLandmarker(numPoses: 1)
    }
    
    // Add method to switch between modes
    func setMode(numPoses: Int) {
        guard numPoses != currentNumPoses else { return }
        currentNumPoses = numPoses
        setupPoseLandmarker(numPoses: numPoses)
        print("🔄 Switched to \(numPoses == 1 ? "Styling" : "Partner") mode")
    }
    
    private func setupPoseLandmarker(numPoses: Int) {
        let modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task")
        
        guard let modelPath = modelPath else {
            print("❌ Model file not found")
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = numPoses  // Use the parameter
        options.minPoseDetectionConfidence = 0.1
        options.minPosePresenceConfidence = 0.1
        options.minTrackingConfidence = 0.1
        options.poseLandmarkerLiveStreamDelegate = self
        
        do {
            poseLandmarker = try PoseLandmarker(options: options)
            print("✅ PoseLandmarker initialized with numPoses = \(numPoses)")
        } catch {
            print("❌ Error creating PoseLandmarker: \(error)")
        }
    }
    
    func detectAsync(image: UIImage, timestamp: Int) {
        guard let poseLandmarker = poseLandmarker else { return }
        
        guard let mpImage = try? MPImage(uiImage: image) else {
            print("❌ Failed to convert UIImage to MPImage")
            return
        }
        
        do {
            try poseLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestamp)
        } catch {
            print("❌ Detection async error: \(error)")
        }
    }
    
    // Recording controls
    func startRecording() {
        recordedKeypoints = []
        isRecording = true
        print("🔴 Recording started")
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

// MARK: - PoseLandmarkerLiveStreamDelegate
extension PoseDetector: PoseLandmarkerLiveStreamDelegate {
    
    // Map MediaPipe 33 landmarks to Vision-compatible 17 landmarks
    // MediaPipe indices -> Vision-style indices
    private static let landmarkMapping: [Int] = [
        0,   // nose -> 0
        2,   // left eye -> 1
        5,   // right eye -> 2
        7,   // left ear -> 3
        8,   // right ear -> 4
        11,  // left shoulder -> 5
        12,  // right shoulder -> 6
        13,  // left elbow -> 7
        14,  // right elbow -> 8
        15,  // left wrist -> 9
        16,  // right wrist -> 10
        23,  // left hip -> 11
        24,  // right hip -> 12
        25,  // left knee -> 13
        26,  // right knee -> 14
        27,  // left ankle -> 15
        28,  // right ankle -> 16
    ]
    
    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                       didFinishDetection result: PoseLandmarkerResult?,
                       timestampInMilliseconds: Int,
                       error: Error?) {
        
        if let error = error {
            print("❌ Detection error: \(error)")
            return
        }
        
        guard let result = result else {
            DispatchQueue.main.async {
                self.keypoints = []
            }
            return
        }
        
        // Extract poses with only 17 key landmarks (matching Vision)
        var allPoses: [[CGPoint]] = []
        
        for pose in result.landmarks {
            // Extract only the 17 landmarks that match Vision
            var points: [CGPoint] = []
            for mpIndex in PoseDetector.landmarkMapping {
                if mpIndex < pose.count {
                    let landmark = pose[mpIndex]
                    points.append(CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y)))
                } else {
                    points.append(CGPoint(x: -1, y: -1))
                }
            }
            allPoses.append(points)
        }
        
        DispatchQueue.main.async {
            self.keypoints = allPoses
            
            if self.isRecording {
                self.recordedKeypoints.append(allPoses)
                // Send frame to backend immediately
                let frameIndex = self.recordedKeypoints.count - 1
                Task {
                    await APIService.shared.uploadFrame(allPoses, frameIndex: frameIndex)
                }
            }
        }
    }
}
