import SwiftUI

struct ContentView: View {
    var onSignOut: () -> Void = {}
    // MediaPipe for single person (Styling mode)
    @StateObject private var poseDetector = PoseDetector()
    // Apple Vision for multi-person (Partner mode) - much better detection!
    @StateObject private var visionDetector = VisionPoseDetector()
    
    @State private var showCamera = false
    @State private var showPlayback = false
    @State private var selectedMode: LandingView.DanceMode = .styling
    
    // Use Vision for Partner mode, MediaPipe for Styling
    private var isPartnerMode: Bool { selectedMode == .partner }
    private var currentKeypoints: [[CGPoint]] {
        isPartnerMode ? visionDetector.keypoints : poseDetector.keypoints
    }
    private var currentRecordedKeypoints: [[[CGPoint]]] {
        isPartnerMode ? visionDetector.recordedKeypoints : poseDetector.recordedKeypoints
    }
    private var currentRecordedFrameTimes: [Double] {
        isPartnerMode ? visionDetector.recordedFrameTimes : poseDetector.recordedFrameTimes
    }
    private var isRecording: Bool {
        isPartnerMode ? visionDetector.isRecording : poseDetector.isRecording
    }
    
    var body: some View {
        if showCamera {
            ZStack {
                if isPartnerMode {
                    VisionCameraView(visionDetector: visionDetector)
                        .ignoresSafeArea()
                } else {
                    CameraView(poseDetector: poseDetector)
                        .ignoresSafeArea()
                }
                
                SkeletonOverlay(keypoints: currentKeypoints, useVisionIndices: isPartnerMode)
                    .ignoresSafeArea()
                
                VStack {
                    // Back button and mode indicator at top
                    HStack {
                        Button(action: {
                            showCamera = false
                            poseDetector.clearRecording()
                            visionDetector.clearRecording()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .padding()
                        }
                        
                        Spacer()
                        
                        // Mode indicator
                        Text(selectedMode == .styling ? "STYLING MODE" : "PARTNER MODE")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(selectedMode == .styling ? Color.green : Color.blue)
                            .cornerRadius(20)
                            .padding()
                    }
                    
                    Spacer()
                    
                    // Recording controls at bottom
                    HStack(spacing: 30) {
                        // View Recording button
                        if !currentRecordedKeypoints.isEmpty && !isRecording {
                            Button(action: {
                                showPlayback = true
                            }) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        // Record button
                        Button(action: {
                            if isPartnerMode {
                                if visionDetector.isRecording {
                                    visionDetector.stopRecording()
                                } else {
                                    visionDetector.startRecording()
                                }
                            } else {
                                if poseDetector.isRecording {
                                    poseDetector.stopRecording()
                                } else {
                                    poseDetector.startRecording()
                                }
                            }
                        }) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.system(size: 70))
                                .foregroundColor(isRecording ? .red : .white)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
            .onAppear {
                if !isPartnerMode {
                    // Set MediaPipe mode for single person
                    poseDetector.setMode(numPoses: 1)
                }
                
                let saved = loadAllRecordings()
                print("📚 Loaded \(saved.count) saved recordings:")
                for recording in saved {
                    print("  - \(recording.name) (\(recording.frameCount) frames)")
                }
            }
            .fullScreenCover(isPresented: $showPlayback) {
                SkeletonPlaybackView(
                    keypoints: currentRecordedKeypoints,
                    allowSave: true,
                    useVisionIndices: isPartnerMode,
                    fps: 20,
                    frameTimes: currentRecordedFrameTimes,
                    recordingMode: isPartnerMode ? .partner : .styling
                )
            }
        } else {
            LandingView(showCamera: $showCamera, selectedMode: $selectedMode, onSignOut: onSignOut)
        }
    }
    
    func loadAllRecordings() -> [DanceRecording] {
        (try? RecordingStore.shared.load()) ?? []
    }
}
