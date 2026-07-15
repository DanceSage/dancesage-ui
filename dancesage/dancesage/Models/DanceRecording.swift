import Foundation

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
    
    init(
        name: String,
        keypoints: [[[CGPoint]]],
        mode: Mode = .styling,
        fps: Double = 15,
        frameTimes: [Double] = [],
        beats: [Double] = [],
        bpm: Double = 0,
        hasVideo: Bool = false,
        cameraPosition: String? = nil
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
