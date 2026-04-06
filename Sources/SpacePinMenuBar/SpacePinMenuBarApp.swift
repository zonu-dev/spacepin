import AppKit
import Foundation
import SwiftUI

@main
struct SpacePinMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let launchAtLoginController = LaunchAtLoginController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItemIfNeeded()
        ensureHostAppRunning()
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginController.refreshStatus()
        rebuildMenu()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let title = L10n.text("app.name", fallback: "SpacePin")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "pin.circle.fill", accessibilityDescription: title) {
                image.isTemplate = true
                image.size = NSSize(width: 16, height: 16)
                button.image = image
                button.imagePosition = .imageOnly
            }
            button.toolTip = title
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = true
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else {
            return
        }

        menu.removeAllItems()

        menu.addItem(makeActionItem(
            title: L10n.text("action.open_manager", fallback: "Open Manager"),
            action: #selector(openManager)
        ))
        menu.addItem(makeActionItem(
            title: L10n.text("action.new_note_pin", fallback: "New Note Pin"),
            action: #selector(createNotePin)
        ))
        menu.addItem(makeActionItem(
            title: L10n.text("action.import_image", fallback: "Import Image…"),
            action: #selector(importImage)
        ))
        menu.addItem(makeActionItem(
            title: L10n.text("action.bring_all_pins_forward", fallback: "Bring All Pins Forward"),
            action: #selector(bringAllPinsForward)
        ))
        menu.addItem(.separator())
        menu.addItem(makeToggleItem(
            title: L10n.text("settings.launch_at_login", fallback: "Launch at login"),
            isOn: launchAtLoginController.isEnabled,
            action: #selector(toggleLaunchAtLogin)
        ))

        if launchAtLoginController.requiresApproval {
            menu.addItem(makeDisabledItem(title: L10n.text(
                "settings.launch_at_login_requires_approval",
                fallback: "Allow SpacePin in System Settings > General > Login Items."
            )))
            menu.addItem(makeActionItem(
                title: L10n.text("action.open_login_items_settings", fallback: "Open Login Items Settings"),
                action: #selector(openLoginItemsSettings)
            ))
        }

        if let errorMessage = launchAtLoginController.errorMessage, !errorMessage.isEmpty {
            menu.addItem(makeErrorItem(message: errorMessage))
        }

        menu.addItem(.separator())
        menu.addItem(makeActionItem(
            title: L10n.format("action.quit_app", fallback: "Quit %@", L10n.text("app.name", fallback: "SpacePin")),
            action: #selector(quitSpacePin)
        ))
    }

    private func makeActionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeToggleItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = makeActionItem(title: title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func makeDisabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeErrorItem(message: String) -> NSMenuItem {
        let item = makeDisabledItem(title: message)
        item.attributedTitle = NSAttributedString(
            string: message,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        return item
    }

    private func ensureHostAppRunning() {
        let hostBundleIdentifier = MenuBarBridge.hostBundleIdentifier()
        let hostURL = MenuBarBridge.hostAppURL()
        MenuBarAppLauncher.launchIfNeeded(
            bundleIdentifier: hostBundleIdentifier,
            appURL: hostURL,
            arguments: [MenuBarBridge.backgroundLaunchArgument],
            activates: false
        )
    }

    private func dispatch(_ command: MenuBarCommand) {
        let hostBundleIdentifier = MenuBarBridge.hostBundleIdentifier()
        let hostWasRunning = MenuBarBridge.isRunning(bundleIdentifier: hostBundleIdentifier)
        ensureHostAppRunning()

        let delay: DispatchTimeInterval = hostWasRunning ? .milliseconds(0) : .milliseconds(600)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MenuBarBridge.post(command: command)
        }
    }

    @objc
    private func openManager() {
        dispatch(.openManager)
    }

    @objc
    private func createNotePin() {
        dispatch(.newNotePin)
    }

    @objc
    private func importImage() {
        dispatch(.importImage)
    }

    @objc
    private func bringAllPinsForward() {
        dispatch(.bringAllPinsForward)
    }

    @objc
    private func toggleLaunchAtLogin() {
        launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled)
        rebuildMenu()
    }

    @objc
    private func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    @objc
    private func quitSpacePin() {
        MenuBarBridge.post(command: .quit)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            NSApplication.shared.terminate(nil)
        }
    }
}
