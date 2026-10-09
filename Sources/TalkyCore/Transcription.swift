import Foundation

public enum Backend: Equatable {
    case local
    case groq(key: String)
    case openai(key: String)

    public var label: String {
        switch self {
        case .local: return "Local whisper.cpp"
        case .groq: return "Groq Whisper"
        case .openai: return "OpenAI Whisper"
        }
    }
}

public final class TranscriptionService: @unchecked Sendable {
    public let local = LocalWhisper()

    public init() {}

    /// This version always hears on the Mac. A key is only for the later cleanup step.
    public static func plan(_ c: Config.Transcription) throws -> Backend {
        _ = c
        return .local
    }

    /// Starts whisper-server ahead of time when local transcription is the plan.
    public func prewarm(_ c: Config.Transcription) {
        guard (try? Self.plan(c)) == .local, c.useWhisperServer else {
            Task { await local.stopServer() }
            return
        }
        Task { _ = await local.ensureServer(c) }
    }

    public func transcribe(wav: URL, config c: Config.Transcription) async throws -> String {
        let backend = try Self.plan(c)
        let text: String
        switch backend {
        case .local:
            text = try await local.transcribe(wav: wav, config: c)
        case .groq(let key), .openai(let key):
            let isGroq = { if case .groq = backend { return true } else { return false } }()
            let api = CloudWhisper(
                endpoint: URL(string: isGroq
                    ? "https://api.groq.com/openai/v1/audio/transcriptions"
                    : "https://api.openai.com/v1/audio/transcriptions")!,
                apiKey: key,
                model: isGroq ? c.groqModel : c.openaiModel)
            do {
                text = try await api.transcribe(wav: wav, language: c.language, prompt: c.vocabulary)
            } catch {
                guard !Task.isCancelled, c.fallbackToLocal, local.modelURL(c) != nil else { throw error }
                text = try await local.transcribe(wav: wav, config: c)
            }
        }
        return Self.cleanTranscript(text)
    }

    /// Drops Whisper's non-speech annotations like [BLANK_AUDIO] or (music).
    public static func cleanTranscript(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\[[A-Za-z _]+\]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(
            of: #"\((?:music|silence|applause|laughs?|laughter|inaudible|blank_audio|noise|coughs?)\)"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Cloud (OpenAI-compatible /audio/transcriptions)

struct CloudWhisper {
    let endpoint: URL
    let apiKey: String
    let model: String

    func transcribe(wav: URL, language: String, prompt: String) async throws -> String {
        var form = MultipartForm()
        form.addField("model", model)
        form.addField("response_format", "json")
        form.addField("temperature", "0")
        if language.lowercased() != "auto", !language.isEmpty { form.addField("language", language) }
        if !prompt.isEmpty { form.addField("prompt", prompt) }
        form.addFile("file", filename: "audio.wav", mime: "audio/wav", data: try Data(contentsOf: wav))

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.upload(for: req, from: form.finish())
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw TalkyError("Transcription API \(status): \(msg)")
        }
        return json["text"] as? String ?? ""
    }
}

struct MultipartForm {
    let boundary = "talky-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }

    mutating func addFile(_ name: String, filename: String, mime: String, data: Data) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    func finish() -> Data {
        var d = body
        d.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return d
    }
}

// MARK: - Model file

public enum WhisperModel {
    public static let setupName = "small"

    public static func file(named name: String) -> URL {
        Paths.modelsDir.appendingPathComponent("ggml-\(name).bin")
    }

    public static func isInstalled(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: file(named: name).path)
    }

    /// Downloads ggml-\(name).bin into the Talky models folder. `onProgress` receives
    /// nil when the server does not say the size, otherwise a fraction from 0 to 1.
    public static func download(_ name: String, onProgress: @escaping @Sendable (Double?) -> Void) async throws {
        if isInstalled(name) {
            onProgress(1)
            return
        }
        guard let remote = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin") else {
            throw TalkyError("Unknown model address")
        }
        Paths.ensure()
        let box = ModelDownload(dest: file(named: name), onProgress: onProgress)
        try await withTaskCancellationHandler {
            try await box.run(remote)
        } onCancel: {
            box.cancel()
        }
        onProgress(1)
    }
}

private final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let dest: URL
    let onProgress: @Sendable (Double?) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var storedError: Error?
    private let lock = NSLock()

    init(dest: URL, onProgress: @escaping @Sendable (Double?) -> Void) {
        self.dest = dest
        self.onProgress = onProgress
    }

    func run(_ url: URL) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock()
            continuation = cont
            lock.unlock()
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
        session.finishTasksAndInvalidate()
    }

    func cancel() { task?.cancel() }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        } else {
            onProgress(nil)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            storedError = TalkyError("Model download failed (HTTP \(status))")
            return
        }
        do {
            Paths.ensure()
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: location, to: dest)
        } catch {
            storedError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        if let error {
            cont?.resume(throwing: error)
        } else if let storedError {
            cont?.resume(throwing: storedError)
        } else {
            cont?.resume()
        }
    }
}

// MARK: - Local whisper.cpp

/// Runs whisper.cpp as a subprocess. Prefers a long-lived whisper-server (model stays in memory,
/// so a transcription costs only inference time) and falls back to one-shot whisper-cli.
public actor LocalWhisper {
    private var server: Process?
    private var serverPort = 0
    private var serverModel: URL?
    private var serverStarting: Task<Bool, Never>?

    public init() {}

    public nonisolated func modelURL(_ c: Config.Transcription) -> URL? {
        let name = c.localModel
        let url: URL
        if name.contains("/") {
            url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath)
        } else {
            url = Paths.modelsDir.appendingPathComponent("ggml-\(name).bin")
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public nonisolated static func findBinary(_ name: String, override: String?) -> String? {
        var candidates: [String] = []
        if let override, !override.isEmpty { candidates.append((override as NSString).expandingTildeInPath) }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/whisper/\(name)").path
        candidates.append(bundled)
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func transcribe(wav: URL, config c: Config.Transcription) async throws -> String {
        guard let model = modelURL(c) else {
            throw TalkyError("The speech model is not on this Mac yet.")
        }
        if c.useWhisperServer, await ensureServer(c) {
            do {
                return try await viaServer(wav: wav, c: c)
            } catch {
                if Task.isCancelled { throw error }
                stopServer()   // fall through to the CLI and restart the server next time
            }
        }
        return try await viaCLI(wav: wav, model: model, c: c)
    }

    public func ensureServer(_ c: Config.Transcription) async -> Bool {
        guard let model = modelURL(c),
              let bin = Self.findBinary("whisper-server", override: c.whisperServerPath) else { return false }
        if let server, server.isRunning, serverModel == model { return true }
        if let serverStarting { return await serverStarting.value }
        stopServer()

        let task = Task<Bool, Never> { await self.launchServer(bin: bin, model: model) }
        serverStarting = task
        let ok = await task.value
        serverStarting = nil
        return ok
    }

    private func launchServer(bin: String, model: URL) async -> Bool {
        let port = Self.freePort()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-m", model.path, "--host", "127.0.0.1", "--port", String(port),
                       "-t", String(max(4, ProcessInfo.processInfo.activeProcessorCount / 2))]
        let log = Paths.logsDir.appendingPathComponent("whisper-server.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: log)
        p.standardOutput = handle ?? FileHandle.nullDevice
        p.standardError = handle ?? FileHandle.nullDevice
        do { try p.run() } catch { return false }
        server = p
        serverPort = port
        serverModel = model

        // Model load takes a second or two; wait until the HTTP port answers.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            guard p.isRunning else { break }
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!)
            req.timeoutInterval = 1
            if let (_, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse) != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        stopServer()
        return false
    }

    public func stopServer() {
        if let server, server.isRunning { server.terminate() }
        server = nil
        serverModel = nil
    }

    private func viaServer(wav: URL, c: Config.Transcription) async throws -> String {
        var form = MultipartForm()
        form.addField("response_format", "json")
        form.addField("temperature", "0.0")
        form.addField("language", c.language.isEmpty ? "auto" : c.language)
        if !c.vocabulary.isEmpty { form.addField("prompt", c.vocabulary) }
        form.addFile("file", filename: "audio.wav", mime: "audio/wav", data: try Data(contentsOf: wav))
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(serverPort)/inference")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.upload(for: req, from: form.finish())
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TalkyError("whisper-server returned an error")
        }
        return json["text"] as? String ?? ""
    }

    private func viaCLI(wav: URL, model: URL, c: Config.Transcription) async throws -> String {
        guard let bin = Self.findBinary("whisper-cli", override: c.whisperCliPath) else {
            throw TalkyError("Talky is missing its speech engine. Reinstall Talky.")
        }
        let outBase = wav.deletingPathExtension().path
        var args = ["-m", model.path, "-f", wav.path, "-nt", "-np", "-otxt", "-of", outBase,
                    "-l", c.language.isEmpty ? "auto" : c.language,
                    "-t", String(max(4, ProcessInfo.processInfo.activeProcessorCount / 2))]
        if !c.vocabulary.isEmpty { args += ["--prompt", c.vocabulary] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
                do { try p.run() } catch { cont.resume(throwing: error) }
            }
        } onCancel: {
            p.terminate()
        }
        try Task.checkCancellation()
        let txt = URL(fileURLWithPath: outBase + ".txt")
        defer { try? FileManager.default.removeItem(at: txt) }
        guard status == 0, let text = try? String(contentsOf: txt, encoding: .utf8) else {
            throw TalkyError("whisper-cli failed (exit \(status))")
        }
        return text
    }

    static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        let port = Int(UInt16(bigEndian: addr.sin_port))
        return port > 0 ? port : 8178
    }
}
