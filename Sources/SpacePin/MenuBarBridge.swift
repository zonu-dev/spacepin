import AppKit
import Foundation

enum MenuBarCommand: String {
    case openManager
    case newNotePin
    case importImage
    case bringAllPinsForward
    case quit
}

enum MenuBarBridge {
    static let helperBundleSuffix = ".menubar"
    static let helperAppName = "SpacePinMenuBar.app"
    static let commandUserInfoKey = "command"
    static let backgroundLaunchArgument = "--spacepin-background"
    static let commandNotification = Notification.Name("com.zoochigames.spacepin.command")

    static func helperBundleIdentifier(for bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "") -> String {
        guard !bundleIdentifier.isEmpty else {
            return "com.zoochigames.spacepin.menubar"
        }

        return bundleIdentifier.hasSuffix(helperBundleSuffix)
            ? bundleIdentifier
            : bundleIdentifier + helperBundleSuffix
    }

    static func hostBundleIdentifier(for bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "") -> String {
        guard bundleIdentifier.hasSuffix(helperBundleSuffix) else {
            return bundleIdentifier
        }

        return String(bundleIdentifier.dropLast(helperBundleSuffix.count))
    }

    static func helperAppURL(for hostBundleURL: URL = Bundle.main.bundleURL) -> URL {
        hostBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent(helperAppName, isDirectory: true)
    }

    static func hostAppURL(for helperBundleURL: URL = Bundle.main.bundleURL) -> URL {
        var hostURL = helperBundleURL
        for _ in 0..<4 {
            hostURL.deleteLastPathComponent()
        }

        return hostURL
    }

    static func isBackgroundLaunch(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(backgroundLaunchArgument)
    }

    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static func post(command: MenuBarCommand) {
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification,
            object: nil,
            userInfo: [commandUserInfoKey: command.rawValue],
            options: [.deliverImmediately]
        )
    }

    static func command(from notification: Notification) -> MenuBarCommand? {
        guard let rawValue = notification.userInfo?[commandUserInfoKey] as? String else {
            return nil
        }

        return MenuBarCommand(rawValue: rawValue)
    }
}

@MainActor
enum MenuBarAppLauncher {
    static func launchIfNeeded(bundleIdentifier: String, appURL: URL, arguments: [String], activates: Bool) {
        guard !MenuBarBridge.isRunning(bundleIdentifier: bundleIdentifier) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.arguments = arguments

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("SpacePin launch failed for %@: %@", appURL.path, error.localizedDescription)
            }
        }
    }
}
