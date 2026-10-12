import AppKit
import CoreGraphics

/// A hotkey from config.json. Two shapes:
/// - a lone modifier: "fn", "right_option", "left_option", "right_command", "right_control", "right_shift", ...
/// - a chord: "ctrl+opt+space", "cmd+shift+d", "f13"
public enum HotkeySpec: Equatable {
    case modifier(keyCode: Int64, mask: UInt64)
    case chord(keyCode: Int64, modifiers: CGEventFlags)

    // Device-dependent bits from IOKit's NX_DEVICE*KEYMASK tell left and right modifiers apart.
    static let modifierKeys: [String: (Int64, UInt64)] = [
        "fn": (63, CGEventFlags.maskSecondaryFn.rawValue),
        "globe": (63, CGEventFlags.maskSecondaryFn.rawValue),
        "right_option": (61, 0x40), "left_option": (58, 0x20),
        "right_command": (54, 0x10), "left_command": (55, 0x08),
        "right_control": (62, 0x2000), "left_control": (59, 0x01),
        "right_shift": (60, 0x04), "left_shift": (56, 0x02),
    ]

    static let keyCodes: [String: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
        "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48,
        "space": 49, "`": 50, "delete": 51, "backspace": 51,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    ]

    static let chordMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    public static func parse(_ raw: String) -> HotkeySpec? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        if let (code, mask) = modifierKeys[s] { return .modifier(keyCode: code, mask: mask) }
        let parts = s.split(separator: "+").map(String.init)
        guard let key = parts.last, let code = keyCodes[key] else { return nil }
        var mods: CGEventFlags = []
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command": mods.insert(.maskCommand)
            case "ctrl", "control": mods.insert(.maskControl)
            case "opt", "option", "alt": mods.insert(.maskAlternate)
            case "shift": mods.insert(.maskShift)
            default: return nil
            }
        }
        return .chord(keyCode: code, modifiers: mods)
    }

    public var isModifierOnly: Bool {
        if case .modifier = self { return true }
        return false
    }

    /// Short label for UI hints, e.g. "fn" or "⌃⌥Space".
    public static func label(_ raw: String) -> String { keycaps(raw).joined() }

    /// One label per key, e.g. ["right ⌥"] or ["⌃", "⌥", "Space"], for drawing the hotkey as key caps.
    public static func keycaps(_ raw: String) -> [String] {
        let s = raw.lowercased().replacingOccurrences(of: " ", with: "")
        let names = ["fn": "fn", "globe": "fn", "right_option": "right ⌥", "left_option": "left ⌥",
                     "right_command": "right ⌘", "left_command": "left ⌘", "right_control": "right ⌃",
                     "left_control": "left ⌃", "right_shift": "right ⇧", "left_shift": "left ⇧"]
        if let n = names[s] { return [n] }
        return s.split(separator: "+").map { part -> String in
            switch part {
            case "cmd", "command": return "⌘"
            case "ctrl", "control": return "⌃"
            case "opt", "option", "alt": return "⌥"
            case "shift": return "⇧"
            default: return part.capitalized
            }
        }
    }
}

/// Turns the keys pressed in the Settings shortcut recorder into a hotkey name that HotkeySpec parses.
/// A modifier pressed and released alone gives that modifier ("right_option"). Modifiers held with a
/// key give a chord ("ctrl+opt+space"). It takes NSEvent key codes and flags, whose bits match CGEventFlags.
public struct HotkeyCapture {
    public enum Result: Equatable {
        case captured(String)
        /// The keys can't be a Talky hotkey. The text says why, for the recorder to show.
        case rejected(String)
    }

    static let modifierNames: [Int64: String] = [
        63: "fn", 61: "right_option", 58: "left_option", 54: "right_command", 55: "left_command",
        62: "right_control", 59: "left_control", 60: "right_shift", 56: "left_shift",
    ]
    static let modifierSymbols: [(codes: Set<Int64>, symbol: String)] = [
        ([63], "fn"), ([59, 62], "⌃"), ([58, 61], "⌥"), ([56, 60], "⇧"), ([55, 54], "⌘"),
    ]
    /// Key code to name, without the aliases ("enter", "backspace"), so a recorded hotkey has one spelling.
    static let keyNames: [Int64: String] = Dictionary(
        HotkeySpec.keyCodes.filter { !["enter", "backspace"].contains($0.key) }.map { ($0.value, $0.key) },
        uniquingKeysWith: { first, _ in first })

    /// Modifier key codes held now.
    private var held = Set<Int64>()
    /// The one modifier pressed so far, while no other key has joined it.
    private var lone: Int64?

    public init() {}

    /// The modifiers held now, for the recorder to show while it waits: ["right ⌥"] for one, ["⌃", "⌥"] for more.
    public var heldKeycaps: [String] {
        if held.count == 1, let code = held.first, let name = Self.modifierNames[code] {
            return HotkeySpec.keycaps(name)
        }
        return Self.modifierSymbols.filter { !$0.codes.isDisjoint(with: held) }.map(\.symbol)
    }

    public mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags) -> Result? {
        guard let name = Self.modifierNames[keyCode], let (_, mask) = HotkeySpec.modifierKeys[name] else { return nil }
        if flags.rawValue & mask != 0 {
            lone = held.isEmpty ? keyCode : nil
            held.insert(keyCode)
            return nil
        }
        held.remove(keyCode)
        guard lone == keyCode else { return nil }
        lone = nil
        return .captured(name)
    }

    public mutating func keyDown(keyCode: Int64, flags: CGEventFlags) -> Result? {
        lone = nil
        guard let key = Self.keyNames[keyCode] else {
            return .rejected("Talky can't use that key. Use a letter, a number, Space or an F key.")
        }
        let mods = flags.intersection(HotkeySpec.chordMask)
        let isFunctionKey = key.count > 1 && key.hasPrefix("f")
        // A plain key, or one with only ⇧, would stop that key from typing in every app.
        if !isFunctionKey, mods.subtracting(.maskShift).isEmpty {
            return .rejected("Add ⌃, ⌥ or ⌘ to that key, or press one modifier key by itself.")
        }
        var parts: [String] = []
        if mods.contains(.maskControl) { parts.append("ctrl") }
        if mods.contains(.maskAlternate) { parts.append("opt") }
        if mods.contains(.maskShift) { parts.append("shift") }
        if mods.contains(.maskCommand) { parts.append("cmd") }
        return .captured((parts + [key]).joined(separator: "+"))
    }
}

public enum PickerKey { case up, down, choose }

/// A hotkey that fires once per tap: a clean tap of a lone modifier, or a chord when its key comes up.
/// The transform hotkey and the hands-free hotkey work this way.
struct TapHotkey {
    var spec: HotkeySpec?
    private var modifierDownAt: Date?
    private var dirty = false
    private var chordDown = false

    init(spec: HotkeySpec? = nil) { self.spec = spec }

    /// A modifier changed. Returns nil when it isn't this hotkey's modifier, else whether the tap fired.
    mutating func flagsChanged(code: Int64, flags: CGEventFlags) -> Bool? {
        guard case let .modifier(k, mask)? = spec, code == k else {
            if modifierDownAt != nil { dirty = true }
            return nil
        }
        if flags.rawValue & mask != 0 {
            modifierDownAt = Date()
            dirty = false
            return false
        }
        guard let at = modifierDownAt else { return false }
        modifierDownAt = nil
        // A clean tap only. Holding the key as ⌥ or ⌘ for other keys must not fire.
        return !dirty && Date().timeIntervalSince(at) < 0.5
    }

    /// A key went down. Returns true when it is this hotkey's chord, which the monitor swallows.
    mutating func keyDown(code: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        if modifierDownAt != nil { dirty = true }
        guard case let .chord(k, mods)? = spec, code == k, flags.intersection(HotkeySpec.chordMask) == mods else { return false }
        if !isRepeat { chordDown = true }
        return true
    }

    /// A key came up. Returns nil when it isn't this chord's key, else whether the chord fired.
    /// It fires on release, so the chord's modifiers are up before Talky copies or types.
    mutating func keyUp(code: Int64) -> Bool? {
        guard case let .chord(k, _)? = spec, code == k else { return nil }
        defer { chordDown = false }
        return chordDown
    }

    mutating func reset() {
        modifierDownAt = nil
        chordDown = false
    }
}

@MainActor
public protocol KeyMonitorDelegate: AnyObject {
    var hotkeysEnabled: Bool { get }
    func mainHotkeyDown()
    func mainHotkeyUp()
    func transformHotkeyFired()
    /// A tap of the hands-free hotkey: start a hands-free recording, or stop the one in progress.
    func handsFreeHotkeyFired()
    func escapePressed()
    /// Return true to swallow the key so the digit doesn't reach the focused app.
    func digitPressed(_ n: Int) -> Bool
    /// ↑, ↓ or Return. Return true to swallow the key: the transform picker uses them while it is open,
    /// and Return also finishes a hands-free spoken instruction.
    func pickerKeyPressed(_ key: PickerKey) -> Bool
    /// Any other key while the main modifier hotkey is held (e.g. fn+arrow).
    func otherKeyWhileHeld()
}

/// One CGEventTap for everything. It passes every event through untouched except the chord
/// hotkeys and digits used for pipe selection, so Esc and normal typing still reach the focused app.
@MainActor
public final class KeyMonitor {
    public weak var delegate: KeyMonitorDelegate?
    /// True while Settings records a new hotkey: the tap passes every key through, so the keys
    /// reach the recorder and the current hotkeys don't start a dictation.
    public static var isPaused = false
    public var mainSpec: HotkeySpec?
    public var transformSpec: HotkeySpec? {
        get { transformTap.spec }
        set { transformTap.spec = newValue }
    }
    public var handsFreeSpec: HotkeySpec? {
        get { handsFreeTap.spec }
        set { handsFreeTap.spec = newValue }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mainDown = false
    private var transformTap = TapHotkey()
    private var handsFreeTap = TapHotkey()
    private var swallowedKeyUps = Set<Int64>()
    private let ownPID = Int64(ProcessInfo.processInfo.processIdentifier)

    static let digitCodes: [Int64: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    static let escapeCode: Int64 = 53
    /// ↑, ↓, Return and the keypad Enter.
    static let pickerCodes: [Int64: PickerKey] = [126: .up, 125: .down, 36: .choose, 76: .choose]

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Fails until the app has Accessibility permission.
    public func start() -> Bool {
        if tap != nil { return true }
        // Without Accessibility, tapCreate makes macOS show its own prompt. Onboarding asks at its permissions step.
        guard Permissions.accessibility else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = src
        return true
    }

    public func resetState() {
        mainDown = false
        transformTap.reset()
        handsFreeTap.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        // Our own synthetic Cmd-C / Cmd-V.
        if event.getIntegerValueField(.eventSourceUnixProcessID) == ownPID { return false }
        guard let delegate, delegate.hotkeysEnabled, !Self.isPaused else {
            if mainDown { mainDown = false; delegate?.mainHotkeyUp() }
            return false
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch type {
        case .flagsChanged:
            if case let .modifier(k, mask)? = mainSpec, code == k {
                let down = flags.rawValue & mask != 0
                if down, !mainDown {
                    mainDown = true
                    async { $0.mainHotkeyDown() }
                } else if !down, mainDown {
                    mainDown = false
                    async { $0.mainHotkeyUp() }
                }
                return false
            }
            if transformTap.flagsChanged(code: code, flags: flags) == true { async { $0.transformHotkeyFired() } }
            if handsFreeTap.flagsChanged(code: code, flags: flags) == true { async { $0.handsFreeHotkeyFired() } }
            return false

        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            // Both run, so any key also spoils a modifier tap that is in progress.
            let isTransformChord = transformTap.keyDown(code: code, flags: flags, isRepeat: isRepeat)
            let isHandsFreeChord = handsFreeTap.keyDown(code: code, flags: flags, isRepeat: isRepeat)
            if case let .chord(k, mods)? = mainSpec, code == k, flags.intersection(HotkeySpec.chordMask) == mods {
                if !isRepeat, !mainDown {
                    mainDown = true
                    async { $0.mainHotkeyDown() }
                }
                return true
            }
            if isTransformChord || isHandsFreeChord { return true }
            if code == Self.escapeCode {
                async { $0.escapePressed() }
                return false
            }
            if let key = Self.pickerCodes[code], flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                // A held key repeats. Arrows keep moving; a held Return must not reach the app once the picker closes.
                if isRepeat, swallowedKeyUps.contains(code) {
                    if key != .choose { _ = delegate.pickerKeyPressed(key) }
                    return true
                }
                if !isRepeat, delegate.pickerKeyPressed(key) {
                    swallowedKeyUps.insert(code)
                    return true
                }
                return false
            }
            if let n = Self.digitCodes[code], flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                if delegate.digitPressed(n) {
                    swallowedKeyUps.insert(code)
                    return true
                }
                return false
            }
            if mainDown, mainSpec?.isModifierOnly == true { async { $0.otherKeyWhileHeld() } }
            return false

        case .keyUp:
            if swallowedKeyUps.remove(code) != nil { return true }
            if case let .chord(k, _)? = mainSpec, code == k {
                if mainDown {
                    mainDown = false
                    async { $0.mainHotkeyUp() }
                }
                return true
            }
            if let fired = transformTap.keyUp(code: code) {
                if fired { async { $0.transformHotkeyFired() } }
                return true
            }
            if let fired = handsFreeTap.keyUp(code: code) {
                if fired { async { $0.handsFreeHotkeyFired() } }
                return true
            }
            return false

        default:
            return false
        }
    }

    /// Hotkey work (starting the mic, etc.) runs after the tap callback returns so typing never stalls.
    private func async(_ f: @escaping @MainActor (KeyMonitorDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let d = self?.delegate else { return }
            MainActor.assumeIsolated { f(d) }
        }
    }
}
