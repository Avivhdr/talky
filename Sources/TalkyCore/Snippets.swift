import AppKit
import AVFoundation
import Foundation
import SwiftUI

/// One dictation Talky kept. The recording is a wav file beside this record.
/// `piped` is nil when no pipe ran, or when the pipe did not finish.
struct DictationSnippet: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var kind: Kind
    /// What Whisper heard.
    var original: String
    /// The pipe the user had selected. Set even when that pipe did not finish.
    var pipeName: String?
    /// What the pipe wrote, or what a spoken instruction produced.
    var piped: String?
    /// Length of the recording in seconds, once the wav file is written.
    var duration: TimeInterval?

    enum Kind: String, Codable, Equatable, Sendable {
        case dictation
        case instruction
    }
}

/// 16 kHz mono 16-bit wav, the same rate Whisper hears.
enum WavFile {
    static let sampleRate: UInt32 = 16_000

    static func write(samples: [Float], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ints = [Int16](repeating: 0, count: samples.count)
        for (i, sample) in samples.enumerated() {
            let clamped = max(-1 as Float, min(1, sample))
            ints[i] = Int16(clamping: Int((clamped * 32_767).rounded()))
        }
        let pcm = ints.withUnsafeBufferPointer { Data(buffer: $0) }
        var data = Data(capacity: 44 + pcm.count)
        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func append16(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func append32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        let dataBytes = UInt32(pcm.count)
        append("RIFF")
        append32(36 + dataBytes)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        append("data")
        append32(dataBytes)
        data.append(pcm)
        try data.write(to: url, options: .atomic)
    }
}

/// The dictation history in ~/.config/talky/snippets.json, newest first.
@MainActor
public final class SnippetStore: ObservableObject {
    static let limit = 200

    @Published private(set) var snippets: [DictationSnippet] = [] {
        didSet { if snippets != oldValue && !loading { save() } }
    }
    @Published private(set) var loadError: String?
    private var loading = false
    private var audioWrites: [UUID: Task<Void, Never>] = [:]
    let fileURL: URL
    let audioDirectory: URL

    init(fileURL: URL? = nil, audioDirectory: URL? = nil) {
        self.fileURL = fileURL ?? Paths.snippetsFile
        self.audioDirectory = audioDirectory ?? Paths.snippetsDirectory
        load()
    }

    /// Nil when the transcript is blank, so a miss is not stored.
    static func make(kind: DictationSnippet.Kind, original: String, pipeName: String?, piped: String?,
                     duration: TimeInterval? = nil, createdAt: Date = Date(), id: UUID = UUID()) -> DictationSnippet? {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        let pipeName = pipeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let piped = piped?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamped = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        return DictationSnippet(
            id: id, createdAt: stamped, kind: kind, original: original,
            pipeName: (pipeName?.isEmpty == false) ? pipeName : nil,
            piped: (piped?.isEmpty == false) ? piped : nil,
            duration: duration
        )
    }

    static func kept(_ existing: [DictationSnippet], adding snippet: DictationSnippet, limit: Int) -> (snippets: [DictationSnippet], removed: [UUID]) {
        var next = existing
        next.removeAll { $0.id == snippet.id }
        next.insert(snippet, at: 0)
        guard next.count > limit else { return (next, []) }
        let removed = next.suffix(next.count - limit).map(\.id)
        return (Array(next.prefix(limit)), removed)
    }

    /// Keeps the text immediately. The wav is written after, so a long recording does not delay the paste.
    func record(kind: DictationSnippet.Kind, original: String, pipeName: String?, piped: String?, samples: [Float] = []) {
        guard let snippet = Self.make(kind: kind, original: original, pipeName: pipeName, piped: piped) else { return }
        commit(snippet)
        guard !samples.isEmpty else { return }
        let id = snippet.id
        let url = audioURL(for: id)
        let count = samples.count
        audioWrites[id] = Task { [samples] in
            let wrote = await Task.detached { (try? WavFile.write(samples: samples, to: url)) != nil }.value
            if Task.isCancelled {
                if wrote { try? FileManager.default.removeItem(at: url) }
                return
            }
            self.noteAudio(id: id, wrote: wrote, sampleCount: count)
            self.audioWrites[id] = nil
        }
    }

    func waitForAudioWrites() async {
        let tasks = Array(audioWrites.values)
        for task in tasks { await task.value }
    }

    func delete(id: UUID) {
        audioWrites[id]?.cancel()
        audioWrites[id] = nil
        snippets.removeAll { $0.id == id }
        removeAudio(id)
    }

    func clear() {
        for task in audioWrites.values { task.cancel() }
        audioWrites = [:]
        let ids = snippets.map(\.id)
        snippets = []
        for id in ids { removeAudio(id) }
    }

    func hasAudio(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: audioURL(for: id).path)
    }

    func audioURL(for id: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(id.uuidString).wav")
    }

    func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: fileURL) else {
            loadError = nil
            if !snippets.isEmpty { snippets = [] }
            sweepAudio()
            return
        }
        do {
            let file = try Self.decoder().decode(SnippetsFile.self, from: data)
            if file.snippets != snippets { snippets = file.snippets }
            loadError = nil
            sweepAudio()
        } catch {
            loadError = "snippets.json: \(error.localizedDescription)"
        }
    }

    private func commit(_ snippet: DictationSnippet) {
        let next = Self.kept(snippets, adding: snippet, limit: Self.limit)
        for id in next.removed { removeAudio(id) }
        snippets = next.snippets
    }

    private func noteAudio(id: UUID, wrote: Bool, sampleCount: Int) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else {
            if wrote { removeAudio(id) }
            return
        }
        guard wrote else { return }
        snippets[index].duration = Double(sampleCount) / Double(WavFile.sampleRate)
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try Self.encoder().encode(SnippetsFile(snippets: snippets)).write(to: fileURL, options: .atomic)
            loadError = nil
            sweepAudio()
        } catch {
            loadError = "Could not write snippets.json: \(error.localizedDescription)"
        }
    }

    private func removeAudio(_ id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(for: id))
    }

    private func sweepAudio() {
        let keep = Set(snippets.map { "\($0.id.uuidString).wav" })
        guard let files = try? FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "wav" && !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct SnippetsFile: Codable, Equatable {
    var snippets: [DictationSnippet]
}

// MARK: - Playback

@MainActor
final class SnippetPlayback: NSObject, ObservableObject {
    @Published private(set) var playingId: UUID?

    private var player: AVAudioPlayer?

    func toggle(id: UUID, url: URL) {
        if playingId == id {
            stop()
            return
        }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.play() else { return }
            self.player = player
            playingId = id
        } catch {
            self.player = nil
            playingId = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingId = nil
    }

    fileprivate func finished(_ player: AVAudioPlayer) {
        guard self.player === player else { return }
        self.player = nil
        playingId = nil
    }
}

extension SnippetPlayback: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finished(player)
        }
    }
}

// MARK: - Settings page

struct SnippetsTab: View {
    @ObservedObject var store: SnippetStore
    /// The hotkey that opens this page, or "" when that key is off.
    let openHotkey: String
    @StateObject private var playback = SnippetPlayback()
    @State private var copiedKey: String?
    @State private var confirmClear = false

    private var subtitle: String {
        let keep = "Each recording stays on this Mac."
        let copy = "Copy the text if the cursor was not in a text field."
        guard HotkeySpec.parse(openHotkey) != nil else { return "\(keep) \(copy)" }
        return "\(keep) Tap \(HotkeySpec.label(openHotkey)) to open this page. \(copy)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHero(title: "Saved dictations", subtitle: subtitle) {
                snippetPreview
            }
            if let err = store.loadError {
                Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            HStack {
                Text(store.snippets.isEmpty ? "Nothing saved yet" : "\(store.snippets.count) saved")
                    .font(.headline)
                Spacer()
                Button("Clear All…") { confirmClear = true }
                    .disabled(store.snippets.isEmpty)
            }
            ScrollView {
                if store.snippets.isEmpty {
                    Text("When you dictate, the recording and the text show up here. A pipe keeps what you said and what the pipe wrote.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(cardBackground)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.snippets) { snippet in
                            SnippetCard(snippet: snippet, store: store, playback: playback,
                                        copiedKey: copiedKey, onCopy: copy)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Text("Talky keeps the latest \(SnippetStore.limit). Recordings and text stay in ~/.config/talky. They do not leave this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(SettingsLayout.margin)
        .onDisappear {
            playback.stop()
        }
        .confirmationDialog("Delete every saved dictation?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All Saved Dictations", role: .destructive) {
                playback.stop()
                store.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Talky removes the recordings and the text from this Mac.")
        }
    }

    private var snippetPreview: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                previewCapsule("waveform", "What you said")
                previewCapsule(nil, "Pipe result")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .accessibilityHidden(true)
    }

    private func previewCapsule(_ symbol: String?, _ title: String) -> some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .talkyGlass(Capsule(), tint: Color.black.opacity(0.18))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    private func copy(_ text: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedKey = key
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if copiedKey == key { copiedKey = nil }
        }
    }
}

private struct SnippetCard: View {
    let snippet: DictationSnippet
    @ObservedObject var store: SnippetStore
    @ObservedObject var playback: SnippetPlayback
    let copiedKey: String?
    let onCopy: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(snippet.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let duration = snippet.duration {
                    Text(Self.clock(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Length \(Self.clock(duration))")
                }
                if snippet.kind == .instruction {
                    Text("Instruction")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer(minLength: 8)
                if store.hasAudio(snippet.id) {
                    Button {
                        playback.toggle(id: snippet.id, url: store.audioURL(for: snippet.id))
                    } label: {
                        Image(systemName: playback.playingId == snippet.id ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(playback.playingId == snippet.id ? "Stop" : "Play the recording")
                    .accessibilityLabel(playback.playingId == snippet.id ? "Stop playback" : "Play the recording")
                }
                Button {
                    if playback.playingId == snippet.id { playback.stop() }
                    store.delete(id: snippet.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this dictation")
                .accessibilityLabel("Delete this dictation")
            }
            textBlock(title: "You said", text: snippet.original, key: "\(snippet.id.uuidString)-original")
            if let piped = snippet.piped {
                textBlock(title: snippet.pipeName ?? "Talky typed", text: piped, key: "\(snippet.id.uuidString)-piped")
            } else if let name = snippet.pipeName {
                Text("\(name) did not finish. Talky kept what you said.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    private func textBlock(title: String, text: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(copiedKey == key ? "Copied" : "Copy") { onCopy(text, key) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel(copiedKey == key ? "Copied" : "Copy \(title)")
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
