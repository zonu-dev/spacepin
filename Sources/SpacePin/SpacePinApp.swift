import AppKit
import Combine
import SpacePinCore
import SwiftUI

@main
struct SpacePinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator

    init() {
        let coordinator = AppCoordinator()
        coordinator.startIfNeeded()
        AppDelegate.pendingCoordinator = coordinator
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingCoordinator: AppCoordinator?

    private var coordinator: AppCoordinator?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let pendingCoordinator = Self.pendingCoordinator {
            Self.pendingCoordinator = nil
            configure(with: pendingCoordinator)
        }
    }

    private func configure(with coordinator: AppCoordinator) {
        guard self.coordinator == nil else {
            return
        }

        self.coordinator = coordinator
        installStatusItemIfNeeded()
        observeCoordinator()
        rebuildMenu()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "pin.circle.fill",
                accessibilityDescription: L10n.text("app.name", fallback: "SpacePin")
            )
            button.imagePosition = .imageOnly
            button.toolTip = L10n.text("app.name", fallback: "SpacePin")
        }
        statusItem.menu = NSMenu()
        self.statusItem = statusItem
    }

    private func observeCoordinator() {
        guard let coordinator else {
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
    }

    private func rebuildMenu() {
        guard let coordinator, let menu = statusItem?.menu else {
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

        if let lastErrorMessage = coordinator.lastErrorMessage, !lastErrorMessage.isEmpty {
            menu.addItem(.separator())
            menu.addItem(makeErrorItem(message: lastErrorMessage))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("app.name", fallback: "SpacePin"))
                .font(.title2.bold())

            Text(L10n.text("settings.storage_path", fallback: "Pins are stored in ~/Library/Application Support/SpacePin."))
                .foregroundStyle(.secondary)

            Button(L10n.text("action.open_manager", fallback: "Open Manager")) {
                coordinator.showManagerWindow()
            }
        }
        .frame(width: 360)
        .padding(24)
    }
}
