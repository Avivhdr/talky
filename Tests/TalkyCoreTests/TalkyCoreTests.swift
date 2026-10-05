import XCTest
@testable import TalkyCore

final class HotkeyTests: XCTestCase {
    func testModifierNames() {
        XCTAssertEqual(HotkeySpec.parse("fn"), .modifier(keyCode: 63, mask: CGEventFlags.maskSecondaryFn.rawValue))
        XCTAssertEqual(HotkeySpec.parse("Right_Option"), .modifier(keyCode: 61, mask: 0x40))
    }

    func testChords() {
        XCTAssertEqual(HotkeySpec.parse("ctrl+opt+space"), .chord(keyCode: 49, modifiers: [.maskControl, .maskAlternate]))
        XCTAssertEqual(HotkeySpec.parse("cmd + shift + d"), .chord(keyCode: 2, modifiers: [.maskCommand, .maskShift]))
        XCTAssertEqual(HotkeySpec.parse("f13"), .chord(keyCode: 105, modifiers: []))
        XCTAssertNil(HotkeySpec.parse("hyper+q"))
        XCTAssertNil(HotkeySpec.parse("ctrl+nope"))
    }

    func testLabels() {
        XCTAssertEqual(HotkeySpec.label("fn"), "fn")
        XCTAssertEqual(HotkeySpec.label("ctrl+opt+space"), "⌃⌥Space")
    }
}

final class ConfigTests: XCTestCase {
    func testPartialConfigKeepsDefaults() throws {
        let json = #"{"hotkey": "right_command", "transcription": {"backend": "local"}}"#
        let c = try Config.decode(merging: Data(json.utf8))
        XCTAssertEqual(c.hotkey, "right_command")
        XCTAssertEqual(c.transcription.backend, "local")
        XCTAssertEqual(c.transcription.localModel, "small")
        XCTAssertEqual(c.handsFree.maxSeconds, 300)
        XCTAssertFalse(c.clipboard.restorePrevious)
    }

    func testRoundTrip() throws {
        var c = Config()
        c.clipboard.restorePrevious = true
        XCTAssertEqual(try Config.decode(merging: c.encoded()), c)
    }

    func testEnvParsing() {
        let env = Env.parse("""
        # comment
        export ANTHROPIC_API_KEY="sk-ant-123"
        GROQ_API_KEY=gsk_abc # trailing comment
        OPENAI_API_KEY='sk-x'
        EMPTY=
        """)
        XCTAssertEqual(env["ANTHROPIC_API_KEY"], "sk-ant-123")
        XCTAssertEqual(env["GROQ_API_KEY"], "gsk_abc")
        XCTAssertEqual(env["OPENAI_API_KEY"], "sk-x")
        XCTAssertEqual(env["EMPTY"], "")
    }
}

final class TextTests: XCTestCase {
    func testTranscriptCleanup() {
        XCTAssertEqual(TranscriptionService.cleanTranscript(" [BLANK_AUDIO] "), "")
        XCTAssertEqual(TranscriptionService.cleanTranscript("Hello (music) there\n world"), "Hello there world")
        XCTAssertEqual(TranscriptionService.cleanTranscript("keep (this) aside"), "keep (this) aside")
    }

    func testLLMOutputCleanup() {
        XCTAssertEqual(AnthropicClient.clean("<text>\nhi there\n</text>"), "hi there")
    }

    func testWAVHeader() {
        let d = WAV.data(samples: [0, 0.5, -0.5, 1])
        XCTAssertEqual(d.count, 44 + 8)
        XCTAssertEqual(String(decoding: d.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: d[8..<12], as: UTF8.self), "WAVE")
    }
}

final class EnvWriteTests: XCTestCase {
    func testSetKeepsOtherLinesAndRemovesKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("TALKY_CONFIG_DIR", dir.path, 1)
        defer { unsetenv("TALKY_CONFIG_DIR"); try? FileManager.default.removeItem(at: dir) }

        try "# keys\nexport GROQ_API_KEY=old\nOTHER=1\n".write(to: Paths.envFile, atomically: true, encoding: .utf8)
        Env.set("GROQ_API_KEY", " new ")
        Env.set("ANTHROPIC_API_KEY", "sk-ant")
        XCTAssertEqual(try String(contentsOf: Paths.envFile, encoding: .utf8),
                       "# keys\nGROQ_API_KEY=new\nOTHER=1\nANTHROPIC_API_KEY=sk-ant\n")

        Env.set("ANTHROPIC_API_KEY", "")
        XCTAssertNil(Env.value("ANTHROPIC_API_KEY"))
        XCTAssertEqual(Env.value("GROQ_API_KEY"), "new")
    }
}
