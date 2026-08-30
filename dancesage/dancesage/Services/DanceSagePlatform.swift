import Foundation
import CoreGraphics

/// Talks to the Dance Sage platform. Everything here needs a session; the rest of
/// the app does not.

struct PlatformVideo: Identifiable, Decodable {
    let id: Int
    let title: String
    let note: String
    let style: String
    let level: String
    let visibility: String
    let frames: Int
    let has_video: Bool
    let pose_key: String
    let pose2d_key: String
    let video_key: String
    let fps: Int

    var seconds: Int { fps > 0 ? frames / fps : 0 }
    var duration: String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// The 2D track overlays the video; the 3D one is the standalone skeleton.
    var overlayKey: String { pose2d_key.isEmpty ? pose_key : pose2d_key }

    func videoURL(base: URL) -> URL? {
        video_key.isEmpty ? nil : base.appendingPathComponent("video/\(video_key).mov")
    }
}

struct PlatformProfile: Decodable {
    let handle: String
    let display_name: String
    let bio: String
    let city: String
    let styles: String
    let levels: String
    let takes_students: Bool
    let avatar: String
    let videos: [PlatformVideo]

    /// Empty when nobody has set a photo — the header falls back to initials.
    func avatarURL(base: URL?) -> URL? {
        guard !avatar.isEmpty, let base else { return nil }
        return base.appendingPathComponent(avatar.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    var publicCount: Int { videos.filter { $0.visibility == "public" }.count }
}

/// One pose track, as the app produced it and the platform stored it.
/// `j` is `[dancer][frame][joint][x,y,z]`.
struct PoseTrack: Decodable {
    let fps: Int
    let frames: Int
    let j: [[[[Double]]]]

    var joints: Int { j.first?.first?.count ?? 0 }
    var isTwoDimensional: Bool { (j.first?.first?.first?.count ?? 3) == 2 }

    /// A representative frame — a bit past the start, where the movement has begun.
    func poseFrame() -> [[Double]]? {
        guard let dancer = j.first, !dancer.isEmpty else { return nil }
        return dancer[min(dancer.count / 3, dancer.count - 1)]
    }
}

/// Someone you have let in.
struct PlatformGrant: Identifiable, Decodable {
    let id: Int
    let handle: String
    let display_name: String
    let avatar: String
    let since: String
    let video_id: Int?
    /// What this grant covers — a title, or everything shared.
    let scope: String
}

/// A video as the feed and search return it — the same fields as a profile video,
/// plus who danced it. Credit travels with the clip rather than being looked up.
struct FeedVideo: Identifiable, Decodable {
    struct By: Decodable {
        let handle: String
        let display_name: String
        let avatar: String
    }
    let id: Int
    let title: String
    let style: String
    let level: String
    let visibility: String
    let frames: Int
    let fps: Int
    let has_video: Bool
    let dancers: Int
    let pose_key: String
    let pose2d_key: String
    let video_key: String
    let note: String
    let by: By

    var seconds: Int { fps > 0 ? frames / fps : 0 }
    var duration: String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// The detail player takes a PlatformVideo; the two describe the same thing.
    var asPlatformVideo: PlatformVideo {
        PlatformVideo(id: id, title: title, note: note, style: style, level: level,
                      visibility: visibility, frames: frames, has_video: has_video,
                      pose_key: pose_key, pose2d_key: pose2d_key,
                      video_key: video_key, fps: fps)
    }
}

/// Someone who shared their videos with you, and what they shared.
struct SharedFrom: Identifiable, Decodable {
    let handle: String
    let display_name: String
    let avatar: String
    let videos: [FeedVideo]
    var id: String { handle }
}

enum PlatformError: LocalizedError {
    case notSignedIn
    case notConfigured
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:   return "Sign in to see your profile."
        case .notConfigured: return "Dance Sage server is not configured."
        case .server(let m): return m
        }
    }
}

@MainActor
struct DanceSagePlatform {
    static let shared = DanceSagePlatform()
    /// Its own session, so a request that cannot arrive fails in seconds rather
    /// than sitting for the default minute and looking like a hung app.
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 120      // uploads need longer
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// The same data the web owner page renders — one source, two surfaces.
    func me() async throws -> PlatformProfile {
        try JSONDecoder().decode(PlatformProfile.self, from: try await get("v1/me"))
    }

    func poseTrack(key: String) async throws -> PoseTrack {
        let data = try await get("pose/\(key).json")
        return try JSONDecoder().decode(PoseTrack.self, from: data)
    }

    /// A short-lived URL for one video. `AVPlayer` cannot carry an Authorization
    /// header, so playback is authorised by the URL itself.
    func playbackURL(videoID: Int) async throws -> URL {
        let data = try await get("v1/videos/\(videoID)/playback")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["url"] as? String,
              let base = AppConfig.platformBaseURL else {
            throw PlatformError.server("Could not get a playback link.")
        }
        // Absolute in the cloud, relative while the server is local.
        return URL(string: raw) ?? URL(string: base.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")) + raw)!
    }

    // MARK: - Your handle

    struct HandleCheck: Decodable { let ok: Bool; let why: String }

    func handleAvailable(_ handle: String) async throws -> HandleCheck {
        try JSONDecoder().decode(
            HandleCheck.self,
            from: try await get("v1/handles/\(handle.lowercased())/available"))
    }

    func setHandle(_ handle: String) async throws {
        var req = try request("v1/me")
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["handle": handle.lowercased()])
        let (data, response) = try await session.data(for: req)
        try check(response, data)
    }

    // MARK: - Shared with me

    /// The inbound half of a grant — what other people let you see.
    func sharedWithMe() async throws -> [SharedFrom] {
        struct Wrapper: Decodable { let from: [SharedFrom] }
        return try JSONDecoder().decode(Wrapper.self, from: try await get("v1/shared")).from
    }

    // MARK: - Who can see your shared videos

    func grants() async throws -> [PlatformGrant] {
        struct Wrapper: Decodable { let grants: [PlatformGrant] }
        return try JSONDecoder().decode(Wrapper.self, from: try await get("v1/grants")).grants
    }

    /// Give one person access. Naming a video shares just that one and marks it
    /// shared; omitting it covers everything you have marked shared.
    func grant(handle: String, videoID: Int? = nil) async throws {
        var body: [String: Any] = ["handle": handle]
        if let videoID { body["video_id"] = videoID }
        _ = try await send("v1/grants", body: body)
    }

    /// Revoking is a timestamp, not a deletion — the next request from them is refused.
    func revoke(grantID: Int) async throws {
        var req = try request("v1/grants/\(grantID)")
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try check(response, data)
    }

    /// Removes the post, its pose tracks and its video. The recording on the
    /// phone is untouched — this deletes what was published, not what you danced.
    func deleteVideo(id: Int) async throws {
        var req = try request("v1/videos/\(id)")
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try check(response, data)
    }

    func setVisibility(videoID: Int, to visibility: String) async throws {
        _ = try await send("v1/videos/\(videoID)/visibility", body: ["visibility": visibility])
    }

    // MARK: - Plumbing

    private func request(_ path: String) throws -> URLRequest {
        guard let base = AppConfig.platformBaseURL else { throw PlatformError.notConfigured }
        guard let token = DanceSageAuth.shared.sessionToken else { throw PlatformError.notSignedIn }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func get(_ path: String) async throws -> Data {
        let (data, response) = try await session.data(for: try request(path))
        try check(response, data)
        return data
    }

    @discardableResult
    private func send(_ path: String, body: [String: Any]) async throws -> Data {
        var req = try request(path)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        return data
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PlatformError.server("No response from Dance Sage.")
        }
        if http.statusCode == 401 { throw PlatformError.notSignedIn }
        guard (200..<300).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (json ?? nil)?["detail"] as? String
            throw PlatformError.server(detail ?? "Dance Sage returned \(http.statusCode).")
        }
    }
}
