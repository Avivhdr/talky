import Foundation

/// Asks Anthropic whether it accepts a key. A models request is enough: it fails on a bad key and costs nothing.
public enum KeyCheck {
    public enum Verdict: Equatable {
        case works
        /// Anthropic answered and refused the key. The text says why.
        case rejected(String)
        /// Talky couldn't get an answer, so the key may still be good. The text says why.
        case unreachable(String)
    }

    /// Turns an HTTP status and body into a verdict with a sentence the user can read.
    public static func interpret(status: Int, body: Data) -> Verdict {
        switch status {
        case 200:
            return .works
        case 401:
            return .rejected("Anthropic didn't accept this key. Check that you copied all of it.")
        case 408, 429, 500...:
            return .unreachable("Anthropic answered HTTP \(status)")
        default:
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty { return .rejected("Anthropic didn't accept this key: \(message)") }
            return .rejected("Anthropic didn't accept this key (HTTP \(status)).")
        }
    }

    public static func verify(_ key: String) async -> Verdict {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.timeoutInterval = 15
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return interpret(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}

/// The Anthropic key in the Settings and onboarding fields, and what Anthropic said about it.
/// Talky saves a key only after Anthropic accepts it, or when Talky can't reach Anthropic to check it.
/// An empty field removes the key.
@MainActor
final class AnthropicKeyEntry: ObservableObject {
    static let shared = AnthropicKeyEntry()

    enum Status: Equatable {
        case empty, untested, testing, works
        case rejected(String)
        case unreachable(String)
    }

    @Published var draft: String {
        didSet { if draft != oldValue { edited() } }
    }
    @Published private(set) var status: Status
    private var testID = 0
    private var onWorks: (() -> Void)?

    init() {
        let saved = AnthropicClient.apiKey ?? ""
        draft = saved
        status = saved.isEmpty ? .empty : .untested
    }

    var key: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canTest: Bool { !key.isEmpty && status != .testing }

    private func edited() {
        testID += 1 // An answer about the old text no longer counts.
        onWorks = nil
        if key.isEmpty {
            status = .empty
            save("")
        } else {
            status = .untested
        }
    }

    /// For a key nobody has tested yet: the saved key when a field appears, a typed key when the field loses focus.
    func testIfNeeded() {
        if status == .untested { test() }
    }

    /// Asks Anthropic about the key. `then` runs if Anthropic accepts it.
    /// During a test, a second call only adds its `then` to the test that runs.
    func test(then next: (() -> Void)? = nil) {
        guard !key.isEmpty else { return }
        if status == .testing {
            if let next { onWorks = next }
            return
        }
        let key = key
        testID += 1
        let id = testID
        onWorks = next
        status = .testing
        Task {
            let verdict = await KeyCheck.verify(key)
            guard id == testID else { return }
            let next = onWorks
            onWorks = nil
            switch verdict {
            case .works:
                save(key)
                status = .works
                next?()
            case .rejected(let message):
                status = .rejected(message)
            case .unreachable(let reason):
                save(key)
                status = .unreachable(reason)
            }
        }
    }

    private func save(_ key: String) {
        guard key != (AnthropicClient.apiKey ?? "") else { return }
        Env.set("ANTHROPIC_API_KEY", key)
        NotificationCenter.default.post(name: .talkyKeysChanged, object: nil)
    }
}
