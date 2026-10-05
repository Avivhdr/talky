import Foundation

/// A named prompt that transforms text. Called TextPipe because Foundation already has `Pipe`.
public struct TextPipe: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var prompt: String

    public init(id: String = UUID().uuidString, name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}

public struct PipesFile: Codable, Equatable {
    /// Pipe applied to dictation unless another one is picked in the pill. nil means raw transcript.
    public var defaultPipe: String?
    public var pipes: [TextPipe]
}

public enum DefaultPipes {
    public static let cleanPrompt = """
    Clean up this dictated text.
    - Remove filler words (um, uh, er, like, you know, I mean, sort of) and false starts or repeated words.
    - When the speaker corrects themselves ("at 3, no, at 4"), keep only the correction.
    - Fix punctuation and obvious transcription mistakes.
    - Keep the speaker's own words, meaning and tone. Don't rephrase, summarize or add anything.
    - Casing: use normal sentence case for full sentences. For a short fragment of a few words, keep it lowercase with no trailing period, the way people type in chat.
    """

    public static let all: [TextPipe] = [
        TextPipe(id: "clean", name: "Clean", prompt: cleanPrompt),
        TextPipe(id: "formal", name: "Formal", prompt: """
        Rewrite the text as clear, professional prose suitable for a work email or document. \
        Fix grammar and remove filler. Keep roughly the same length and every fact the speaker gave. \
        Don't add a greeting or sign-off unless the text already has one.
        """),
        TextPipe(id: "bullets", name: "Bullets", prompt: """
        Turn the text into a concise markdown bullet list, one idea per bullet. \
        Remove filler and repetition. Keep the speaker's terminology.
        """),
    ]

    public static var file: PipesFile { PipesFile(defaultPipe: "clean", pipes: all) }
}

@MainActor
public final class PipeStore: ObservableObject {
    @Published public var pipes: [TextPipe] = [] {
        didSet { if pipes != oldValue && !loading { save() } }
    }
    @Published public var defaultPipeId: String? {
        didSet { if defaultPipeId != oldValue && !loading { save() } }
    }
    @Published public private(set) var loadError: String?
    private var loading = false

    public init() { load() }

    public var defaultPipe: TextPipe? { pipes.first { $0.id == defaultPipeId } }

    public func pipe(id: String?) -> TextPipe? {
        guard let id else { return nil }
        return pipes.first { $0.id == id }
    }

    public func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: Paths.pipesFile) else {
            let f = DefaultPipes.file
            pipes = f.pipes
            defaultPipeId = f.defaultPipe
            loading = false
            save()
            return
        }
        do {
            let f = try JSONDecoder().decode(PipesFile.self, from: data)
            if f.pipes != pipes { pipes = f.pipes }
            if f.defaultPipe != defaultPipeId { defaultPipeId = f.defaultPipe }
            loadError = nil
        } catch {
            loadError = "pipes.json: \(error.localizedDescription)"
        }
    }

    public func save() {
        Paths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(PipesFile(defaultPipe: defaultPipeId, pipes: pipes)) {
            try? data.write(to: Paths.pipesFile, options: .atomic)
        }
    }

    @discardableResult
    public func add() -> TextPipe {
        let p = TextPipe(name: "New pipe", prompt: "Describe how to transform the text.")
        pipes.append(p)
        return p
    }

    public func delete(id: String) {
        pipes.removeAll { $0.id == id }
        if defaultPipeId == id { defaultPipeId = pipes.first?.id }
    }

    public func move(id: String, by offset: Int) {
        guard let i = pipes.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard pipes.indices.contains(j) else { return }
        pipes.swapAt(i, j)
    }
}
