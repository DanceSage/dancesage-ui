import AVFoundation
import CoreGraphics
import SwiftUI
import UIKit

enum VideoExportError: LocalizedError {
    case noVideoTrack
    case readerFailed(String)
    case writerFailed(String)
    case renderFailed
    case audioMergeFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "This recording has no video track to export."
        case .readerFailed(let message):
            return "DanceSage could not read the recording: \(message)"
        case .writerFailed(let message):
            return "DanceSage could not write the exported video: \(message)"
        case .renderFailed:
            return "DanceSage could not draw the skeleton onto the video."
        case .audioMergeFailed:
            return "DanceSage exported the video but could not add the original audio."
        }
    }
}

/// Renders a recording's skeleton onto its video and writes a shareable file.
///
/// The skeleton is drawn by `SkeletonOverlay` — the same view used during playback — so the
/// exported video always matches what the dancer saw on screen. Frames are composited one at a
/// time so memory stays flat regardless of recording length.
@MainActor
enum VideoExporter {

    enum Content {
        /// The dancer with the skeleton tracking them — the recognizable DanceSage look.
        case skeletonOverVideo
        /// Skeleton on a plain background. Nobody in frame is identifiable, which is the safe
        /// option for partner recordings where the second dancer has not agreed to be posted.
        case skeletonOnly
    }

    struct Options {
        var content: Content = .skeletonOverVideo
        /// Silent is the default: a recording made at a venue carries music the dancer has no
        /// right to redistribute. See dancesage-product-strategy/docs/decisions-and-constraints.md.
        var includeOriginalAudio: Bool = false
        /// Matches the white backdrop used by playback's Skeleton mode, which the jewel-toned
        /// limb colours in `SkeletonOverlay` were chosen against.
        var skeletonBackground: CGColor = UIColor.white.cgColor
        /// Longest output edge. Keeps exports reasonable on older devices.
        var maximumDimension: CGFloat = 1920
    }

    /// - Parameter progress: called on the main actor with a value from 0 to 1.
    /// - Returns: a temporary file URL suitable for `ShareLink`.
    static func exportSkeletonVideo(
        videoURL: URL,
        keypoints: [[[CGPoint]]],
        frameTimes: [Double],
        useVisionIndices: Bool,
        name: String,
        options: Options = Options(),
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.noVideoTrack
        }

        // A video composition bakes in the track's preferred transform, so frames arrive upright
        // and we never have to reason about rotation ourselves.
        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        let renderSize = scaledRenderSize(composition.renderSize, limit: options.maximumDimension)
        composition.renderSize = renderSize

        let duration = try await asset.load(.duration).seconds

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerOutput.videoComposition = composition
        guard reader.canAdd(readerOutput) else {
            throw VideoExportError.readerFailed("unsupported video format")
        }
        reader.add(readerOutput)

        let silentURL = temporaryURL(for: name, suffix: "skeleton-silent")
        let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mov)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(renderSize.width),
                AVVideoHeightKey: Int(renderSize.height)
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw VideoExportError.writerFailed("unsupported output format")
        }
        writer.add(writerInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.startWriting() else {
            throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw VideoExportError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue

        while let sample = readerOutput.copyNextSampleBuffer() {
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
            let seconds = presentationTime.seconds

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            guard let pool = adaptor.pixelBufferPool else {
                throw VideoExportError.writerFailed("no pixel buffer pool")
            }
            var destination: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
                  let destinationBuffer = destination else {
                throw VideoExportError.renderFailed
            }

            let overlay = overlayImage(
                for: seconds,
                keypoints: keypoints,
                frameTimes: frameTimes,
                useVisionIndices: useVisionIndices,
                size: renderSize
            )

            try composite(
                source: options.content == .skeletonOverVideo ? sourceBuffer : nil,
                background: options.content == .skeletonOnly ? options.skeletonBackground : nil,
                overlay: overlay,
                into: destinationBuffer,
                size: renderSize,
                colorSpace: colorSpace,
                bitmapInfo: bitmapInfo
            )

            if !adaptor.append(destinationBuffer, withPresentationTime: presentationTime) {
                throw VideoExportError.writerFailed(
                    writer.error?.localizedDescription ?? "frame rejected"
                )
            }

            if duration > 0 {
                progress(min(seconds / duration, 1) * (options.includeOriginalAudio ? 0.9 : 1))
            }
        }

        if reader.status == .failed {
            throw VideoExportError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw VideoExportError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }

        guard options.includeOriginalAudio else {
            progress(1)
            return silentURL
        }

        let merged = try await mergeOriginalAudio(into: silentURL, from: asset, name: name)
        try? FileManager.default.removeItem(at: silentURL)
        progress(1)
        return merged
    }

    // MARK: - Skeleton rendering

    /// Renders the skeleton for the frame active at `seconds`.
    ///
    /// `videoAspect` is set to the output aspect so `SkeletonOverlay`'s aspect-fill crop math
    /// resolves to an identity mapping — normalized keypoints land directly on output pixels.
    private static func overlayImage(
        for seconds: Double,
        keypoints: [[[CGPoint]]],
        frameTimes: [Double],
        useVisionIndices: Bool,
        size: CGSize
    ) -> CGImage? {
        guard let index = frameIndex(at: seconds, frameTimes: frameTimes, frameCount: keypoints.count),
              !keypoints[index].isEmpty else { return nil }

        let renderer = ImageRenderer(
            content: SkeletonOverlay(
                keypoints: keypoints[index],
                useVisionIndices: useVisionIndices,
                videoAspect: size.width / max(size.height, 1)
            )
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }

    /// Largest frame whose timestamp is at or before `seconds`, so the skeleton holds the last
    /// known pose rather than blinking out between pose samples.
    private static func frameIndex(at seconds: Double, frameTimes: [Double], frameCount: Int) -> Int? {
        guard frameCount > 0 else { return nil }
        guard frameTimes.count == frameCount else {
            return min(max(Int(seconds * 15), 0), frameCount - 1)
        }
        guard seconds >= frameTimes[0] else { return nil }

        var low = 0
        var high = frameCount - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if frameTimes[middle] <= seconds { low = middle } else { high = middle - 1 }
        }
        return low
    }

    // MARK: - Compositing

    /// Draws the source frame and the skeleton into `destination` under a single transform, so the
    /// two can never drift out of alignment with each other.
    ///
    /// Pass `source: nil` with a `background` colour to render the skeleton on its own.
    private static func composite(
        source: CVPixelBuffer?,
        background: CGColor?,
        overlay: CGImage?,
        into destination: CVPixelBuffer,
        size: CGSize,
        colorSpace: CGColorSpace,
        bitmapInfo: UInt32
    ) throws {
        CVPixelBufferLockBaseAddress(destination, [])
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(destination),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(destination),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw VideoExportError.renderFailed
        }

        let rect = CGRect(origin: .zero, size: size)
        context.clear(rect)

        if let background {
            context.setFillColor(background)
            context.fill(rect)
        }

        // Core Graphics draws bottom-up; both images go through the same flip so the skeleton
        // stays registered to the dancer.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        if let source {
            CVPixelBufferLockBaseAddress(source, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

            if let sourceImage = makeImage(from: source, colorSpace: colorSpace, bitmapInfo: bitmapInfo) {
                context.draw(sourceImage, in: rect)
            }
        }
        if let overlay {
            context.draw(overlay, in: rect)
        }
    }

    private static func makeImage(
        from buffer: CVPixelBuffer,
        colorSpace: CGColorSpace,
        bitmapInfo: UInt32
    ) -> CGImage? {
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        return CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )?.makeImage()
    }

    // MARK: - Audio

    private static func mergeOriginalAudio(
        into videoURL: URL,
        from sourceAsset: AVAsset,
        name: String
    ) async throws -> URL {
        guard let audioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first else {
            return videoURL
        }

        let renderedAsset = AVURLAsset(url: videoURL)
        guard let renderedVideoTrack = try await renderedAsset.loadTracks(withMediaType: .video).first else {
            return videoURL
        }

        let composition = AVMutableComposition()
        guard let videoSlot = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioSlot = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoExportError.audioMergeFailed
        }

        let videoDuration = try await renderedAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: videoDuration)
        try videoSlot.insertTimeRange(range, of: renderedVideoTrack, at: .zero)

        // The audio track can be marginally longer than the rendered video; clamp it so the
        // export does not end on a frozen frame.
        let audioDuration = try await audioTrack.load(.timeRange).duration
        let audioRange = CMTimeRange(start: .zero, duration: min(audioDuration, videoDuration))
        try audioSlot.insertTimeRange(audioRange, of: audioTrack, at: .zero)

        let outputURL = temporaryURL(for: name, suffix: "skeleton")
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoExportError.audioMergeFailed
        }

        if #available(iOS 18.0, *) {
            try await session.export(to: outputURL, as: .mov)
        } else {
            session.outputURL = outputURL
            session.outputFileType = .mov
            await session.export()
            if session.status != .completed {
                throw VideoExportError.audioMergeFailed
            }
        }
        return outputURL
    }

    // MARK: - Helpers

    /// H.264 requires even dimensions, and we cap the long edge to keep exports quick.
    private static func scaledRenderSize(_ size: CGSize, limit: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1080, height: 1920) }
        let scale = min(1, limit / max(size.width, size.height))
        let width = (size.width * scale).rounded()
        let height = (size.height * scale).rounded()
        return CGSize(
            width: max(2, width - width.truncatingRemainder(dividingBy: 2)),
            height: max(2, height - height.truncatingRemainder(dividingBy: 2))
        )
    }

    private static func temporaryURL(for name: String, suffix: String) -> URL {
        let safeName = name
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safeName.isEmpty ? "DanceSage" : safeName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(suffix).mov")
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
