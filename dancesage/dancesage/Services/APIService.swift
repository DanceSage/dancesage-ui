import Foundation

class APIService {
    static let shared = APIService()
    
    // For physical device: use your Mac's local IP address
    // For simulator: use http://127.0.0.1:8000/api
    private let baseURL = "http://192.168.2.183:8000/api"
    
    // Send a single frame during live recording
    func uploadFrame(_ frame: [[CGPoint]], frameIndex: Int) async {
        let url = URL(string: "\(baseURL)/refine-pose")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
        let url = URL(string: "\(baseURL)/refine-pose")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        print("✅ Successfully uploaded keypoints: \(recording.name)")
    }
}
