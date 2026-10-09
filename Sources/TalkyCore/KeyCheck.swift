import Foundation

public enum KeyState: Equatable {
    case empty
    case checking
    case valid
    case invalid(String)
}

/// Asks Groq or Anthropic whether a key is accepted. A models request is enough:
/// it fails on a bad key and does not spend a transcription.
public enum KeyCheck {
    public enum Service {
        case groq
        case anthropic

        var endpoint: URL {
            switch self {
            case .groq: return URL(string: "https://api.groq.com/openai/v1/models")!
            case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
            }
        }
    }

    public struct Verdict: Equatable {
        public var ok: Bool
        public var message: String
    }

    /// Turns an HTTP status and body into a sentence the user can read.
    public static func interpret(status: Int, body: Data) -> Verdict {
        if status == 200 { return Verdict(ok: true, message: "Key works") }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let message = (error?["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let message, !message.isEmpty {
            return Verdict(ok: false, message: message)
        }
        return Verdict(ok: false, message: "The key was rejected (HTTP \(status))")
    }

    public static func verify(_ service: Service, key: String) async -> Verdict {
        var request = URLRequest(url: service.endpoint)
        request.timeoutInterval = 20
        request.httpMethod = "GET"
        switch service {
        case .groq:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return interpret(status: status, body: data)
        } catch {
            return Verdict(ok: false, message: error.localizedDescription)
        }
    }
}
