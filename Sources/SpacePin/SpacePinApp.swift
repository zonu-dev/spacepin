import AppKit
import Combine
import SpacePinCore
import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var pendingCoordinator: AppCoordinator?
    static var pendingLaunchAtLoginController: LaunchAtLoginController?

    private var coordinator: AppCoordinator?
    private var launchAtLoginController: LaunchAtLoginController?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var hasScheduledLaunchAtLoginPrompt = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let pendingCoordinator = Self.pendingCoordinator,
           let pendingLaunchAtLoginController = Self.pendingLaunchAtLoginController {
            Self.pendingCoordinator = nil
            Self.pendingLaunchAtLoginController = nil
            configure(with: pendingCoordinator, launchAtLoginController: pendingLaunchAtLoginController)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLoginController?.refreshStatus()
    }

    private func configure(with coordinator: AppCoordinator, launchAtLoginController: LaunchAtLoginController) {
        guard self.coordinator == nil else {
            return
        }

        self.coordinator = coordinator
        self.launchAtLoginController = launchAtLoginController
        installStatusItemIfNeeded()
        observeCoordinator()
        rebuildMenu()
        scheduleLaunchAtLoginPromptIfNeeded()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let image = NSImage(
            systemSymbolName: "pin.circle.fill",
            accessibilityDescription: L10n.text("app.name", fallback: "SpacePin")
        )
        let itemLength = image == nil ? NSStatusItem.variableLength : NSStatusItem.squareLength
        let statusItem = NSStatusBar.system.statusItem(withLength: itemLength)
        if let button = statusItem.button {
            if let image {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
                button.title = ""
            } else {
                button.title = "SP"
            }
            button.toolTip = L10n.text("app.name", fallback: "SpacePin")
        }
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        statusItem.isVisible = true
        self.statusItem = statusItem
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginController?.refreshStatus()
    }

    private func scheduleLaunchAtLoginPromptIfNeeded() {
        guard !hasScheduledLaunchAtLoginPrompt else {
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

    private func observeCoordinator() {
        guard let coordinator, let launchAtLoginController else {
            return
        }

        coordinator.$pins
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        coordinator.$lastErrorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        launchAtLoginController.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        launchAtLoginController.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        guard let coordinator, let launchAtLoginController, let menu = statusItem?.menu else {
            return
        }

        menu.removeAllItems()

        menu.addItem(makeActionItem(
            title: L10n.text("action.open_manager", fallback: "Open Manager"),
            keyEquivalent: "0",
            modifiers: [.command, .option],
            action: #selector(openManager)
        ))
        menu.addItem(makeActionItem(
            title: L10n.text("action.new_note_pin", fallback: "New Note Pin"),
            keyEquivalent: "n",
            modifiers: [.command, .option],
            action: #selector(createNotePin)
        ))
        menu.addItem(makeActionItem(
            title: L10n.text("action.import_image", fallback: "Import Image…"),
            keyEquivalent: "i",
            modifiers: [.command, .option],
            action: #selector(importImage)
        ))
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

        if !coordinator.pins.isEmpty {
            menu.addItem(makeActionItem(
                title: L10n.text("action.bring_all_pins_forward", fallback: "Bring All Pins Forward"),
                action: #selector(bringAllPinsForward)
            ))
            menu.addItem(.separator())

            for item in coordinator.pins {
                menu.addItem(makePinMenuItem(for: item))
            }
        } else {
            menu.addItem(.separator())
            menu.addItem(makeDisabledItem(title: L10n.text("label.no_active_pins", fallback: "No active pins")))
        }

        let errorMessages = [coordinator.lastErrorMessage, launchAtLoginController.errorMessage]
            .compactMap { message -> String? in
                guard let message, !message.isEmpty else {
                    return nil
                }

                return message
            }

        if !errorMessages.isEmpty {
            menu.addItem(.separator())
            for message in errorMessages {
                menu.addItem(makeErrorItem(message: message))
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeActionItem(
            title: L10n.format("action.quit_app", fallback: "Quit %@", L10n.text("app.name", fallback: "SpacePin")),
            action: #selector(quitApp)
        ))
    }

    private func makePinMenuItem(for item: PinItem) -> NSMenuItem {
        let menuItem = NSMenuItem(title: item.displayTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: item.displayTitle)

        submenu.addItem(makePinActionItem(
            title: L10n.text("action.show", fallback: "Show"),
            action: #selector(showPin(_:)),
            id: item.id
        ))
        submenu.addItem(makePinActionItem(
            title: L10n.text("action.duplicate", fallback: "Duplicate"),
            action: #selector(duplicatePin(_:)),
            id: item.id
        ))
        submenu.addItem(makePinActionItem(
            title: item.record.locked
                ? L10n.text("action.unlock", fallback: "Unlock")
                : L10n.text("action.lock", fallback: "Lock"),
            action: #selector(toggleLock(_:)),
            id: item.id
        ))
        submenu.addItem(makePinActionItem(
            title: item.record.clickThrough
                ? L10n.text("action.disable_click_through", fallback: "Disable Click-through")
                : L10n.text("action.enable_click_through", fallback: "Enable Click-through"),
            action: #selector(toggleClickThrough(_:)),
            id: item.id
        ))

        if item.record.kind == .note {
            let colorMenuItem = NSMenuItem(title: L10n.text("label.color", fallback: "Color"), action: nil, keyEquivalent: "")
            let colorMenu = NSMenu(title: colorMenuItem.title)

            for preset in NoteColorPreset.allCases {
                let colorItem = NSMenuItem(
                    title: L10n.noteColorName(preset),
                    action: #selector(setNoteColor(_:)),
                    keyEquivalent: ""
                )
                colorItem.target = self
                colorItem.representedObject = "\(item.id.uuidString)|\(preset.rawValue)"
                colorItem.state = item.record.noteColorPreset == preset ? .on : .off
                colorMenu.addItem(colorItem)
            }

            colorMenuItem.submenu = colorMenu
            submenu.addItem(colorMenuItem)
        }

        submenu.addItem(makePinActionItem(
            title: L10n.text("action.delete", fallback: "Delete"),
            action: #selector(deletePin(_:)),
            id: item.id
        ))

        menuItem.submenu = submenu
        return menuItem
    }

    private func makeActionItem(
        title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func makePinActionItem(title: String, action: Selector, id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id.uuidString
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
            attributes: [
                .foregroundColor: NSColor.systemRed,
            ]
        )
        return item
    }

    private func uuid(for sender: NSMenuItem) -> UUID? {
        guard let stringValue = sender.representedObject as? String else {
            return nil
        }

        return UUID(uuidString: stringValue)
    }

    @objc
    private func openManager() {
        coordinator?.showManagerWindow()
    }

    @objc
    private func createNotePin() {
        coordinator?.createNotePin()
    }

    @objc
    private func importImage() {
        coordinator?.presentImageImporter()
    }

    @objc
    private func toggleLaunchAtLogin() {
        guard let launchAtLoginController else {
            return
        }

        launchAtLoginController.setEnabled(!launchAtLoginController.isEnabled)
    }

    @objc
    private func openLoginItemsSettings() {
        launchAtLoginController?.openSystemSettings()
    }

    @objc
    private func bringAllPinsForward() {
        coordinator?.bringAllPinsToFront()
    }

    @objc
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc
    private func showPin(_ sender: NSMenuItem) {
        guard let id = uuid(for: sender) else {
            return
        }

        coordinator?.bringToFront(id: id)
    }

    @objc
    private func duplicatePin(_ sender: NSMenuItem) {
        guard let id = uuid(for: sender) else {
            return
        }

        coordinator?.duplicatePin(id: id)
    }

    @objc
    private func toggleLock(_ sender: NSMenuItem) {
        guard
            let id = uuid(for: sender),
            let item = coordinator?.pins.first(where: { $0.id == id })
        else {
            return
        }

        item.setLocked(!item.record.locked)
    }

    @objc
    private func toggleClickThrough(_ sender: NSMenuItem) {
        guard
            let id = uuid(for: sender),
            let item = coordinator?.pins.first(where: { $0.id == id })
        else {
            return
        }

        item.setClickThrough(!item.record.clickThrough)
    }

    @objc
    private func setNoteColor(_ sender: NSMenuItem) {
        guard
            let payload = sender.representedObject as? String,
            let separatorIndex = payload.firstIndex(of: "|")
        else {
            return
        }

        let id = UUID(uuidString: String(payload[..<separatorIndex]))
        let preset = NoteColorPreset(rawValue: String(payload[payload.index(after: separatorIndex)...]))

        guard
            let id,
            let preset,
            let item = coordinator?.pins.first(where: { $0.id == id })
        else {
            return
        }

        item.setNoteColorPreset(preset)
    }

    @objc
    private func deletePin(_ sender: NSMenuItem) {
        guard let id = uuid(for: sender) else {
            return
        }

        coordinator?.deletePin(id: id)
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
