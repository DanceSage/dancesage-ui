import Foundation
import Combine
import CoreGraphics

/// Posting a recording to your profile.
///
/// The video is optional; the pose track is not. That is the platform rule — no
/// skeleton, no post — and the server enforces it by rejecting a request without
/// one, so it cannot be worked around by a client that forgets.
@MainActor
final class DanceSagePublisher: ObservableObject {

    enum Stage: Equatable {
        case idle
        case compressing
        case uploading(Double)
        case done(id: Int, visibility: String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .compressing, .uploading: return true
            default: return false
            }
        }
    }

    @Published private(set) var stage: Stage = .idle

    /// - Parameters:
    ///   - keypoints: `[frame][person][joint]`, normalised 0–1 as the detector produced them.
    ///   - videoURL: the original capture. Compressed for delivery before it is sent;
    ///     the file on the device is left untouched.
    /// The id the server gave the post, once it exists.
    private(set) var lastPublishedID: Int?

    func publish(title: String,
                 note: String = "",
                 style: String = "Bachata",
                 level: String = "All levels",
                 visibility: String = "private",
                 keypoints: [[[CGPoint]]],
                 world: [[[PosePoint3D]]] = [],
                 frameTimes: [Double] = [],
                 fps: Double,
                 videoURL: URL?) async {
        guard !keypoints.isEmpty, !keypoints[0].isEmpty else {
            stage = .failed("This recording has no pose data, so it cannot be posted.")
            return
        }
        guard let base = AppConfig.platformBaseURL else {
            stage = .failed("Dance Sage server is not configured."); return
        }
        guard let token = DanceSageAuth.shared.sessionToken else {
            stage = .failed("Sign in to post."); return
        }

        do {
            var upload: URL?
            if let videoURL {
                stage = .compressing
                upload = try await VideoCompressor.compress(videoURL)
            }

            stage = .uploading(0)
            var form = MultipartForm()
            form.add("title", title)
            form.add("note", note)
            form.add("style", style)
            form.add("level", level)
            form.add("visibility", visibility)
            form.add("fps", String(fps))
            // When each pose frame was actually captured. Detection is throttled
            // and irregular, so a viewer that assumes an even spacing watches the
            // skeleton drift away from the body it is drawn on.
            if frameTimes.count == keypoints.count, !frameTimes.isEmpty,
               let times = try? JSONSerialization.data(withJSONObject: frameTimes) {
                form.add("times", String(decoding: times, as: UTF8.self))
            }
            // Two tracks from one recording, stored separately so the viewer can
            // switch: the 2D one lies on the video, the other stands on its own.
            form.add("pose2d", try poseJSON(keypoints, dimensions: 2))
            // Metric 3D when the recording has it. Falling back to flattened 2D
            // keeps older recordings postable, but it is a placeholder — a track
            // with no depth cannot be turned, and cannot train anything.
            if world.count == keypoints.count, !world.isEmpty {
                form.add("pose3d", try worldJSON(world))
            } else {
                form.add("pose3d", try poseJSON(keypoints, dimensions: 3))
            }
            if let upload {
                form.addFile("video", filename: "clip.mp4",
                             mime: "video/mp4", data: try Data(contentsOf: upload))
            }

            var request = URLRequest(url: base.appendingPathComponent("v1/videos"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 300

            let (data, response) = try await URLSession.shared.upload(
                for: request, from: form.finish())

            if let upload { try? FileManager.default.removeItem(at: upload) }

            guard let http = response as? HTTPURLResponse else {
                stage = .failed("No response from Dance Sage."); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let detail = (json ?? nil)?["detail"] as? String
                stage = .failed(detail ?? "Dance Sage returned \(http.statusCode).")
                return
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let newID = json?["id"] as? Int ?? 0
            lastPublishedID = newID
            stage = .done(id: newID,
                          visibility: json?["visibility"] as? String ?? visibility)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    func reset() { stage = .idle }

    /// Metric 3D, transposed the same way, in metres.
    ///
    /// Negated in y and z: MediaPipe's world frame has y pointing down and z
    /// toward the camera, while everything that reads these — the players here
    /// and on the web, and the research pipeline — assumes y up and z away.
    private func worldJSON(_ world: [[[PosePoint3D]]]) throws -> String {
        let people = world.map(\.count).max() ?? 1
        var byPerson: [[[[Double]]]] = []
        for person in 0..<people {
            var track: [[[Double]]] = []
            track.reserveCapacity(world.count)
            for frame in world where person < frame.count {
                track.append(frame[person].map {
                    [Double($0.x), Double(-$0.y), Double(-$0.z)]
                })
            }
            if !track.isEmpty { byPerson.append(track) }
        }
        guard !byPerson.isEmpty else { throw PlatformError.server("No joints to post.") }
        let data = try JSONSerialization.data(withJSONObject: ["j": byPerson])
        return String(decoding: data, as: UTF8.self)
    }

    /// The detector gives `[frame][person][joint]`; the platform stores
    /// `[person][frame][joint]`. Transposed here rather than on the server so the
    /// stored shape matches what the web player already reads.
    ///
    /// - Parameter dimensions: 2 for the track that overlays the video, where the
    ///   coordinates are the video's own normalised frame; 3 for the standalone
    ///   skeleton. Depth is zero until the fitting pipeline supplies real values,
    ///   and the renderer detects that rather than pretending otherwise.
    private func poseJSON(_ keypoints: [[[CGPoint]]], dimensions: Int) throws -> String {
        let frames = keypoints.count
        let people = keypoints.map(\.count).max() ?? 1
        var byPerson: [[[[Double]]]] = []
        for person in 0..<people {
            var track: [[[Double]]] = []
            track.reserveCapacity(frames)
            for frame in keypoints {
                guard person < frame.count else { continue }
                track.append(frame[person].map {
                    dimensions == 2 ? [Double($0.x), Double($0.y)]
                                    : [Double($0.x), Double($0.y), 0]
                })
            }
            if !track.isEmpty { byPerson.append(track) }
        }
        guard !byPerson.isEmpty else { throw PlatformError.server("No joints to post.") }
        let data = try JSONSerialization.data(withJSONObject: ["j": byPerson])
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - multipart/form-data

private struct MultipartForm {
    let boundary = "dancesage.\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append(value)
        body.append("\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mime: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    mutating func finish() -> Data {
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ s: String) { append(Data(s.utf8)) }
}
