import Foundation
import CoreGraphics

/// The teacher's refined 3D skeleton: 70 MHR joints a frame, in metres, in the
/// camera's own frame of reference (x right, y down, z away from the lens).
///
/// This is what makes a 3D lesson worth paying for. The student no longer has to
/// stand where the teacher stood: she picks an angle, the skeleton turns to meet
/// her, and the ghost she follows is that turned skeleton flattened back onto the
/// camera. Nothing is converted to another layout on the way — MHR70 is drawn as
/// MHR70, because the moment two layouts are mixed nobody can say what a score
/// means.
///
/// A reference type, not a struct, because framing is cached per angle and the
/// whole point is that the ghost does not breathe as limbs extend.
final class Body3DTrack {
    static let jointCount = 70

    /// The MHR70 indices we actually draw. The other fifty are fingers and face,
    /// which cost a lot of ink and say nothing about salsa.
    enum J {
        static let nose = 0
        static let leftShoulder = 5, rightShoulder = 6
        static let leftElbow = 7, rightElbow = 8
        static let leftHip = 9, rightHip = 10
        static let leftKnee = 11, rightKnee = 12
        static let leftAnkle = 13, rightAnkle = 14
        static let leftBigToe = 15, leftHeel = 17
        static let rightBigToe = 18, rightHeel = 20
        static let rightWrist = 41, leftWrist = 62
        static let neck = 69
    }

    let fps: Double
    let frameCount: Int
    /// person → frame → 70 joints, or nil for a frame where that dancer was not found.
    private let people: [[[SIMD3<Double>]?]]

    /// Framing is worked out once per angle from the whole clip, not per frame:
    /// scaling each frame to its own bounding box would make the ghost swell
    /// every time an arm went up.
    private var framingCache: [Int: Framing] = [:]

    private struct Framing {
        let scale: Double
        let offsetX: Double
        let offsetY: Double
    }

    init(fps: Double, frameCount: Int, people: [[[SIMD3<Double>]?]]) {
        self.fps = fps > 0 ? fps : 30
        self.frameCount = frameCount
        self.people = people
    }

    var dancerCount: Int { people.count }
    var duration: Double { Double(frameCount) / fps }

    // MARK: - Loading

    private struct Payload: Decodable {
        let fps: Double?
        let frames: Int?
        let people: [[[[Double]]?]]
    }

    /// The worker's `joints.json`, exactly as it is written and stored.
    static func decode(_ data: Data) throws -> Body3DTrack {
        let raw = try JSONDecoder().decode(Payload.self, from: data)
        let people: [[[SIMD3<Double>]?]] = raw.people.map { person in
            person.map { frame -> [SIMD3<Double>]? in
                guard let frame, frame.count >= jointCount else { return nil }
                return frame.map { j in
                    j.count >= 3 ? SIMD3(j[0], j[1], j[2]) : SIMD3(0, 0, 0)
                }
            }
        }
        let frames = raw.frames ?? (people.first?.count ?? 0)
        return Body3DTrack(fps: raw.fps ?? 30, frameCount: frames, people: people)
    }

    /// The 3D skeleton behind a lesson, when the lesson came from a post that has
    /// one. Returns nil for an ordinary 2D lesson, which is most of them.
    static func forLesson(_ lesson: Lesson) async -> Body3DTrack? {
        guard let videoID = lesson.sourceVideoID else { return nil }
        guard let info = try? await DanceSagePlatform.shared.body(videoID: videoID),
              let path = info.track?.files?["joints"] else { return nil }
        guard let data = try? await DanceSagePlatform.shared.bodyFile(path: path) else { return nil }
        return try? decode(data)
    }

    // MARK: - The pose, turned and flattened

    /// The joints at a moment, without rotation — camera-frame metres.
    func joints(at time: Double, person: Int = 0) -> [SIMD3<Double>]? {
        guard person < people.count else { return nil }
        let track = people[person]
        guard !track.isEmpty else { return nil }
        let index = min(max(Int((time * fps).rounded()), 0), track.count - 1)
        if let here = track[index] { return here }
        // A dropped frame holds the last good pose rather than blinking out.
        for step in 1...min(12, track.count) {
            if index - step >= 0, let before = track[index - step] { return before }
            if index + step < track.count, let after = track[index + step] { return after }
        }
        return nil
    }

    /// The ghost: the skeleton turned by `yaw` about its own vertical axis, then
    /// projected back onto the screen as normalised 0…1 points, y downward —
    /// exactly what `SkeletonOverlay` draws for every other skeleton.
    ///
    /// `yaw` is in radians. 0 is the angle the teacher was filmed from.
    func projected(at time: Double, yaw: Double, person: Int = 0) -> [CGPoint]? {
        guard let joints = joints(at: time, person: person) else { return nil }
        let framing = framing(forYaw: yaw, person: person)
        return flatten(joints, yaw: yaw, framing: framing)
    }

    /// Turn about the vertical axis through the hips, then divide by depth. The
    /// hips stay where they are, so turning the teacher does not walk them out of
    /// frame.
    private func flatten(_ joints: [SIMD3<Double>], yaw: Double, framing: Framing) -> [CGPoint] {
        let hip = (joints[J.leftHip] + joints[J.rightHip]) / 2
        let cosY = cos(yaw), sinY = sin(yaw)

        return joints.map { j in
            let dx = j.x - hip.x
            let dz = j.z - hip.z
            let x = cosY * dx + sinY * dz
            let z = -sinY * dx + cosY * dz
            let y = j.y - hip.y

            // Depth from the lens after turning. Clamped so a joint that swings
            // behind the camera cannot invert the projection.
            let depth = max(hip.z + z, 0.35)
            let u = x / depth
            let v = y / depth

            return CGPoint(x: u * framing.scale + framing.offsetX,
                           y: v * framing.scale + framing.offsetY)
        }
    }

    /// One framing for the whole clip at this angle: the dancer fills a steady
    /// share of the screen and stands on the same floor from the first frame to
    /// the last.
    private func framing(forYaw yaw: Double, person: Int) -> Framing {
        let key = Int((yaw * 180 / .pi).rounded())
        if let cached = framingCache[key] { return cached }

        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude

        // A sample is enough, and keeps this cheap on the main thread.
        let track = person < people.count ? people[person] : []
        let stride = max(1, track.count / 60)
        var sampled = 0
        for index in Swift.stride(from: 0, to: track.count, by: stride) {
            guard let joints = track[index] else { continue }
            let hip = (joints[J.leftHip] + joints[J.rightHip]) / 2
            let cosY = cos(yaw), sinY = sin(yaw)
            for index in drawnJoints {
                let j = joints[index]
                let dx = j.x - hip.x, dz = j.z - hip.z
                let x = cosY * dx + sinY * dz
                let z = -sinY * dx + cosY * dz
                let depth = max(hip.z + z, 0.35)
                let u = x / depth, v = (j.y - hip.y) / depth
                minX = min(minX, u); maxX = max(maxX, u)
                minY = min(minY, v); maxY = max(maxY, v)
            }
            sampled += 1
        }

        let framing: Framing
        if sampled == 0 || maxY <= minY {
            framing = Framing(scale: 1, offsetX: 0.5, offsetY: 0.5)
        } else {
            // Fill most of the height, leaving room above the head and under the
            // feet so the ghost never looks cropped.
            let scale = 0.82 / (maxY - minY)
            let centreX = (minX + maxX) / 2
            framing = Framing(scale: scale,
                              offsetX: 0.5 - centreX * scale,
                              offsetY: 0.90 - maxY * scale)
        }
        framingCache[key] = framing
        return framing
    }

    /// The joints worth drawing: body, hands as single points, feet. Fingers and
    /// face detail are in the data and stay out of the picture.
    private let drawnJoints: [Int] = [
        J.nose, J.neck,
        J.leftShoulder, J.rightShoulder, J.leftElbow, J.rightElbow, J.leftWrist, J.rightWrist,
        J.leftHip, J.rightHip, J.leftKnee, J.rightKnee, J.leftAnkle, J.rightAnkle,
        J.leftHeel, J.leftBigToe, J.rightHeel, J.rightBigToe,
    ]
}
