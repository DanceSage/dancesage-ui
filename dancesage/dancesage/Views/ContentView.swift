import SwiftUI
import AVFoundation

struct ContentView: View {
    // MediaPipe for single person (Styling mode)
    @StateObject private var poseDetector = PoseDetector()
    // Apple Vision for multi-person (Partner mode) - much better detection!
    @StateObject private var visionDetector = VisionPoseDetector()
    
    @State private var showCamera = false
    @State private var showPlayback = false
    @State private var selectedMode: LandingView.DanceMode = .styling
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var recordingRequested = false
    @State private var captureActive = false
    @State private var capturedVideoURL: URL?
    @State private var captureError = ""
    
    // Use Vision for Partner mode, MediaPipe for Styling
    private var isPartnerMode: Bool { selectedMode == .partner }
    private var currentKeypoints: [[CGPoint]] {
        isPartnerMode ? visionDetector.keypoints : poseDetector.keypoints
    }
    private var currentRecordedKeypoints: [[[CGPoint]]] {
        isPartnerMode ? visionDetector.recordedKeypoints : poseDetector.recordedKeypoints
    }
    private var currentRecordedWorldKeypoints: [[[PosePoint3D]]] {
        isPartnerMode ? [] : poseDetector.recordedWorldKeypoints
    }
    private var currentRecordedFrameTimes: [Double] {
        isPartnerMode ? visionDetector.recordedFrameTimes : poseDetector.recordedFrameTimes
    }
    private var isRecording: Bool { recordingRequested || captureActive }
    
    var body: some View {
        if showCamera {
            ZStack {
                LiveCameraView(
                    poseDetector: poseDetector,
                    visionDetector: visionDetector,
                    isPartnerMode: isPartnerMode,
                    cameraPosition: cameraPosition,
                    recordingRequested: recordingRequested,
                    onRecordingStarted: recordingStarted,
                    onRecordingFinished: recordingFinished,
                    onError: { captureError = $0 }
                )
                .ignoresSafeArea()
                
                SkeletonOverlay(keypoints: currentKeypoints, useVisionIndices: isPartnerMode)
                    .ignoresSafeArea()
                
                VStack {
                    // Back button and mode indicator at top
                    HStack {
                        Button(action: {
                            recordingRequested = false
                            showCamera = false
                            removeTemporaryVideo()
                            poseDetector.clearRecording()
                            visionDetector.clearRecording()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .padding()
                        }
                        .disabled(isRecording)
                        
                        Spacer()

                        Button(action: switchCamera) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .disabled(isRecording)
                        
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
                        if capturedVideoURL != nil && !currentRecordedKeypoints.isEmpty && !isRecording {
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
                            if recordingRequested {
                                recordingRequested = false
                            } else {
                                beginRecording()
                            }
                        }) {
                            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                                .font(.system(size: 70))
                                .foregroundColor(isRecording ? .red : .white)
                        }
                        .disabled(captureActive && !recordingRequested)
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
                    recordingMode: isPartnerMode ? .partner : .styling,
                    videoURL: capturedVideoURL,
                    cameraPosition: cameraPosition == .front ? "front" : "back",
                    worldKeypoints: currentRecordedWorldKeypoints
                )
            }
            .alert("Camera Error", isPresented: Binding(
                get: { !captureError.isEmpty },
                set: { if !$0 { captureError = "" } }
            )) {
                Button("OK", role: .cancel) { captureError = "" }
            } message: {
                Text(captureError)
            }
        } else {
            LandingView(showCamera: $showCamera, selectedMode: $selectedMode)
        }
    }
    
    func loadAllRecordings() -> [DanceRecording] {
        (try? RecordingStore.shared.load()) ?? []
    }

    private func beginRecording() {
        removeTemporaryVideo()
        poseDetector.clearRecording()
        visionDetector.clearRecording()
        recordingRequested = true
    }

    private func recordingStarted() {
        captureActive = true
        if isPartnerMode {
            visionDetector.startRecording()
        } else {
            poseDetector.startRecording()
        }
    }

    private func recordingFinished(_ url: URL) {
        recordingRequested = false
        captureActive = false
        if isPartnerMode {
            visionDetector.stopRecording()
        } else {
            poseDetector.stopRecording()
        }
        capturedVideoURL = url
    }

    private func switchCamera() {
        removeTemporaryVideo()
        poseDetector.clearRecording()
        visionDetector.clearRecording()
        cameraPosition = cameraPosition == .back ? .front : .back
    }

    private func removeTemporaryVideo() {
        if let capturedVideoURL { try? FileManager.default.removeItem(at: capturedVideoURL) }
        capturedVideoURL = nil
    }
}
