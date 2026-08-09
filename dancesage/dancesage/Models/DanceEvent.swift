import Foundation

enum DanceStyle: String, Codable, CaseIterable, Identifiable {
    case salsa
    case bachata
    case latin

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct DanceEvent: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let styles: [DanceStyle]
    let eventType: String
    let startTime: Date
    let endTime: Date?
    let timezone: String
    let venueName: String
    let address: String?
    let city: String
    let summary: String
    let sourceURL: URL
    let sourceTitle: String
    let confidence: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, name, styles, timezone, address, city, summary, confidence, status
        case eventType = "event_type"
        case startTime = "start_time"
        case endTime = "end_time"
        case venueName = "venue_name"
        case sourceURL = "source_url"
        case sourceTitle = "source_title"
    }
}

struct EventSearchQuery: Codable {
    let city: String
    let region: String?
    let country: String?
    let date: String
    let styles: [DanceStyle]
}

struct EventSearchResponse: Decodable {
    let events: [DanceEvent]
    let checkedAt: Date
    let cached: Bool

    enum CodingKeys: String, CodingKey {
        case events, cached
        case checkedAt = "checked_at"
    }
}
