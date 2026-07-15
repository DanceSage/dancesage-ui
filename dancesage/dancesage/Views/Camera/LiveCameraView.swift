import AVFoundation
import SwiftUI
import UIKit

struct LiveCameraView: UIViewRepresentable {
    @ObservedObject var poseDetector: PoseDetector
    @ObservedObject var visionDetector: VisionPoseDetector
    let isPartnerMode: Bool
    let cameraPosition: AVCaptureDevice.Position
    let recordingRequested: Bool
    let onRecordingStarted: () -> Void
    let onRecordingFinished: (URL) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attachPreview(view.previewLayer)
        context.coordinator.configure(position: cameraPosition)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.update(
            isPartnerMode: isPartnerMode,
            position: cameraPosition,
            recordingRequested: recordingRequested,
            onRecordingStarted: onRecordingStarted,
            onRecordingFinished: onRecordingFinished,
            onError: onError
        )
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            poseDetector: poseDetector,
            visionDetector: visionDetector,
            isPartnerMode: isPartnerMode,
            onRecordingStarted: onRecordingStarted,
            onRecordingFinished: onRecordingFinished,
            onError: onError
        )
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "com.dancesage.capture.session")
        private let videoQueue = DispatchQueue(label: "com.dancesage.capture.frames", qos: .userInitiated)
        private let videoOutput = AVCaptureVideoDataOutput()
        private let movieOutput = AVCaptureMovieFileOutput()
        private let imageContext = CIContext()
        private let poseDetector: PoseDetector
        private let visionDetector: VisionPoseDetector

        private weak var previewLayer: AVCaptureVideoPreviewLayer?
        private var currentPosition: AVCaptureDevice.Position = .unspecified
        private var desiredPosition: AVCaptureDevice.Position
        private var isPartnerMode: Bool
        private var recordingRequested = false
        private var configured = false
        private var lastDetectionTime = 0

        private var onRecordingStarted: () -> Void
        private var onRecordingFinished: (URL) -> Void
        private var onError: (String) -> Void

        init(
            poseDetector: PoseDetector,
            visionDetector: VisionPoseDetector,
            isPartnerMode: Bool,
            onRecordingStarted: @escaping () -> Void,
            onRecordingFinished: @escaping (URL) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.poseDetector = poseDetector
            self.visionDetector = visionDetector
            self.isPartnerMode = isPartnerMode
            self.desiredPosition = .back
            self.onRecordingStarted = onRecordingStarted
            self.onRecordingFinished = onRecordingFinished
            self.onError = onError
        }

        func attachPreview(_ previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            previewLayer.session = session
        }

        func configure(position: AVCaptureDevice.Position) {
            desiredPosition = position
            requestCameraAccessAndConfigure()
        }

        func update(
            isPartnerMode: Bool,
            position: AVCaptureDevice.Position,
            recordingRequested: Bool,
            onRecordingStarted: @escaping () -> Void,
            onRecordingFinished: @escaping (URL) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.isPartnerMode = isPartnerMode
            self.onRecordingStarted = onRecordingStarted
            self.onRecordingFinished = onRecordingFinished
            self.onError = onError

            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.desiredPosition = position
                self.recordingRequested = recordingRequested
                if self.configured, position != self.currentPosition, !self.movieOutput.isRecording {
                    self.replaceVideoInput(position: position)
                }
                self.synchronizeRecordingState()
            }
        }

        func stopSession() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
                if self.session.isRunning { self.session.stopRunning() }
            }
        }

        private func requestCameraAccessAndConfigure() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                requestMicrophoneAccessAndConfigure()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    guard let self else { return }
                    granted ? self.requestMicrophoneAccessAndConfigure() : self.report("Camera access is required to record a dance.")
                }
            default:
                report("Camera access is disabled. Enable it in Settings to record a dance.")
            }
        }

        private func requestMicrophoneAccessAndConfigure() {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in self?.setupSession() }
            default:
                setupSession()
            }
        }

        private func setupSession() {
            sessionQueue.async { [weak self] in
                guard let self, !self.configured else { return }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

                guard self.addVideoInput(position: self.desiredPosition) else {
                    self.session.commitConfiguration()
                    self.report("The selected camera is unavailable.")
                    return
                }
                self.addAudioInputIfAuthorized()

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
                if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }

                self.session.commitConfiguration()
                self.configured = true
                self.configureConnections(position: self.currentPosition)
                self.session.startRunning()
                self.synchronizeRecordingState()
            }
        }

        private func addVideoInput(position: AVCaptureDevice.Position) -> Bool {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return false }
            session.addInput(input)
            currentPosition = position
            return true
        }

        private func replaceVideoInput(position: AVCaptureDevice.Position) {
            let previousInput = session.inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.video) }

            session.beginConfiguration()
            if let previousInput { session.removeInput(previousInput) }
            if !addVideoInput(position: position), let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
                currentPosition = previousInput.device.position
                report("Could not switch cameras.")
            }
            session.commitConfiguration()
            configureConnections(position: currentPosition)
        }

        private func addAudioInputIfAuthorized() {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                  let microphone = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: microphone),
                  session.canAddInput(input) else { return }
            session.addInput(input)
        }

        private func configureConnections(position: AVCaptureDevice.Position) {
            let isFront = position == .front
            [videoOutput.connection(with: .video), movieOutput.connection(with: .video)].forEach { connection in
                guard let connection else { return }
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isFront
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let connection = self?.previewLayer?.connection else { return }
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = isFront
                }
            }
        }

        private func synchronizeRecordingState() {
            guard configured, session.isRunning else { return }
            if recordingRequested, !movieOutput.isRecording {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DanceSage-\(UUID().uuidString)")
                    .appendingPathExtension("mov")
                try? FileManager.default.removeItem(at: url)
                movieOutput.startRecording(to: url, recordingDelegate: self)
            } else if !recordingRequested, movieOutput.isRecording {
                movieOutput.stopRecording()
            }
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            let timestamp = Int(ProcessInfo.processInfo.systemUptime * 1_000)
            guard timestamp - lastDetectionTime >= 50,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            lastDetectionTime = timestamp

            if isPartnerMode {
                visionDetector.detectPoses(in: pixelBuffer, orientation: .up)
            } else {
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return }
                poseDetector.detectAsync(image: UIImage(cgImage: cgImage), timestamp: timestamp)
            }
        }

        func fileOutput(
            _ output: AVCaptureFileOutput,
            didStartRecordingTo fileURL: URL,
            from connections: [AVCaptureConnection]
        ) {
            DispatchQueue.main.async { [weak self] in self?.onRecordingStarted() }
        }

        func fileOutput(
            _ output: AVCaptureFileOutput,
            didFinishRecordingTo outputFileURL: URL,
            from connections: [AVCaptureConnection],
            error: Error?
        ) {
            let completedSuccessfully = (error as NSError?)?
                .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if completedSuccessfully {
                    self.onRecordingFinished(outputFileURL)
                } else {
                    self.onError(error?.localizedDescription ?? "The video could not be recorded.")
                }
            }
        }

        private func report(_ message: String) {
            DispatchQueue.main.async { [weak self] in self?.onError(message) }
        }
    }
}
