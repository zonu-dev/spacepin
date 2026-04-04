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

        guard integralFrame != record.frame || (!record.isCollapsed && record.expandedHeight != integralFrame.height) else {
            return
        }

        mutate { record in
            record.frame = integralFrame
            if !record.isCollapsed {
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

    func setNoteColorPreset(_ preset: NoteColorPreset) {
        guard record.noteColorPreset != preset else {
            return
        }

        mutate { record in
            record.noteColorPreset = preset
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

    func applyCollapsedState(_ collapsed: Bool, frame: CGRect, expandedHeight: CGFloat?) {
        let integralFrame = PinFrame(frame.integral)
        let normalizedExpandedHeight = expandedHeight.map { Double($0) }

        guard
            record.isCollapsed != collapsed ||
            record.frame != integralFrame ||
            record.expandedHeight != normalizedExpandedHeight
        else {
            return
        }

        mutate { record in
            record.isCollapsed = collapsed
            record.frame = integralFrame
            if let normalizedExpandedHeight {
                record.expandedHeight = normalizedExpandedHeight
            }
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
