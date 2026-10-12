import Foundation
import whisper

/// Turns speech into text on this Mac with whisper.cpp, which ships inside Talky.
/// The model loads once and stays in memory, so a dictation costs only inference time.
public final class TranscriptionService: @unchecked Sendable {
    /// A whisper.cpp context is not thread safe. `context` and `contextModel` are only used on this queue.
    private let queue = DispatchQueue(label: "dev.talky.whisper", qos: .userInitiated)
    private var context: OpaquePointer?
    private var contextModel: URL?
    /// Set by unload: no model loads after it.
    private var isClosed = false

    public init() {
        // whisper.cpp logs every model load and decode to stderr.
        whisper_log_set({ _, _, _ in }, nil)
    }

    /// Loads the model ahead of the first dictation. Does nothing until the model is downloaded.
    public func prewarm(_ c: Config.Transcription) {
        queue.async { _ = try? self.loadContext(c) }
    }

    public func transcribe(samples: [Float], config c: Config.Transcription) async throws -> String {
        let abort = AbortFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                queue.async { cont.resume(with: Result { try self.run(samples, c, abort) }) }
            }
        } onCancel: {
            abort.set()
        }
    }

    /// Frees the model. Call it before the app exits: at exit whisper.cpp aborts the process when
    /// Metal memory it gave out is still in use. Waits for a transcription in progress, so cancel that first.
    public func unload() {
        queue.sync {
            isClosed = true
            if let context { whisper_free(context) }
            context = nil
            contextModel = nil
        }
    }

    private func loadContext(_ c: Config.Transcription) throws -> OpaquePointer {
        if isClosed { throw CancellationError() }
        let url = SpeechModel.url(for: c.model)
        if let context, contextModel == url { return context }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TalkyError("The speech model isn't downloaded yet. Download it in Talky Settings.")
        }
        if let context { whisper_free(context) }
        context = nil
        contextModel = nil
        guard let ctx = whisper_init_from_file_with_params(url.path, whisper_context_default_params()) else {
            throw TalkyError("Talky couldn't load the speech model. Download it again in Settings.")
        }
        context = ctx
        contextModel = url
        return ctx
    }

    private func run(_ samples: [Float], _ c: Config.Transcription, _ abort: AbortFlag) throws -> String {
        let ctx = try loadContext(c)
        var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        p.print_progress = false
        p.print_realtime = false
        p.print_timestamps = false
        p.print_special = false
        p.no_timestamps = true
        p.no_context = true
        p.n_threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount / 2))
        p.abort_callback = { data in
            guard let data else { return false }
            return Unmanaged<AbortFlag>.fromOpaque(data).takeUnretainedValue().isSet
        }
        p.abort_callback_user_data = Unmanaged.passUnretained(abort).toOpaque()

        let language = c.language.isEmpty ? "auto" : c.language
        let status = language.withCString { lang in
            c.vocabulary.withCString { vocabulary in
                p.language = lang
                p.initial_prompt = c.vocabulary.isEmpty ? nil : vocabulary
                return samples.withUnsafeBufferPointer { whisper_full(ctx, p, $0.baseAddress, Int32($0.count)) }
            }
        }
        if abort.isSet { throw CancellationError() }
        guard status == 0 else { throw TalkyError("Transcription failed (whisper.cpp error \(status))") }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let segment = whisper_full_get_segment_text(ctx, i) { text += String(cString: segment) }
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

/// Set from the cancel handler, read by whisper.cpp between decode steps.
private final class AbortFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

// MARK: - The model file

/// The Whisper model Talky needs for dictation, and its one-time download.
@MainActor
public final class SpeechModel: NSObject, ObservableObject {
    public static let shared = SpeechModel()

    public enum State: Equatable {
        case missing
        case downloading(received: Int64, total: Int64)
        case ready
        case failed(String)
    }

    @Published public private(set) var state = State.missing
    /// The model name from config.json: "large-v3-turbo-q5_0", "small" and so on, or a path to a ggml file.
    public private(set) var name = Config.Transcription().model
    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    /// Sizes for the label before a download starts. Other models show their size once it starts.
    static let knownSizes: [String: Int64] = ["large-v3-turbo-q5_0": 574_041_195, "small": 487_601_967]

    public nonisolated static func url(for name: String) -> URL {
        if name.contains("/") { return URL(fileURLWithPath: (name as NSString).expandingTildeInPath) }
        return Paths.modelsDir.appendingPathComponent("ggml-\(name).bin")
    }

    public var isReady: Bool { state == .ready }
    public var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }
    public var url: URL { Self.url(for: name) }
    /// "Whisper large-v3 turbo" for the default model; other names as they are.
    public var displayName: String {
        name == "large-v3-turbo-q5_0" ? "Whisper large-v3 turbo" : "Whisper \(name)"
    }
    public var expectedSize: Int64? {
        if case .downloading(_, let total) = state, total > 0 { return total }
        return Self.knownSizes[name]
    }

    /// Why dictation can't start yet, in words for the pill. Nil when the model is ready.
    public var blocker: String? {
        switch state {
        case .ready: return nil
        case .downloading(let received, let total):
            guard total > 0 else { return "Talky is still downloading its speech model" }
            return "Talky is still downloading its speech model (\(Int(Double(received) / Double(total) * 100))%)"
        case .missing, .failed: return "Talky needs its speech model first"
        }
    }

    public func use(_ name: String) {
        guard name != self.name else { return }
        cancel()
        self.name = name
        refresh()
    }

    public func refresh() {
        if case .downloading = state { return }
        state = FileManager.default.fileExists(atPath: url.path) ? .ready : .missing
    }

    public func download() {
        if case .downloading = state { return }
        guard !name.contains("/") else {
            state = .failed("No model file at \(name)")
            return
        }
        let source = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin")!
        state = .downloading(received: 0, total: Self.knownSizes[name] ?? 0)
        let task = session.downloadTask(with: source)
        self.task = task
        task.resume()
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if case .downloading = state { state = .missing }
    }

    fileprivate func finish(_ task: URLSessionDownloadTask, file: URL) {
        guard task == self.task else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            state = .failed("The download failed (HTTP \(status)).")
            return
        }
        do {
            Paths.ensure()
            let fm = FileManager.default
            try? fm.removeItem(at: url)
            try fm.moveItem(at: file, to: url)
            self.task = nil
            state = .ready
        } catch {
            state = .failed("Talky couldn't save the model: \(error.localizedDescription)")
        }
    }

    fileprivate func fail(_ task: URLSessionTask, _ error: Error) {
        guard task == self.task else { return }
        self.task = nil
        if (error as? URLError)?.code == .cancelled { return }
        state = .failed("The download stopped. Check your connection and try again.")
    }

    fileprivate func progress(_ task: URLSessionTask, received: Int64, total: Int64) {
        guard task == self.task else { return }
        state = .downloading(received: received, total: total > 0 ? total : (Self.knownSizes[name] ?? 0))
    }
}

// The session delivers on the main queue, so each callback can step into the main actor.
extension SpeechModel: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                       didFinishDownloadingTo location: URL) {
        // The file is deleted when this method returns, so it has to move now.
        MainActor.assumeIsolated { finish(downloadTask, file: location) }
    }

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                       didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                       totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated { progress(downloadTask, received: totalBytesWritten, total: totalBytesExpectedToWrite) }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        MainActor.assumeIsolated { fail(task, error) }
    }
}
