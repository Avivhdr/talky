import AppKit
import AVFoundation
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
        XCTAssertNil(t.keyUp(code: 4), "one press fires once")
        XCTAssertNil(t.keyUp(code: 5))
        XCTAssertFalse(t.keyDown(code: 4, flags: .maskControl, isRepeat: false), "⌃H alone is not the chord")
    }

    func testTapHotkeyPassesThePlainKeyUp() {
        var t = TapHotkey(spec: HotkeySpec.parse("ctrl+z"))
        XCTAssertFalse(t.keyDown(code: 6, flags: [], isRepeat: false))
        XCTAssertNil(t.keyUp(code: 6), "a plain Z's key-up reaches the app")
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

    func testSavedDictationsHotkeyDefault() throws {
        XCTAssertEqual(try Config.decode(merging: Data("{}".utf8)).savedDictationsHotkey, "right_control")
        // An older file that already uses right ⌃ for another hotkey gets no saved-dictations hotkey.
        let clash = try Config.decode(merging: Data(#"{"handsFreeHotkey": "right_control"}"#.utf8))
        XCTAssertEqual(clash.savedDictationsHotkey, "")
        XCTAssertEqual(clash.handsFreeHotkey, "right_control")
        let dictate = try Config.decode(merging: Data(#"{"hotkey": "right_control"}"#.utf8))
        XCTAssertEqual(dictate.savedDictationsHotkey, "")
        XCTAssertEqual(dictate.handsFreeHotkey, "right_command")
        // A choice the user made stays, including None and a key that matches another hotkey.
        let off = try Config.decode(merging: Data(#"{"savedDictationsHotkey": ""}"#.utf8))
        XCTAssertEqual(off.savedDictationsHotkey, "")
        let kept = try Config.decode(merging: Data(#"{"handsFreeHotkey":"right_control","savedDictationsHotkey":"right_control"}"#.utf8))
        XCTAssertEqual(kept.savedDictationsHotkey, "right_control")
        // The saved-dictations key can take the hands-free default when the hands-free key is absent.
        let taken = try Config.decode(merging: Data(#"{"savedDictationsHotkey": "right_command"}"#.utf8))
        XCTAssertEqual(taken.savedDictationsHotkey, "right_command")
        XCTAssertEqual(taken.handsFreeHotkey, "")
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

final class FittingTextHeightTests: XCTestCase {
    let font = NSFont.systemFont(ofSize: 13)
    let width: CGFloat = 460

    func height(_ text: String, width: CGFloat = 460) -> CGFloat {
        FittingTextHeight.height(text: text, width: width, font: font, inset: FittingTextHeight.inset)
    }

    func testEmptyFieldIsOneLine() {
        let empty = height("")
        let one = height("Rewrite this text.")
        XCTAssertEqual(empty, one, accuracy: 0.5)
        XCTAssertGreaterThan(empty, FittingTextHeight.inset * 2)
    }

    func testEachNewLineAddsOneLine() {
        let one = height("Hello")
        let two = height("Hello\nHello")
        let three = height("Hello\nHello\nHello")
        let step = two - one
        XCTAssertGreaterThan(step, 8)
        XCTAssertEqual(three - two, step, accuracy: 1)
    }

    func testNarrowWidthIsTallerThanWideWidth() {
        let paragraph = String(repeating: "word ", count: 40)
        let narrow = height(paragraph, width: 180)
        let wide = height(paragraph, width: 900)
        XCTAssertGreaterThan(narrow, wide)
    }
}

@MainActor
final class SnippetStoreTests: XCTestCase {
    func testBlankTranscriptIsNotStored() {
        XCTAssertNil(SnippetStore.make(kind: .dictation, original: " \n ", pipeName: "Clean", piped: "Hi"))
    }

    func testPipeNameStaysWhenThePipeDidNotFinish() {
        let snippet = SnippetStore.make(kind: .dictation, original: " um hi ", pipeName: " Formal ", piped: " \n")
        XCTAssertEqual(snippet?.original, "um hi")
        XCTAssertEqual(snippet?.pipeName, "Formal")
        XCTAssertNil(snippet?.piped)
    }

    func testPipeResultIsKeptBesideTheOriginal() {
        let snippet = SnippetStore.make(kind: .dictation, original: "um hi", pipeName: "Clean", piped: " Hi. ")
        XCTAssertEqual(snippet?.original, "um hi")
        XCTAssertEqual(snippet?.pipeName, "Clean")
        XCTAssertEqual(snippet?.piped, "Hi.")
    }

    func testInstructionKeepsWhatYouSaidAndWhatTalkyTyped() {
        let snippet = SnippetStore.make(kind: .instruction, original: "make this shorter", pipeName: nil, piped: "Send the numbers.")
        XCTAssertEqual(snippet?.kind, .instruction)
        XCTAssertEqual(snippet?.piped, "Send the numbers.")
        XCTAssertNil(snippet?.pipeName)
    }

    func testNewestStaysAndOldestDrops() {
        let first = SnippetStore.make(kind: .dictation, original: "a", pipeName: nil, piped: nil)!
        let second = SnippetStore.make(kind: .dictation, original: "b", pipeName: nil, piped: nil)!
        let third = SnippetStore.make(kind: .dictation, original: "c", pipeName: nil, piped: nil)!
        var list = SnippetStore.kept([], adding: first, limit: 2).snippets
        list = SnippetStore.kept(list, adding: second, limit: 2).snippets
        let last = SnippetStore.kept(list, adding: third, limit: 2)
        XCTAssertEqual(last.snippets.map(\.original), ["c", "b"])
        XCTAssertEqual(last.removed, [first.id])
    }

    func testRecordWritesTextAndAudioAndDropsABadFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let audio = root.appendingPathComponent("snippets")
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"), audioDirectory: audio)
        defer { try? FileManager.default.removeItem(at: root) }

        store.record(kind: .dictation, original: "um hello", pipeName: "Clean", piped: "Hello.", samples: [0, 0.5, -0.5, 1])
        let id = try XCTUnwrap(store.snippets.first?.id)
        await store.waitForAudioWrites()

        let again = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"), audioDirectory: audio)
        XCTAssertEqual(again.snippets, store.snippets)
        XCTAssertEqual(again.snippets.first?.pipeName, "Clean")
        XCTAssertEqual(again.snippets.first?.piped, "Hello.")
        XCTAssertEqual(again.snippets.first?.duration ?? -1, 4.0 / 16_000, accuracy: 0.0001)
        XCTAssertTrue(again.hasAudio(id))

        let file = try AVAudioFile(forReading: again.audioURL(for: id))
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(file.length, 4)

        try "{".write(to: root.appendingPathComponent("snippets.json"), atomically: true, encoding: .utf8)
        store.load()
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.snippets.map(\.original), ["um hello"])

        let junk = audio.appendingPathComponent("not-json.wav")
        try Data([0]).write(to: junk)
        store.delete(id: id)
        XCTAssertTrue(store.snippets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audioURL(for: id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
    }
}
