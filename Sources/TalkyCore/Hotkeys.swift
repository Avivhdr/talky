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
    public static func label(_ raw: String) -> String {
        let s = raw.lowercased()
        let names = ["fn": "fn", "globe": "fn", "right_option": "right ⌥", "left_option": "left ⌥",
                     "right_command": "right ⌘", "left_command": "left ⌘", "right_control": "right ⌃",
                     "left_control": "left ⌃", "right_shift": "right ⇧", "left_shift": "left ⇧"]
        if let n = names[s] { return n }
        return s.split(separator: "+").map { part -> String in
            switch part {
            case "cmd", "command": return "⌘"
            case "ctrl", "control": return "⌃"
            case "opt", "option", "alt": return "⌥"
            case "shift": return "⇧"
            default: return part.capitalized
            }
        }.joined()
    }
}

public enum PickerKey { case up, down, choose }

@MainActor
public protocol KeyMonitorDelegate: AnyObject {
    var hotkeysEnabled: Bool { get }
    func mainHotkeyDown()
    func mainHotkeyUp()
    func transformHotkeyFired()
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
    public var mainSpec: HotkeySpec?
    public var transformSpec: HotkeySpec?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var mainDown = false
    private var transformModDownAt: Date?
    private var transformDirty = false
    private var transformChordDown = false
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
        transformModDownAt = nil
        transformChordDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        // Our own synthetic Cmd-C / Cmd-V.
        if event.getIntegerValueField(.eventSourceUnixProcessID) == ownPID { return false }
        guard let delegate, delegate.hotkeysEnabled else {
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
            if case let .modifier(k, mask)? = transformSpec, code == k {
                if flags.rawValue & mask != 0 {
                    transformModDownAt = Date()
                    transformDirty = false
                } else if let at = transformModDownAt {
                    transformModDownAt = nil
                    // A clean tap only. Holding it as ⌥ for typing special characters must not trigger.
                    if !transformDirty, Date().timeIntervalSince(at) < 0.5 { async { $0.transformHotkeyFired() } }
                }
                return false
            }
            if transformModDownAt != nil { transformDirty = true }
            return false

        case .keyDown:
            if transformModDownAt != nil { transformDirty = true }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if case let .chord(k, mods)? = mainSpec, code == k, flags.intersection(HotkeySpec.chordMask) == mods {
                if !isRepeat, !mainDown {
                    mainDown = true
                    async { $0.mainHotkeyDown() }
                }
                return true
            }
            if case let .chord(k, mods)? = transformSpec, code == k, flags.intersection(HotkeySpec.chordMask) == mods {
                if !isRepeat { transformChordDown = true }
                return true
            }
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
            if case let .chord(k, _)? = transformSpec, code == k {
                // Fire on release so the chord's modifiers are up before we send Cmd-C.
                if transformChordDown {
                    transformChordDown = false
                    async { $0.transformHotkeyFired() }
                }
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
