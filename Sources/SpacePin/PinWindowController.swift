import AppKit
import Combine
import SpacePinCore

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private let item: PinItem
    private weak var coordinator: AppCoordinator?
    private var recordCancellable: AnyCancellable?
    private var isApplyingRecord = false
    private var shouldAllowClose = false

    init(item: PinItem, coordinator: AppCoordinator) {
        self.item = item
        self.coordinator = coordinator

        let panel = PinPanel(frame: item.record.frame.cgRect, locked: item.record.locked)
        let contentViewController = PinContentViewController(
            item: item,
            initialContentSize: item.record.frame.cgRect.size,
            imageURL: { [weak coordinator] in
                coordinator?.imageURL(for: item.record)
            },
            onDelete: { [weak coordinator] in
                coordinator?.deletePin(id: item.id)
            },
            onDuplicate: { [weak coordinator] in
                coordinator?.duplicatePin(id: item.id)
            }
        )
        _ = contentViewController.view
        super.init(window: panel)

        contentViewController.onToggleCollapse = { [weak self] in
            self?.toggleCollapsedState()
        }
        contentViewController.onCollapsedResizeCommitted = { [weak self] frame in
            self?.commitCollapsedResize(frame)
        }
        panel.delegate = self
        panel.contentViewController = contentViewController

        apply(record: item.record, forceFrame: true)

        recordCancellable = item.$record.sink { [weak self] record in
            self?.apply(record: record, forceFrame: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPinWindow() {
        guard let window else {
            return
        }

        if item.record.clickThrough {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func closeWindowProgrammatically() {
        shouldAllowClose = true
        window?.close()
    }

    func windowDidMove(_ notification: Notification) {
        synchronizeWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        synchronizeWindowFrame()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard item.record.isCollapsed else {
            return frameSize
        }

        return NSSize(
            width: max(PinPanel.collapsedMinimumWidth, frameSize.width),
            height: PinPanel.collapsedHeight
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        (window?.contentViewController as? PinContentViewController)?.handleWindowResignKey()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if shouldAllowClose {
            return true
        }

        coordinator?.deletePin(id: item.id)
        return false
    }

    private func synchronizeWindowFrame() {
        guard !isApplyingRecord, let window else {
            return
        }

        guard !item.record.isCollapsed else {
            return
        }

        item.updateFrameFromWindow(window.frame)
    }

    private func toggleCollapsedState() {
        guard let window else {
            return
        }

        let currentFrame = window.frame

        if item.record.isCollapsed {
            let targetHeight = CGFloat(item.record.expandedHeight ?? 220)
            let expandedFrame = CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - targetHeight,
                width: currentFrame.width,
                height: targetHeight
            )
            item.applyCollapsedState(false, frame: expandedFrame, expandedHeight: targetHeight)
        } else {
            let expandedHeight = max(currentFrame.height, PinPanel.collapsedHeight)
            let collapsedFrame = CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - PinPanel.collapsedHeight,
                width: currentFrame.width,
                height: PinPanel.collapsedHeight
            )
            item.applyCollapsedState(true, frame: collapsedFrame, expandedHeight: expandedHeight)
        }
    }

    private func commitCollapsedResize(_ frame: CGRect) {
        item.updateCollapsedFrameFromResize(frame)
    }

    private func apply(record: PinRecord, forceFrame: Bool) {
        guard let panel = window as? PinPanel else {
            return
        }

        isApplyingRecord = true
        defer { isApplyingRecord = false }

        panel.applyBehavior(for: record)

        let targetFrame = record.frame.cgRect
        if forceFrame || !panel.frame.isAlmostEqual(to: targetFrame) {
            panel.setFrame(targetFrame, display: true)
        }
    }
}

private extension CGRect {
    func isAlmostEqual(to other: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
        abs(origin.y - other.origin.y) <= tolerance &&
        abs(size.width - other.size.width) <= tolerance &&
        abs(size.height - other.size.height) <= tolerance
    }
}
