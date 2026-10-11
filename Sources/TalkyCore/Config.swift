import Foundation

public enum Paths {
    public static var configDir: URL {
        if let custom = ProcessInfo.processInfo.environment["TALKY_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/talky")
    }

    public static var configFile: URL { configDir.appendingPathComponent("config.json") }
    public static var pipesFile: URL { configDir.appendingPathComponent("pipes.json") }
    public static var envFile: URL { configDir.appendingPathComponent(".env") }
    public static var modelsDir: URL { configDir.appendingPathComponent("models") }
    public static var logsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Talky")
    }

    public static func ensure() {
        let fm = FileManager.default
        for dir in [configDir, modelsDir, logsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Reads KEY=VALUE pairs from ~/.config/talky/.env. Values from the file win over the
/// process environment. Read on every lookup so edits apply without a restart.
public enum Env {
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            } else if let hash = value.range(of: " #") {
                value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            if !key.isEmpty { out[key] = value }
        }
        return out
    }

    public static func value(_ key: String) -> String? {
        let file = (try? String(contentsOf: Paths.envFile, encoding: .utf8)).map(parse) ?? [:]
        let v = file[key] ?? ProcessInfo.processInfo.environment[key]
        guard let v, !v.isEmpty else { return nil }
        return v
    }

    /// Writes or removes one key in the .env file and keeps every other line as it was.
    /// Writes through a symlink (install.sh may link the file to a repo checkout).
    public static func set(_ key: String, _ value: String?) {
        Paths.ensure()
        let url = Paths.envFile.resolvingSymlinksInPath()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entry = "\(key)=\(trimmed)"
        let matches: (String) -> Bool = { line in
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("export ") { l = String(l.dropFirst(7)) }
            return l.hasPrefix(key + "=") || l.hasPrefix(key + " =")
        }
        if let i = lines.firstIndex(where: matches) {
            lines[i] = entry
        } else if !trimmed.isEmpty {
            lines.append(entry)
        }
        let out = lines.joined(separator: "\n") + "\n"
        FileManager.default.createFile(atPath: url.path, contents: Data(out.utf8),
                                       attributes: [.posixPermissions: 0o600])
    }
}

public struct Config: Codable, Equatable {
    public var enabled = true
    /// Hold to talk, double-tap for hands-free. See HotkeySpec for the accepted names.
    public var hotkey = "fn"
    /// Tap with text selected to open the transform picker.
    public var transformHotkey = "right_option"
    public var showPipesInPill = true
    public var transcription = Transcription()
    public var llm = LLM()
    public var clipboard = Clipboard()
    public var handsFree = HandsFree()

    public struct Transcription: Codable, Equatable, Sendable {
        /// A whisper.cpp model name (large-v3-turbo-q5_0, small, medium, ...), downloaded into
        /// ~/.config/talky/models, or an absolute path to a ggml model file.
        public var model = "large-v3-turbo-q5_0"
        /// Whisper language code ("en", "he", ...) or "auto".
        public var language = "auto"
        /// Names and jargon passed to Whisper as a prompt to bias spelling.
        public var vocabulary = ""
    }

    public struct LLM: Codable, Equatable {
        public var enabled = true
        /// Haiku is the default because cleanup runs on every dictation: about 0.7s against 3s for Opus.
        public var model = "claude-haiku-4-5-20251001"
        /// low | medium | high. Ignored for models that don't take an effort setting.
        public var effort = "low"
        public var timeoutSeconds = 30.0
    }

    public struct Clipboard: Codable, Equatable {
        /// false: the result stays on the clipboard. true: put back what was there before.
        public var restorePrevious = false
        public var restoreDelayMs = 500.0
    }

    public struct HandsFree: Codable, Equatable {
        public var maxSeconds = 300.0
        public var doubleTapWindowMs = 400.0
    }

    public init() {}

    /// Decodes a config file, filling every missing key with its default.
    public static func decode(merging data: Data) throws -> Config {
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Config())) as? [String: Any] ?? [:]
        guard let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Talky", code: 1, userInfo: [NSLocalizedDescriptionKey: "config.json must be a JSON object"])
        }
        let merged = deepMerge(defaults, user)
        return try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = out[k] as? [String: Any], let o = v as? [String: Any] {
                out[k] = deepMerge(b, o)
            } else {
                out[k] = v
            }
        }
        return out
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(self)
    }
}

@MainActor
public final class ConfigStore: ObservableObject {
    @Published public var config: Config {
        didSet { if config != oldValue && !loading { save() } }
    }
    @Published public private(set) var loadError: String?
    private var loading = false

    public init() {
        config = Config()
        load()
    }

    public func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: Paths.configFile) else {
            loadError = nil
            save()
            return
        }
        do {
            let c = try Config.decode(merging: data)
            if c != config { config = c }
            loadError = nil
            // Rewrite the file when it differs from what Talky would write: this drops settings that
            // older versions wrote and adds new settings with their defaults.
            if let canonical = try? c.encoded(), canonical != data { save() }
        } catch {
            // Keep the last good config so a typo in the file doesn't kill the hotkey.
            loadError = "config.json: \(error.localizedDescription)"
        }
    }

    public func save() {
        Paths.ensure()
        do {
            try config.encoded().write(to: Paths.configFile, options: .atomic)
        } catch {
            loadError = "Could not write config.json: \(error.localizedDescription)"
        }
    }
}

/// Watches the config directory so hand edits to config.json / pipes.json apply live.
/// Editors save by renaming, so watching the directory is more reliable than the file.
public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let item = DispatchWorkItem(block: onChange)
            self?.pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}
