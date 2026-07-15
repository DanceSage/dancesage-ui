import Foundation
import Combine
import MediaPipeTasksVision
import UIKit

class PoseDetector: NSObject, ObservableObject {
    @Published var keypoints: [[CGPoint]] = []
    @Published var recordedKeypoints: [[[CGPoint]]] = []
    @Published var isRecording = false
    
    private var poseLandmarker: PoseLandmarker?
    private var currentNumPoses: Int = 1
    
    override init() {
        super.init()
        setupPoseLandmarker(numPoses: 1)
    }
    
    func setMode(numPoses: Int) {
        guard numPoses != currentNumPoses else { return }
        currentNumPoses = numPoses
        setupPoseLandmarker(numPoses: numPoses)
        print("🔄 Switched to \(numPoses == 1 ? "Styling" : "Partner") mode")
    }
    
    private func setupPoseLandmarker(numPoses: Int) {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_heavy", ofType: "task") else {
            print("❌ Model file not found")
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = numPoses
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
    
    // Full 33 MediaPipe landmarks:
    // 0: nose
    // 1: left eye inner, 2: left eye, 3: left eye outer
    // 4: right eye inner, 5: right eye, 6: right eye outer
    // 7: left ear, 8: right ear
    // 9: mouth left, 10: mouth right
    // 11: left shoulder, 12: right shoulder
    // 13: left elbow, 14: right elbow
    // 15: left wrist, 16: right wrist
    // 17: left pinky, 18: right pinky
    // 19: left index, 20: right index
    // 21: left thumb, 22: right thumb
    // 23: left hip, 24: right hip
    // 25: left knee, 26: right knee
    // 27: left ankle, 28: right ankle
    // 29: left heel, 30: right heel
    // 31: left foot index, 32: right foot index
    
    func poseLandmarker(_ poseLandmarker: PoseLandmarker,
                        didFinishDetection result: PoseLandmarkerResult?,
                        timestampInMilliseconds: Int,
                        error: Error?) {
        
        if let error = error {
            print("❌ Detection error: \(error)")
            return
        }
        
        guard let result = result else {
            DispatchQueue.main.async { self.keypoints = [] }
            return
        }
        
        // Use ALL 33 landmarks — no mapping, no dropping
        var allPoses: [[CGPoint]] = []
        
        for pose in result.landmarks {
            let points: [CGPoint] = pose.map { landmark in
                CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y))
            }
            allPoses.append(points)
        }
        
        DispatchQueue.main.async {
            self.keypoints = allPoses
            if self.isRecording {
                self.recordedKeypoints.append(allPoses)
            }
        }
    }
}
