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
        let json = #"{"hotkey": "right_command", "transcription": {"language": "he"}}"#
        let c = try Config.decode(merging: Data(json.utf8))
        XCTAssertEqual(c.hotkey, "right_command")
        XCTAssertEqual(c.transcription.language, "he")
        XCTAssertEqual(c.transcription.model, "large-v3-turbo-q5_0")
        XCTAssertEqual(c.handsFree.maxSeconds, 300)
        XCTAssertFalse(c.clipboard.restorePrevious)
    }

    func testKeyCheckVerdicts() {
        XCTAssertEqual(KeyCheck.interpret(status: 200, body: Data()), .works)
        if case .rejected = KeyCheck.interpret(status: 401, body: Data()) {} else { XCTFail("401 rejects the key") }
        let forbidden = Data(#"{"type":"error","error":{"type":"permission_error","message":"Key disabled"}}"#.utf8)
        XCTAssertEqual(KeyCheck.interpret(status: 403, body: forbidden), .rejected("Anthropic didn't accept this key: Key disabled"))
        // Busy or down: the key may be good, so Talky keeps it.
        for status in [429, 500, 529] {
            if case .unreachable = KeyCheck.interpret(status: status, body: Data()) {} else { XCTFail("\(status) is not a verdict on the key") }
        }
    }

    func testModelFileLocation() {
        XCTAssertEqual(SpeechModel.url(for: "small").lastPathComponent, "ggml-small.bin")
        XCTAssertEqual(SpeechModel.url(for: "/tmp/m.bin").path, "/tmp/m.bin")
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
        PLAIN=abc # trailing comment
        SINGLE='sk-x'
        EMPTY=
        """)
        XCTAssertEqual(env["ANTHROPIC_API_KEY"], "sk-ant-123")
        XCTAssertEqual(env["PLAIN"], "abc")
        XCTAssertEqual(env["SINGLE"], "sk-x")
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
}

final class EnvWriteTests: XCTestCase {
    func testSetKeepsOtherLinesAndRemovesKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("TALKY_CONFIG_DIR", dir.path, 1)
        defer { unsetenv("TALKY_CONFIG_DIR"); try? FileManager.default.removeItem(at: dir) }

        try "# keys\nexport FIRST_KEY=old\nOTHER=1\n".write(to: Paths.envFile, atomically: true, encoding: .utf8)
        Env.set("FIRST_KEY", " new ")
        Env.set("ANTHROPIC_API_KEY", "sk-ant")
        XCTAssertEqual(try String(contentsOf: Paths.envFile, encoding: .utf8),
                       "# keys\nFIRST_KEY=new\nOTHER=1\nANTHROPIC_API_KEY=sk-ant\n")

        Env.set("ANTHROPIC_API_KEY", "")
        XCTAssertNil(Env.value("ANTHROPIC_API_KEY"))
        XCTAssertEqual(Env.value("FIRST_KEY"), "new")
    }
}
