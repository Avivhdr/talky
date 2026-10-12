import AppKit
import ApplicationServices
import AVFoundation

/// Full copy of the pasteboard (every item, every type) so it can be put back.
struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pb: NSPasteboard = .general) {
        items = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
    }

    func restore(_ pb: NSPasteboard = .general) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let objs: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (t, data) in dict { item.setData(data, forType: t) }
            return item
        }
        pb.writeObjects(objs)
    }
}

@MainActor
public enum TextIO {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Puts text at the cursor of the focused app via the pasteboard and Cmd-V.
    public static func insert(_ text: String, restorePrevious: Bool, restoreDelayMs: Double) {
        let pb = NSPasteboard.general
        let snapshot = restorePrevious ? PasteboardSnapshot(pb) : nil
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Clipboard managers skip transient entries; only mark it when we're about to put the old one back.
        if restorePrevious { pb.setData(Data(), forType: transientType) }
        let ourChange = pb.changeCount
        postKey(9, flags: .maskCommand) // v

        if let snapshot {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelayMs / 1000) {
                // Don't clobber something the user copied in the meantime.
                if pb.changeCount == ourChange { snapshot.restore(pb) }
            }
        }
    }

    /// Selected text in the focused app. Tries Accessibility first, then falls back to Cmd-C
    /// (and restores the clipboard) for apps that don't expose AXSelectedText, such as many Electron apps.
    public static func selectedText() async -> String? {
        if NSApp.isActive { return ownSelectedText() }
        if let s = axSelectedText(), !s.isEmpty { return s }

        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pb)
        let before = pb.changeCount
        postKey(8, flags: .maskCommand) // c
        var copied: String?
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before {
                copied = pb.string(forType: .string)
                break
            }
        }
        if pb.changeCount != before { snapshot.restore(pb) }
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    /// The selection in one of Talky's own windows, such as the onboarding try box.
    /// Talky answers Accessibility requests on its main thread, so asking itself from here could block.
    /// Single-line fields are left out: one of them is the API key field.
    static func ownSelectedText() -> String? {
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView, !view.isFieldEditor else { return nil }
        let text = (view.string as NSString).substring(with: view.selectedRange())
        return text.isEmpty ? nil : text
    }

    static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

public enum Permissions {
    // No Input Monitoring: the hotkey tap is an active one, and Accessibility covers it.
    public static var accessibility: Bool { AXIsProcessTrusted() }
    public static var microphone: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    public static var microphoneUndecided: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined }

    /// What to tell the user when the microphone can't record, or nil when it can.
    /// Without access macOS records silence, so Talky must check before it records.
    public static var microphoneProblem: String? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return nil
        case .notDetermined: return "Allow the microphone, then try again"
        default: return "Talky needs microphone access"
        }
    }

    /// The system prompt the first time; after the user has answered, only System Settings can change it.
    @MainActor
    public static func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task { _ = await AudioRecorder.requestPermission() }
        } else {
            openSettings("Privacy_Microphone")
        }
    }

    public static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    public static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

