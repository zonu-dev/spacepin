import AppKit
import Foundation
import SwiftUI

enum AppLaunchMode {
    case foreground
    case background

    init(processInfo: ProcessInfo = .processInfo) {
        self = MenuBarBridge.isBackgroundLaunch(processInfo: processInfo) ? .background : .foreground
    }

    var shouldShowManagerOnLaunch: Bool {
        self == .foreground
    }

    var shouldPromptForLaunchAtLogin: Bool {
        self == .foreground
    }
}

@main
struct SpacePinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @StateObject private var launchAtLoginController: LaunchAtLoginController

    init() {
        let coordinator = AppCoordinator()
        coordinator.startIfNeeded()
        let launchAtLoginController = LaunchAtLoginController()
        AppDelegate.pendingCoordinator = coordinator
        AppDelegate.pendingLaunchAtLoginController = launchAtLoginController
        AppDelegate.pendingLaunchMode = AppLaunchMode()
        _coordinator = StateObject(wrappedValue: coordinator)
        _launchAtLoginController = StateObject(wrappedValue: launchAtLoginController)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(launchAtLoginController)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingCoordinator: AppCoordinator?
    static var pendingLaunchAtLoginController: LaunchAtLoginController?
    static var pendingLaunchMode: AppLaunchMode?

    private var coordinator: AppCoordinator?
    private var launchAtLoginController: LaunchAtLoginController?
    private var launchMode: AppLaunchMode = .foreground
    private var hasScheduledLaunchAtLoginPrompt = false
    private var commandObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let pendingCoordinator = Self.pendingCoordinator,
           let pendingLaunchAtLoginController = Self.pendingLaunchAtLoginController {
            Self.pendingCoordinator = nil
            Self.pendingLaunchAtLoginController = nil
            launchMode = Self.pendingLaunchMode ?? .foreground
            Self.pendingLaunchMode = nil
            configure(with: pendingCoordinator, launchAtLoginController: pendingLaunchAtLoginController)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLoginController?.refreshStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            coordinator?.showManagerWindow()
        }

        return false
    }

    private func configure(with coordinator: AppCoordinator, launchAtLoginController: LaunchAtLoginController) {
        guard self.coordinator == nil else {
            return
        }

        self.coordinator = coordinator
        self.launchAtLoginController = launchAtLoginController
        launchMenuBarHelperIfNeeded()
        observeRemoteCommands()

        if launchMode.shouldShowManagerOnLaunch {
            coordinator.showManagerWindow()
        }

        scheduleLaunchAtLoginPromptIfNeeded()
    }

    private func launchMenuBarHelperIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let helperBundleIdentifier = MenuBarBridge.helperBundleIdentifier(for: bundleIdentifier)
        let helperURL = MenuBarBridge.helperAppURL()
        MenuBarAppLauncher.launchIfNeeded(
            bundleIdentifier: helperBundleIdentifier,
            appURL: helperURL,
            arguments: [],
            activates: false
        )
    }

    private func observeRemoteCommands() {
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: MenuBarBridge.commandNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let command = MenuBarBridge.command(from: notification) else {
                return
            }

            Task { @MainActor in
                self?.handle(command: command)
            }
        }
    }

    private func handle(command: MenuBarCommand) {
        guard let coordinator else {
            return
        }

        switch command {
        case .openManager:
            coordinator.showManagerWindow()
        case .newNotePin:
            coordinator.createNotePin()
        case .importImage:
            coordinator.presentImageImporter()
        case .bringAllPinsForward:
            coordinator.bringAllPinsToFront()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func scheduleLaunchAtLoginPromptIfNeeded() {
        guard launchMode.shouldPromptForLaunchAtLogin, !hasScheduledLaunchAtLoginPrompt else {
            return
        }

        hasScheduledLaunchAtLoginPrompt = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.presentLaunchAtLoginPromptIfNeeded()
        }
    }

    private func presentLaunchAtLoginPromptIfNeeded() {
        guard let launchAtLoginController, launchAtLoginController.shouldPromptOnLaunch else {
            return
        }

        let suppressButton = NSButton(
            checkboxWithTitle: L10n.text(
                "prompt.launch_at_login_do_not_ask_again",
                fallback: "Don't ask again"
            ),
            target: nil,
            action: nil
        )

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text(
            "prompt.launch_at_login_message",
            fallback: "Open SpacePin automatically when you log in?"
        )
        alert.informativeText = L10n.text(
            "prompt.launch_at_login_info",
            fallback: "You can change this later from the menu bar or Settings. macOS may ask you to approve SpacePin in Login Items."
        )
        alert.addButton(withTitle: L10n.text(
            "prompt.launch_at_login_enable",
            fallback: "Enable"
        ))
        alert.addButton(withTitle: L10n.text(
            "prompt.not_now",
            fallback: "Not Now"
        ))
        alert.accessoryView = suppressButton

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if suppressButton.state == .on {
            launchAtLoginController.setPromptSuppressed(true)
        }

        if response == .alertFirstButtonReturn {
            launchAtLoginController.setEnabled(true)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("app.name", fallback: "SpacePin"))
                .font(.title2.bold())

            Text(L10n.text("settings.storage_path", fallback: "Pins are stored in ~/Library/Application Support/SpacePin."))
                .foregroundStyle(.secondary)

            Toggle(
                L10n.text("settings.launch_at_login", fallback: "Launch at login"),
                isOn: Binding(get: {
                    launchAtLoginController.isEnabled
                }, set: { newValue in
                    launchAtLoginController.setEnabled(newValue)
                })
            )

            Text(L10n.text(
                "settings.launch_at_login_help",
                fallback: "Automatically open SpacePin when you log in."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)

            if launchAtLoginController.requiresApproval {
                Text(L10n.text(
                    "settings.launch_at_login_requires_approval",
                    fallback: "Allow SpacePin in System Settings > General > Login Items."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                Button(L10n.text("action.open_login_items_settings", fallback: "Open Login Items Settings")) {
                    launchAtLoginController.openSystemSettings()
                }
            }

            if let errorMessage = launchAtLoginController.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button(L10n.text("action.open_manager", fallback: "Open Manager")) {
                coordinator.showManagerWindow()
            }
        }
        .frame(width: 360)
        .padding(24)
    }
}
