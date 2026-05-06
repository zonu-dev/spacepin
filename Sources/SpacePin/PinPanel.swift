import AppKit
import SpacePinCore

extension NSWindow.Level {
    static let spacePinDragOverlay = NSWindow.Level(
        rawValue: max(
            Int(CGWindowLevelForKey(.draggingWindow)),
            NSWindow.Level.screenSaver.rawValue + 1
        )
    )
}

final class PinPanel: NSPanel {
    static let collapsedHeight: CGFloat = 34
    static let collapsedMinimumWidth: CGFloat = 140
    static let compactNoteDiameter: CGFloat = 34

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(frame: CGRect, locked: Bool) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        applyInteractionState(locked: locked, isCollapsed: false)
    }

    func applyBehavior(for record: PinRecord) {
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        level = .floating
        alphaValue = record.opacity
        ignoresMouseEvents = record.clickThrough
        contentMinSize = minimumContentSize(for: record.kind, isCollapsed: record.isCollapsed)
        contentMaxSize = maximumContentSize(for: record.kind, isCollapsed: record.isCollapsed)
        applyInteractionState(locked: record.locked, isCollapsed: record.isCollapsed)
    }

    private func applyInteractionState(locked: Bool, isCollapsed: Bool) {
        if locked || isCollapsed {
            styleMask.remove(.resizable)
        } else {
            styleMask.insert(.resizable)
        }

        isMovable = !locked
        isMovableByWindowBackground = false
    }

    private func minimumContentSize(for kind: PinKind, isCollapsed: Bool) -> NSSize {
        if isCollapsed {
            switch kind {
            case .note:
                return NSSize(width: Self.compactNoteDiameter, height: Self.compactNoteDiameter)
            case .image:
                return NSSize(width: Self.compactNoteDiameter, height: Self.compactNoteDiameter)
            }
        }

        switch kind {
        case .note:
            return NSSize(width: 180, height: 120)
        case .image:
            return NSSize(width: 140, height: 90)
        }
    }

    private func maximumContentSize(for kind: PinKind, isCollapsed: Bool) -> NSSize {
        if isCollapsed {
            switch kind {
            case .note:
                return NSSize(width: Self.compactNoteDiameter, height: Self.compactNoteDiameter)
            case .image:
                return NSSize(width: Self.compactNoteDiameter, height: Self.compactNoteDiameter)
            }
        }

        return NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
}
