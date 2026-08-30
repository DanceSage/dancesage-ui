import AVFoundation
import Foundation

/// Makes a delivery copy of a recording before it is uploaded.
///
/// Capture stays at full quality — that file is the master and never leaves the device
/// degraded. What goes to the cloud is a separate, smaller copy, because storage is the
/// only thing metered: a clip costs the same to serve whether it is watched once or a
/// million times, but it costs every month for as long as it is stored.
///
/// H.264 rather than HEVC, deliberately. HEVC is ~40% smaller for the same quality, but
/// browser support outside Safari is unreliable and the web is where these are watched.
/// At a fixed bitrate the file size — and so the bill — is identical either way.
enum VideoCompressor {

    struct Settings {
        /// 4 Mbps at 1080p is good for short clips. A 20-second post lands near 10 MB.
        var bitrate: Int = 4_000_000
        var maximumDimension: CGFloat = 1080
        var codec: AVVideoCodecType = .h264
        var keepAudio: Bool = false

        static let delivery = Settings()
    }

    enum Failure: LocalizedError {
        case noVideoTrack
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:       return "That recording has no video to upload."
            case .writeFailed(let m): return "Could not prepare the video for upload: \(m)"
            }
        }
    }

    /// - Returns: a temporary file to upload, and the size saved.
    static func compress(_ source: URL,
                         settings: Settings = .delivery) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).mp4")

        let reader = try AVAssetReader(asset: asset)

        // The phone records HLG / BT.2020 10-bit HDR by default. Handing those pixels
        // straight to an 8-bit encoder produces flat, washed-out video, so read through
        // a composition tagged Rec.709 — that is what makes AVFoundation tone-map rather
        // than just truncate.
        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        readerOutput.videoComposition = composition
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw Failure.writeFailed("cannot read source") }
        reader.add(readerOutput)

        // The composition renders upright at full resolution; the writer does the
        // downscale, which is why renderSize is left alone above.
        let size = fit(composition.renderSize, within: settings.maximumDimension)

        // .mp4 rather than .mov — the container every browser expects.
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true
            ],
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            // Tag the result SDR, so players show it the way it was tone-mapped.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure.writeFailed("cannot write H.264") }
        writer.add(input)

        guard reader.startReading() else {
            throw Failure.writeFailed(reader.error?.localizedDescription ?? "read failed")
        }
        guard writer.startWriting() else {
            throw Failure.writeFailed(writer.error?.localizedDescription ?? "write failed")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "com.dancesage.compress")
        await withCheckedContinuation { continuation in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = readerOutput.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    input.append(sample)
                }
            }
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw Failure.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
        return output
    }

    private static func fit(_ size: CGSize, within longest: CGFloat) -> CGSize {
        let scale = min(1, longest / max(size.width, size.height))
        // Even dimensions — H.264 encoders require it.
        return CGSize(width: (size.width * scale / 2).rounded() * 2,
                      height: (size.height * scale / 2).rounded() * 2)
    }
}
