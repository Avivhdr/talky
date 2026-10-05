import AppKit
import Sparkle

public enum AppInfo {
    public static let bundleId = Bundle.main.bundleIdentifier ?? "dev.talky.Talky"
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Sparkle auto-updates. Builds without SUFeedURL in Info.plist (plain `swift run`, local
/// dev builds) get no updater, so they never prompt about a feed that doesn't exist.
@MainActor
public final class Updater: ObservableObject {
    public static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

    private init() {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = hasFeed
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    public var isAvailable: Bool { controller != nil }

    public var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    public func checkNow() { controller?.checkForUpdates(nil) }
}

/// Removes everything Talky put on this Mac, then moves the app to the Trash and quits.
@MainActor
public enum Uninstaller {
    public static func confirmAndRun() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Talky?"
        alert.informativeText = "Talky will turn off launch at login, clear its macOS permissions, move itself to the Trash and quit."
        let deleteData = NSButton(checkboxWithTitle: "Also delete my settings, pipes and API keys", target: nil, action: nil)
        deleteData.state = .on
        alert.accessoryView = deleteData
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(deleteData: deleteData.state == .on)
    }

    static func run(deleteData: Bool) {
        if LoginItem.isEnabled { LoginItem.set(false) }

        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "All", AppInfo.bundleId]
        try? reset.run()
        reset.waitUntilExit()

        UserDefaults.standard.removePersistentDomain(forName: AppInfo.bundleId)

        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        var doomed = [
            Paths.logsDir,
            library.appendingPathComponent("Caches/\(AppInfo.bundleId)"),
            library.appendingPathComponent("HTTPStorages/\(AppInfo.bundleId)"),
            library.appendingPathComponent("Application Support/\(AppInfo.bundleId)"),
        ]
        if deleteData { doomed.append(Paths.configDir) }
        for url in doomed { try? fm.removeItem(at: url) }

        let app = Bundle.main.bundleURL
        if app.pathExtension == "app" { try? fm.trashItem(at: app, resultingItemURL: nil) }
        NSApp.terminate(nil)
    }
}
