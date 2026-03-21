import SpacePinCore
import SwiftUI
import UniformTypeIdentifiers

struct ManagerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SpacePin")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                Text("Note pins and image pins stay in their own floating panels across Spaces.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    coordinator.createNotePin()
                } label: {
                    Label("New Note Pin", systemImage: "note.text")
                }

                Button {
                    coordinator.presentImageImporter()
                } label: {
                    Label("Import Image", systemImage: "photo")
                }

                Spacer()

                Text("\(coordinator.pins.count) active")
                    .foregroundStyle(.secondary)
            }

            DropZoneView(isTargeted: isDropTarget)
                .onDrop(
                    of: [UTType.fileURL.identifier],
                    isTargeted: $isDropTarget,
                    perform: { providers in
                        coordinator.handleDroppedProviders(providers)
                    }
                )

            if let lastErrorMessage = coordinator.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if coordinator.pins.isEmpty {
                EmptyStateView()
            } else {
                List {
                    ForEach(coordinator.pins) { item in
                        PinListRow(item: item, coordinator: coordinator)
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 500)
    }
}

private struct DropZoneView: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 8])
                    )
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Drop image files here")
                            .font(.headline)

                        Text("PNG, JPEG, GIF, HEIC and other formats supported by AppKit can be imported.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            .frame(height: 96)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No pins yet")
                .font(.title3.bold())

            Text("Create a note pin or import an image to open the first floating panel.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct PinListRow: View {
    @ObservedObject var item: PinItem
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.record.kind == .note ? "note.text" : "photo")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        item.record.kind == .note
                            ? item.record.noteColorPreset.swiftUIColor.opacity(0.22)
                            : Color.accentColor.opacity(0.12)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Text(item.record.kind == .note ? item.notePreview : item.record.sourceDisplayName ?? "Stored image")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button("Show") {
                    coordinator.bringToFront(id: item.id)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 18) {
                Toggle(
                    "Lock",
                    isOn: Binding(get: {
                        item.record.locked
                    }, set: { newValue in
                        item.setLocked(newValue)
                    })
                )
                .toggleStyle(.switch)

                Toggle(
                    "Click-through",
                    isOn: Binding(get: {
                        item.record.clickThrough
                    }, set: { newValue in
                        item.setClickThrough(newValue)
                    })
                )
                .toggleStyle(.switch)
            }

            if item.record.kind == .note {
                HStack(spacing: 12) {
                    Text("Color")
                        .foregroundStyle(.secondary)

                    Picker(
                        "Color",
                        selection: Binding(get: {
                            item.record.noteColorPreset
                        }, set: { newValue in
                            item.setNoteColorPreset(newValue)
                        })
                    ) {
                        ForEach(NoteColorPreset.allCases, id: \.self) { preset in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(preset.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                Text(preset.displayName)
                            }
                            .tag(preset)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                HStack(spacing: 12) {
                    Text("Font")
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(get: {
                            item.record.noteFontSize
                        }, set: { newValue in
                            item.setNoteFontSize(newValue)
                        }),
                        in: 11 ... 32,
                        step: 1
                    )

                    Text("\(Int(item.record.noteFontSize))pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }

            HStack(spacing: 12) {
                Text("Opacity")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(get: {
                        item.record.opacity
                    }, set: { newValue in
                        item.updateOpacity(newValue)
                    }),
                    in: 0.25 ... 1.0
                )

                Text("\(Int(item.record.opacity * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Duplicate") {
                    coordinator.duplicatePin(id: item.id)
                }

                Button("Delete", role: .destructive) {
                    coordinator.deletePin(id: item.id)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }
}
