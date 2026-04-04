import AppKit
import SpacePinCore
import SwiftUI

@main
struct SpacePinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator

    init() {
        let coordinator = AppCoordinator()
        coordinator.startIfNeeded()
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some Scene {
        MenuBarExtra(L10n.text("app.name", fallback: "SpacePin"), systemImage: "pin.circle.fill") {
            MenuBarContentView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        Button(L10n.text("action.open_manager", fallback: "Open Manager")) {
            coordinator.showManagerWindow()
        }
        .keyboardShortcut("0", modifiers: [.command, .option])

        Button(L10n.text("action.new_note_pin", fallback: "New Note Pin")) {
            coordinator.createNotePin()
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button(L10n.text("action.import_image", fallback: "Import Image…")) {
            coordinator.presentImageImporter()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])

        if !coordinator.pins.isEmpty {
            Button(L10n.text("action.bring_all_pins_forward", fallback: "Bring All Pins Forward")) {
                coordinator.bringAllPinsToFront()
            }

            Divider()

            ForEach(coordinator.pins) { item in
                PinMenuSection(item: item, coordinator: coordinator)
            }
        } else {
            Divider()

            Text(L10n.text("label.no_active_pins", fallback: "No active pins"))
                .foregroundStyle(.secondary)
        }

        if let lastErrorMessage = coordinator.lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
                .foregroundStyle(.red)
        }

        Divider()

        Button(L10n.format("action.quit_app", fallback: "Quit %@", L10n.text("app.name", fallback: "SpacePin"))) {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct PinMenuSection: View {
    @ObservedObject var item: PinItem
    let coordinator: AppCoordinator

    var body: some View {
        Menu(item.displayTitle) {
            Button(L10n.text("action.show", fallback: "Show")) {
                coordinator.bringToFront(id: item.id)
            }

            Button(L10n.text("action.duplicate", fallback: "Duplicate")) {
                coordinator.duplicatePin(id: item.id)
            }

            Button(item.record.locked
                ? L10n.text("action.unlock", fallback: "Unlock")
                : L10n.text("action.lock", fallback: "Lock")) {
                item.setLocked(!item.record.locked)
            }

            Button(item.record.clickThrough
                ? L10n.text("action.disable_click_through", fallback: "Disable Click-through")
                : L10n.text("action.enable_click_through", fallback: "Enable Click-through")) {
                item.setClickThrough(!item.record.clickThrough)
            }

            if item.record.kind == .note {
                Menu(L10n.text("label.color", fallback: "Color")) {
                    ForEach(NoteColorPreset.allCases, id: \.self) { preset in
                        Button {
                            item.setNoteColorPreset(preset)
                        } label: {
                            HStack {
                                Image(systemName: item.record.noteColorPreset == preset ? "checkmark.circle.fill" : "circle.fill")
                                Text(L10n.noteColorName(preset))
                            }
                        }
                    }
                }
            }

            Button(L10n.text("action.delete", fallback: "Delete"), role: .destructive) {
                coordinator.deletePin(id: item.id)
            }
        }
        .id(item.record.updatedAt)
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
