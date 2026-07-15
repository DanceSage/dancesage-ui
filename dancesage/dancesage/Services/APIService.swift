import Foundation
import FirebaseAuth

enum APIServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The DanceSage API address is not configured. The recording remains saved on this device."
        case .invalidResponse:
            return "The DanceSage API returned an invalid response."
        case let .server(statusCode, message):
            return "The DanceSage API returned HTTP \(statusCode): \(message)"
        }
    }
}

class APIService {
    static let shared = APIService()
    
    private var baseURL: URL? {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "DANCESAGE_API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configured,
              !configured.isEmpty,
              !configured.contains("$("),
              let url = URL(string: configured) else { return nil }
        return url
    }

    private func request(path: String) async throws -> URLRequest {
        guard let baseURL else { throw APIServiceError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let user = Auth.auth().currentUser,
           let token = try? await user.getIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
    
    // Send a single frame during live recording
    func uploadFrame(_ frame: [[CGPoint]], frameIndex: Int) async {
        // Convert single frame: people → points → [x, y]
        let frameArray: [[[Double]]] = frame.map { person in
            person.map { point in
                [Double(point.x), Double(point.y)]
            }
        }
        
        // Wrap in frames array: [[people → points → [x, y]]]
        let keypointsArray: [[[[Double]]]] = [frameArray]
        
        let payload: [String: Any] = [
            "name": "live_frame_\(frameIndex)",
            "keypoints": keypointsArray
        ]
        
        do {
            var request = try await request(path: "refine-pose")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                // Log every 15th frame to avoid spam
                if frameIndex % 15 == 0 {
                    print("📤 Sent frame \(frameIndex) to backend")
                }
            }
        } catch {
            print("⚠️ Frame \(frameIndex) upload failed: \(error.localizedDescription)")
        }
    }
    
    func uploadKeypoints(_ recording: DanceRecording) async throws {
        var request = try await request(path: "refine-pose")
        
        // Convert CGPoint to [x, y] arrays for JSON
        // Structure: frames → people → points → [x, y]
        let keypointsArray: [[[[Double]]]] = recording.keypoints.map { frame in
            frame.map { person in
                person.map { point in
                    [Double(point.x), Double(point.y)]
                }
            }
        }
        
        let payload: [String: Any] = [
            "name": recording.name,
            "keypoints": keypointsArray
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIServiceError.server(statusCode: httpResponse.statusCode, message: message)
        }
        
        print("✅ Successfully uploaded keypoints: \(recording.name)")
    }
}
