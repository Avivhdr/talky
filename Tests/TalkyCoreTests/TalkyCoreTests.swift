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
        XCTAssertEqual(HotkeySpec.keycaps("right_option"), ["right ⌥"])
        XCTAssertEqual(HotkeySpec.keycaps("cmd + shift + d"), ["⌘", "⇧", "D"])
    }
}

final class HotkeyCaptureTests: XCTestCase {
    // Key codes and the flag bits NSEvent sends with them.
    let rightOption: Int64 = 61, leftControl: Int64 = 59, leftOption: Int64 = 58, fn: Int64 = 63
    let rightOptionDown = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
    let controlOptionDown = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x01 | CGEventFlags.maskAlternate.rawValue | 0x20)

    func testLoneModifierTap() {
        var c = HotkeyCapture()
        XCTAssertNil(c.flagsChanged(keyCode: rightOption, flags: rightOptionDown))
        XCTAssertEqual(c.heldKeycaps, ["right ⌥"])
        XCTAssertEqual(c.flagsChanged(keyCode: rightOption, flags: []), .captured("right_option"))

        var f = HotkeyCapture()
        XCTAssertNil(f.flagsChanged(keyCode: fn, flags: .maskSecondaryFn))
        XCTAssertEqual(f.flagsChanged(keyCode: fn, flags: []), .captured("fn"))
    }

    func testChord() {
        var c = HotkeyCapture()
        _ = c.flagsChanged(keyCode: leftControl, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x01))
        _ = c.flagsChanged(keyCode: leftOption, flags: controlOptionDown)
        XCTAssertEqual(c.heldKeycaps, ["⌃", "⌥"])
        guard case .captured(let name)? = c.keyDown(keyCode: 49, flags: controlOptionDown) else { return XCTFail("⌃⌥Space is a hotkey") }
        XCTAssertEqual(name, "ctrl+opt+space")
        XCTAssertEqual(HotkeySpec.parse(name), .chord(keyCode: 49, modifiers: [.maskControl, .maskAlternate]))
        // Letting go of the modifiers after the chord records nothing more.
        XCTAssertNil(c.flagsChanged(keyCode: leftOption, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x01)))
        XCTAssertNil(c.flagsChanged(keyCode: leftControl, flags: []))
    }

    func testTwoModifiersAloneRecordNothing() {
        var c = HotkeyCapture()
        _ = c.flagsChanged(keyCode: leftControl, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x01))
        _ = c.flagsChanged(keyCode: leftOption, flags: controlOptionDown)
        XCTAssertNil(c.flagsChanged(keyCode: leftOption, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x01)))
        XCTAssertNil(c.flagsChanged(keyCode: leftControl, flags: []))
    }

    func testKeysThatWouldStopTyping() {
        var c = HotkeyCapture()
        if case .rejected? = c.keyDown(keyCode: 0, flags: []) {} else { XCTFail("a plain A stops A from typing") }
        if case .rejected? = c.keyDown(keyCode: 0, flags: .maskShift) {} else { XCTFail("⇧A stops capital A from typing") }
        if case .rejected? = c.keyDown(keyCode: 123, flags: .maskControl) {} else { XCTFail("HotkeySpec has no name for ←") }
        XCTAssertEqual(c.keyDown(keyCode: 105, flags: []), .captured("f13"))
        XCTAssertEqual(c.keyDown(keyCode: 2, flags: [.maskCommand, .maskShift]), .captured("shift+cmd+d"))
        XCTAssertEqual(c.keyDown(keyCode: 36, flags: .maskControl), .captured("ctrl+return"))
    }

    func testEveryKeyNameParses() {
        for (code, name) in HotkeyCapture.keyNames {
            XCTAssertEqual(HotkeySpec.parse("ctrl+\(name)"), .chord(keyCode: code, modifiers: .maskControl), name)
        }
        for (code, name) in HotkeyCapture.modifierNames {
            guard case .modifier(let k, _)? = HotkeySpec.parse(name) else { return XCTFail(name) }
            XCTAssertEqual(k, code)
        }
    }

    func testTapHotkeyModifier() {
        var t = TapHotkey(spec: HotkeySpec.parse("right_command"))
        let down = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
        XCTAssertEqual(t.flagsChanged(code: 54, flags: down), false)
        XCTAssertEqual(t.flagsChanged(code: 54, flags: []), true, "a clean tap fires")

        XCTAssertEqual(t.flagsChanged(code: 54, flags: down), false)
        XCTAssertFalse(t.keyDown(code: 8, flags: down, isRepeat: false), "⌘C is not the hotkey")
        XCTAssertEqual(t.flagsChanged(code: 54, flags: []), false, "⌘C does not fire it")

        XCTAssertNil(t.flagsChanged(code: 61, flags: .maskAlternate), "another modifier is not the hotkey")
    }

    func testTapHotkeyChordFiresOnRelease() {
        var t = TapHotkey(spec: HotkeySpec.parse("ctrl+opt+h"))
        let mods: CGEventFlags = [.maskControl, .maskAlternate]
        XCTAssertTrue(t.keyDown(code: 4, flags: mods, isRepeat: false))
        XCTAssertTrue(t.keyDown(code: 4, flags: mods, isRepeat: true))
        XCTAssertEqual(t.keyUp(code: 4), true)
        XCTAssertEqual(t.keyUp(code: 4), false, "one press fires once")
        XCTAssertNil(t.keyUp(code: 5))
        XCTAssertFalse(t.keyDown(code: 4, flags: .maskControl, isRepeat: false), "⌃H alone is not the chord")
    }

    func testSameKeyUnderTwoNames() {
        XCTAssertTrue(HotkeyField.same("fn", "globe"))
        XCTAssertTrue(HotkeyField.same("cmd+shift+d", "shift+cmd+d"))
        XCTAssertFalse(HotkeyField.same("right_option", "left_option"))
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

    func testHandsFreeHotkeyDefault() throws {
        XCTAssertEqual(try Config.decode(merging: Data("{}".utf8)).handsFreeHotkey, "right_command")
        // An older file that already uses right ⌘ for another hotkey gets no hands-free hotkey.
        let clash = try Config.decode(merging: Data(#"{"transformHotkey": "right_command"}"#.utf8))
        XCTAssertEqual(clash.handsFreeHotkey, "")
        // A choice the user made stays.
        let off = try Config.decode(merging: Data(#"{"handsFreeHotkey": ""}"#.utf8))
        XCTAssertEqual(off.handsFreeHotkey, "")
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
