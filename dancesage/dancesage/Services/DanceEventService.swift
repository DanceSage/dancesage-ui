import Foundation

enum DanceEventServiceError: LocalizedError {
    case invalidConfiguration
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Dance discovery is not configured yet."
        case .server(let message):
            return message
        case .invalidResponse:
            return "DanceSage could not read the event results. Please try again."
        }
    }
}

struct DanceEventService {
    private let session: URLSession
    private let baseURL: URL?

    init(session: URLSession = .shared, baseURL: URL? = DanceEventService.configuredBaseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func search(_ query: EventSearchQuery) async throws -> EventSearchResponse {
        guard let baseURL else { throw DanceEventServiceError.invalidConfiguration }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/events/search"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 70
        request.httpBody = try JSONEncoder().encode(query)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DanceEventServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIError.self, from: data).detail)
            throw DanceEventServiceError.server(detail ?? "Event search is temporarily unavailable.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter.withFractional.date(from: value)
                ?? ISO8601DateFormatter.standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid ISO 8601 date"
            )
        }
        return try decoder.decode(EventSearchResponse.self, from: data)
    }

    private struct APIError: Decodable { let detail: String }

    private static var configuredBaseURL: URL? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "DanceSageAPIBaseURL") as? String,
           !configured.isEmpty,
           !configured.hasPrefix("$(") {
            return URL(string: configured)
        }
#if DEBUG
        return URL(string: "http://127.0.0.1:8000")
#else
        return nil
#endif
    }
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter
    }()

    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return formatter
    }()
}
