import Foundation

/// A joint in metres, hip-centred, with perspective removed.
///
/// MediaPipe returns this beside the flat image landmarks every frame. It is the
/// one worth keeping: image coordinates change as a dancer steps toward the
/// camera — they get bigger rather than nearer — so limb lengths wander frame to
/// frame and the wobble reads as a bad detector.
struct PosePoint3D: Codable, Equatable {
    let x: Float
    let y: Float
    let z: Float
}

struct DanceRecording: Codable, Identifiable {
    enum Mode: String, Codable {
        case styling
        case partner
    }

    let id: String
    let name: String
    let keypoints: [[[CGPoint]]]
    let timestamp: Date
    let frameCount: Int
    let mode: Mode?
    let fps: Double?
    let frameTimes: [Double]?
    let beats: [Double]?
    let bpm: Double?
    let hasVideo: Bool?
    let cameraPosition: String?
    /// The id this recording got when it was posted, if it ever was. Optional so
    /// recordings saved before posting existed still decode — and so the profile
    /// can show one card per dance rather than a local copy beside its own post.
    var postedVideoID: Int?
    /// `[frame][person][joint]` in metres. Optional so recordings made while this
    /// was switched off still decode.
    let worldKeypoints: [[[PosePoint3D]]]?
    
    init(
        name: String,
        keypoints: [[[CGPoint]]],
        mode: Mode = .styling,
        fps: Double = 15,
        frameTimes: [Double] = [],
        beats: [Double] = [],
        bpm: Double = 0,
        hasVideo: Bool = false,
        cameraPosition: String? = nil,
        worldKeypoints: [[[PosePoint3D]]] = []
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.keypoints = keypoints
        self.timestamp = Date()
        self.frameCount = keypoints.count
        self.mode = mode
        self.fps = fps
        self.frameTimes = frameTimes.count == keypoints.count ? frameTimes : nil
        self.beats = beats.isEmpty ? nil : beats
        self.bpm = bpm > 0 ? bpm : nil
        self.hasVideo = hasVideo
        self.cameraPosition = cameraPosition
        // Only kept when it lines up with the 2D frames; a partial track would be
        // worse than none, because everything downstream would trust it.
        self.worldKeypoints = worldKeypoints.count == keypoints.count ? worldKeypoints : nil
    }

    var effectiveFPS: Double { max(fps ?? 15, 1) }
    var effectiveFrameTimes: [Double] {
        if let frameTimes, frameTimes.count == keypoints.count { return frameTimes }
        return keypoints.indices.map { Double($0) / effectiveFPS }
    }

    var videoFilename: String { "\(id).mov" }
}

// Make CGPoint Codable
extension CGPoint: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        self.init(x: x, y: y)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}
