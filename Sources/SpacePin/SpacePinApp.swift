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
        MenuBarExtra("SpacePin", systemImage: "pin.circle.fill") {
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
        Button("Open Manager") {
            coordinator.showManagerWindow()
        }
        .keyboardShortcut("0", modifiers: [.command, .option])

        Button("New Note Pin") {
            coordinator.createNotePin()
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button("Import Image…") {
            coordinator.presentImageImporter()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])

        if !coordinator.pins.isEmpty {
            Button("Bring All Pins Forward") {
                coordinator.bringAllPinsToFront()
            }

            Divider()

            ForEach(coordinator.pins) { item in
                PinMenuSection(item: item, coordinator: coordinator)
            }
        } else {
            Divider()

            Text("No active pins")
                .foregroundStyle(.secondary)
        }

        if let lastErrorMessage = coordinator.lastErrorMessage {
            Divider()
            Text(lastErrorMessage)
                .foregroundStyle(.red)
        }

        Divider()

        Button("Quit SpacePin") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct PinMenuSection: View {
    @ObservedObject var item: PinItem
    let coordinator: AppCoordinator

    var body: some View {
        Menu(item.displayTitle) {
            Button("Show") {
                coordinator.bringToFront(id: item.id)
            }

            Button("Duplicate") {
                coordinator.duplicatePin(id: item.id)
            }

            Button(item.record.locked ? "Unlock" : "Lock") {
                item.setLocked(!item.record.locked)
            }

            Button(item.record.clickThrough ? "Disable Click-through" : "Enable Click-through") {
                item.setClickThrough(!item.record.clickThrough)
            }

            if item.record.kind == .note {
                Menu("Color") {
                    ForEach(NoteColorPreset.allCases, id: \.self) { preset in
                        Button {
                            item.setNoteColorPreset(preset)
                        } label: {
                            HStack {
                                Image(systemName: item.record.noteColorPreset == preset ? "checkmark.circle.fill" : "circle.fill")
                                Text(preset.displayName)
                            }
                        }
                    }
                }
            }

            Button("Delete", role: .destructive) {
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
            Text("SpacePin")
                .font(.title2.bold())

            Text("Pins are stored in ~/Library/Application Support/SpacePin.")
                .foregroundStyle(.secondary)

            Button("Open Manager") {
                coordinator.showManagerWindow()
            }
        }
        .frame(width: 360)
        .padding(24)
    }
}
