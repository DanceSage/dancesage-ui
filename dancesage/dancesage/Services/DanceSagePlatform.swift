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
    /// An attempt: the video it answers, and whether the student read mirrored.
    var reply_to: Int? = nil
    var mirrored: Bool? = nil

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
    /// When each frame was captured, when the uploader knew. Optional: older
    /// tracks and 3D tracks may not carry it.
    let t: [Double]?
    /// An attempt: the student's own time at each frame, so their video follows.
    let ta: [Double]?

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
    /// False while it is still an offer they have not answered.
    let accepted: Bool?
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
    /// Set on a clip someone shared with you: the grant behind it, so you can decline.
    let grant_id: Int?
    /// The group it came through, when it did.
    let group: GroupRef?
    /// The video this one is an attempt at, when it is.
    let reply_to: Int?
    /// An attempt: the student read left/right flipped.
    let mirrored: Bool?
    /// The series it came through, when it did.
    let series: GroupRef?

    struct GroupRef: Decodable { let id: Int; let name: String }

    var seconds: Int { fps > 0 ? frames / fps : 0 }
    var duration: String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// The detail player takes a PlatformVideo; the two describe the same thing.
    var asPlatformVideo: PlatformVideo {
        PlatformVideo(id: id, title: title, note: note, style: style, level: level,
                      visibility: visibility, frames: frames, has_video: has_video,
                      pose_key: pose_key, pose2d_key: pose2d_key,
                      video_key: video_key, fps: fps, reply_to: reply_to, mirrored: mirrored)
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

/// People you share with together.
struct PlatformGroup: Identifiable, Decodable {
    struct Member: Identifiable, Decodable {
        let handle: String?
        let display_name: String
        let avatar: String
        var id: String { handle ?? display_name }
    }
    let id: Int
    let name: String
    let members: [Member]
    /// Present on groups someone else owns and put you in.
    let owner: Member?
}

/// A folder in My videos, shared as a standing offer.
struct DancerPage: Decodable {
    struct Folder: Identifiable, Decodable {
        let id: Int
        let name: String
        let videos: [FeedVideo]
    }
    let handle: String
    let display_name: String
    let bio: String
    let city: String
    let styles: String
    let levels: String
    let avatar: String
    let folders: [Folder]
    let videos: [FeedVideo]
}

struct PlatformSeries: Identifiable, Decodable {
    struct Who: Identifiable, Decodable {
        let grant_id: Int
        let handle: String?
        let display_name: String
        let accepted: Bool
        let group: String?
        var id: Int { grant_id }
    }
    let id: Int
    let name: String
    let video_count: Int
    let videos: [FeedVideo]
    let owner: PlatformAttemptPerson
    /// Owner's view: who has it.
    let shared_with: [Who]?
    /// Viewer's view: the standing offer behind it.
    let series_grant_id: Int?
    let group: FeedVideo.GroupRef?
}

struct PlatformAttemptPerson: Decodable {
    let handle: String?
    let display_name: String
    var name: String { display_name.isEmpty ? (handle.map { "@\($0)" } ?? "Dancer") : display_name }
}

/// A group's wall: what went through it, both ways.
struct GroupWall: Decodable {
    struct Lesson: Identifiable, Decodable {
        struct Who: Decodable { let handle: String?; let accepted: Bool }
        let id: Int
        let title: String
        let pose_key: String
        let has_video: Bool
        let frames: Int
        let fps: Int
        let members: [Who]
        /// Attempts filed under this lesson.
        let replies: [FeedVideo]
        var video: PlatformVideo {
            PlatformVideo(id: id, title: title, note: "", style: "", level: "", visibility: "private",
                          frames: frames, has_video: has_video, pose_key: pose_key, pose2d_key: "",
                          video_key: "", fps: fps)
        }
    }
    struct Head: Decodable {
        let id: Int
        let name: String
        let mine: Bool
        let members: [PlatformGroup.Member]
        let owner: PlatformGroup.Member
    }
    struct SeriesGroup: Identifiable, Decodable {
        let id: Int
        let name: String
        let videos: [Lesson]
    }
    let group: Head
    /// Videos that came through a series, by series.
    let series: [SeriesGroup]
    let lessons: [Lesson]
    let replies: [FeedVideo]
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
        try await inbox().from
    }

    struct Inbox: Decodable {
        /// What you accepted.
        let from: [SharedFrom]
        /// What is waiting on your yes or no.
        let offers: [SharedFrom]
        /// Series you accepted, and series waiting on you.
        let series: [PlatformSeries]
        let series_offers: [PlatformSeries]
        var offerCount: Int { offers.reduce(0) { $0 + $1.videos.count } }
        var sharedCount: Int { from.reduce(0) { $0 + $1.videos.count } }
    }

    /// A dancer's public page: series as folders, then the loose posts.
    func dancer(handle: String) async throws -> DancerPage {
        try JSONDecoder().decode(DancerPage.self, from: try await get("v1/dancers/\(handle)"))
    }

    func inbox() async throws -> Inbox {
        try JSONDecoder().decode(Inbox.self, from: try await get("v1/shared"))
    }

    func accept(grantID: Int) async throws {
        _ = try await send("v1/shared/\(grantID)/accept", body: [:])
    }

    // MARK: - My lessons online

    /// Sends a saved attempt to the teacher — the owner of the video it
    /// answers — at once, no offer. Harmless to repeat.
    func sendAttempt(id: Int) async throws {
        _ = try await send("v1/lessons/\(id)/send", body: [:])
    }

    struct OnlineLesson: Decodable {
        struct Attempt: Decodable { let id: Int; let sent: Bool }
        struct Lesson: Decodable { let id: Int }
        let id: Int
        let lesson: Lesson
        let attempts: [Attempt]
    }

    /// Add to Lessons, online: the lesson exists from here on. Same video twice is one lesson.
    func addLesson(videoID: Int, name: String) async throws -> Int {
        try JSONDecoder().decode(OnlineLesson.self,
                                 from: try await send("v1/lessons", body: ["video_id": videoID, "name": name])).id
    }

    /// The lesson and every attempt at it.
    func deleteLesson(id: Int) async throws {
        try await delete("v1/lessons/\(id)")
    }

    /// One attempt's online copy — and whatever share carried it to the teacher.
    func deleteAttempt(videoID: Int) async throws {
        try await delete("v1/lessons/attempts/\(videoID)")
    }

    /// Which of your attempts have been sent, by post id.
    func sentAttempts() async throws -> Set<Int> {
        struct Wrapper: Decodable { let lessons: [OnlineLesson] }
        let all = try JSONDecoder().decode(Wrapper.self, from: try await get("v1/lessons")).lessons
        return Set(all.flatMap { $0.attempts }.filter(\.sent).map(\.id))
    }

    /// What I teach: my videos that went out as lessons, with students' attempts.
    struct TeachingClass: Identifiable, Decodable {
        struct Student: Decodable { let handle: String?; let display_name: String; let accepted: Bool }
        let lesson: FeedVideo
        let students: [Student]
        let attempts: [FeedVideo]
        let series: FeedVideo.GroupRef?
        let groups: [String]
        var id: Int { lesson.id }
    }

    func classes() async throws -> [TeachingClass] {
        struct Wrapper: Decodable { let classes: [TeachingClass] }
        return try JSONDecoder().decode(Wrapper.self, from: try await get("v1/classes")).classes
    }

    // MARK: - Series

    func series() async throws -> [PlatformSeries] {
        struct Wrapper: Decodable { let series: [PlatformSeries] }
        return try JSONDecoder().decode(Wrapper.self, from: try await get("v1/series")).series
    }

    func createSeries(name: String) async throws -> PlatformSeries {
        try JSONDecoder().decode(PlatformSeries.self, from: try await send("v1/series", body: ["name": name]))
    }

    func addToSeries(seriesID: Int, videoID: Int) async throws {
        _ = try await send("v1/series/\(seriesID)/videos", body: ["video_id": videoID])
    }

    func removeFromSeries(seriesID: Int, videoID: Int) async throws {
        try await delete("v1/series/\(seriesID)/videos/\(videoID)")
    }

    func deleteSeries(id: Int) async throws {
        try await delete("v1/series/\(id)")
    }

    /// Share a series with a person, or with everyone in a group.
    func grant(seriesID: Int, handle: String? = nil, groupID: Int? = nil) async throws {
        var body: [String: Any] = ["series_id": seriesID]
        if let handle { body["handle"] = handle }
        if let groupID { body["group_id"] = groupID }
        _ = try await send("v1/grants", body: body)
    }

    func revokeSeriesGrant(id: Int) async throws {
        try await delete("v1/series/grants/\(id)")
    }

    func acceptSeries(grantID: Int) async throws {
        _ = try await send("v1/shared/series/\(grantID)/accept", body: [:])
    }

    func declineSeries(grantID: Int) async throws {
        try await delete("v1/shared/series/\(grantID)")
    }

    private func delete(_ path: String) async throws {
        var req = try request(path)
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try check(response, data)
    }

    // MARK: - Who can see your shared videos

    func grants() async throws -> [PlatformGrant] {
        struct Wrapper: Decodable { let grants: [PlatformGrant] }
        return try JSONDecoder().decode(Wrapper.self, from: try await get("v1/grants")).grants
    }

    /// Give one person access. Naming a video shares just that one and marks it
    /// shared; omitting it covers everything you have marked shared.
    /// `repliesTo` matters only when passing on someone else's public video:
    /// "sharer" (you) or "owner" (who made it) receives the attempts.
    func grant(handle: String, videoID: Int? = nil, repliesTo: String? = nil) async throws {
        var body: [String: Any] = ["handle": handle]
        if let videoID { body["video_id"] = videoID }
        if let repliesTo { body["replies_to"] = repliesTo }
        _ = try await send("v1/grants", body: body)
    }

    /// Give everyone in a group access to one video — one grant per member.
    func grant(groupID: Int, videoID: Int, repliesTo: String? = nil) async throws {
        var body: [String: Any] = ["group_id": groupID, "video_id": videoID]
        if let repliesTo { body["replies_to"] = repliesTo }
        _ = try await send("v1/grants", body: body)
    }

    /// Turn down an offer, or stop a share you accepted.
    func decline(grantID: Int) async throws {
        var req = try request("v1/shared/\(grantID)")
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try check(response, data)
    }

    // MARK: - Groups

    struct Groups: Decodable { let groups: [PlatformGroup]; let member_of: [PlatformGroup] }

    func allGroups() async throws -> Groups {
        try JSONDecoder().decode(Groups.self, from: try await get("v1/groups"))
    }

    func groups() async throws -> [PlatformGroup] {
        try await allGroups().groups
    }

    func wall(groupID: Int) async throws -> GroupWall {
        try JSONDecoder().decode(GroupWall.self, from: try await get("v1/groups/\(groupID)/wall"))
    }

    /// A member shares one of their own posts back to the group's owner.
    func shareBack(groupID: Int, videoID: Int) async throws {
        _ = try await send("v1/groups/\(groupID)/share", body: ["video_id": videoID])
    }

    func createGroup(name: String, handles: [String]) async throws -> PlatformGroup {
        try JSONDecoder().decode(PlatformGroup.self,
                                 from: try await send("v1/groups", body: ["name": name, "handles": handles]))
    }

    func addToGroup(groupID: Int, handle: String) async throws {
        _ = try await send("v1/groups/\(groupID)/members", body: ["handle": handle])
    }

    func removeFromGroup(groupID: Int, handle: String) async throws {
        var req = try request("v1/groups/\(groupID)/members/\(handle)")
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try check(response, data)
    }

    func deleteGroup(id: Int) async throws {
        var req = try request("v1/groups/\(id)")
        req.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: req)
        try check(response, data)
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

