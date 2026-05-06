import CoreGraphics
import Foundation
import SpacePinCore

@MainActor
final class PinItem: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var record: PinRecord

    var onChange: ((PinRecord) -> Void)?

    init(record: PinRecord) {
        id = record.id
        self.record = record
    }

    var displayTitle: String {
        record.localizedDisplayTitle
    }

    var notePreview: String {
        let flattened = record.noteText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return flattened.isEmpty ? L10n.text("label.empty_note", fallback: "Empty note") : flattened
    }

    func updateFrameFromWindow(_ frame: CGRect) {
        let integralFrame = PinFrame(frame.integral)

        guard
            integralFrame != record.frame ||
            (!record.isCollapsed && (
                record.expandedWidth != integralFrame.width ||
                record.expandedHeight != integralFrame.height
            ))
        else {
            return
        }

        mutate { record in
            record.frame = integralFrame
            if !record.isCollapsed {
                record.expandedWidth = integralFrame.width
                record.expandedHeight = integralFrame.height
            }
        }
    }

    func updateCollapsedFrameFromResize(_ frame: CGRect) {
        let currentFrame = record.frame.cgRect
        let normalizedFrame = CGRect(
            x: frame.origin.x.rounded(),
            y: currentFrame.origin.y,
            width: max(PinPanel.collapsedMinimumWidth, frame.width.rounded()),
            height: currentFrame.height
        )
        let pinFrame = PinFrame(normalizedFrame)

        guard pinFrame != record.frame else {
            return
        }

        mutate { record in
            record.frame = pinFrame
        }
    }

    func updateNoteText(_ text: String) {
        guard record.noteText != text else {
            return
        }

        mutate { record in
            record.noteText = text
        }
    }

    func setTitle(_ title: String) {
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = resolvedTitle

        guard record.title != nextTitle else {
            return
        }

        mutate { record in
            record.title = nextTitle
        }
    }

    func setFrameColorPreset(_ preset: NoteColorPreset) {
        switch record.kind {
        case .note:
            guard record.noteColorPreset != preset else {
                return
            }

            mutate { record in
                record.noteColorPreset = preset
            }
        case .image:
            guard record.imageFrameColorPreset != preset else {
                return
            }

            mutate { record in
                record.imageFrameColorPreset = preset
            }
        }
    }

    func setHeaderIconSymbolName(_ symbolName: String?) {
        let normalizedSymbolName = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextSymbolName: String?
        if let normalizedSymbolName, !normalizedSymbolName.isEmpty {
            let defaultSymbolName = PinRecord.defaultHeaderIconSymbolName(for: record.kind)
            nextSymbolName = normalizedSymbolName == defaultSymbolName ? nil : normalizedSymbolName
        } else {
            nextSymbolName = nil
        }

        guard record.iconSymbolName != nextSymbolName || record.headerIconMode != .symbol else {
            return
        }

        mutate { record in
            record.headerIconMode = .symbol
            record.iconSymbolName = nextSymbolName
        }
    }

    func setHeaderIconToTitleInitial() {
        guard record.headerIconMode != .titleInitial else {
            return
        }

        mutate { record in
            record.headerIconMode = .titleInitial
        }
    }

    func setNoteFontSize(_ size: Double) {
        let clampedSize = min(max(size, 11), 32)

        guard abs(record.noteFontSize - clampedSize) > 0.01 else {
            return
        }

        mutate { record in
            record.noteFontSize = clampedSize
        }
    }

    func applyCollapsedState(_ collapsed: Bool, frame: CGRect, expandedSize: CGSize?) {
        let integralFrame = PinFrame(frame.integral)
        let normalizedExpandedWidth = expandedSize.map { Double($0.width) }
        let normalizedExpandedHeight = expandedSize.map { Double($0.height) }

        guard
            record.isCollapsed != collapsed ||
            record.frame != integralFrame ||
            record.expandedWidth != normalizedExpandedWidth ||
            record.expandedHeight != normalizedExpandedHeight
        else {
            return
        }

        mutate { record in
            record.isCollapsed = collapsed
            record.frame = integralFrame
            if let normalizedExpandedWidth {
                record.expandedWidth = normalizedExpandedWidth
            }
            if let normalizedExpandedHeight {
                record.expandedHeight = normalizedExpandedHeight
            }
        }
    }

    func setDockState(isDocked: Bool, order: Int?) {
        guard record.isDocked != isDocked || record.dockOrder != order else {
            return
        }

        mutate { record in
            record.isDocked = isDocked
            record.dockOrder = order
        }
    }

    func setInventoryOrder(_ order: Int?) {
        guard record.inventoryOrder != order else {
            return
        }

        mutate { record in
            record.inventoryOrder = order
        }
    }

    func updateOpacity(_ opacity: Double) {
        let clampedOpacity = min(max(opacity, 0.25), 1.0)

        guard abs(record.opacity - clampedOpacity) > 0.01 else {
            return
        }

        mutate { record in
            record.opacity = clampedOpacity
        }
    }

    func setClickThrough(_ enabled: Bool) {
        guard record.clickThrough != enabled else {
            return
        }

        mutate { record in
            record.clickThrough = enabled
        }
    }

    func setLocked(_ enabled: Bool) {
        guard record.locked != enabled else {
            return
        }

        mutate { record in
            record.locked = enabled
        }
    }

    private func mutate(_ update: (inout PinRecord) -> Void) {
        var updated = record
        update(&updated)
        updated.updatedAt = Date()
        record = updated
        onChange?(updated)
    }
}
