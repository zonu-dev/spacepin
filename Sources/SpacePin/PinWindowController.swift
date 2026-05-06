import AppKit
import Combine
import QuartzCore
import SpacePinCore

@MainActor
final class PinWindowController: NSWindowController, NSWindowDelegate {
    private static let collapseAnimationDuration: TimeInterval = 0.18
    private static let dockTransitionDuration: TimeInterval = 0.24

    private let item: PinItem
    private weak var coordinator: AppCoordinator?
    private weak var pinContentViewController: PinContentViewController?
    private let dockTransitionWindowController = DockTransitionWindowController()
    private var recordCancellable: AnyCancellable?
    private var screenParametersCancellable: AnyCancellable?
    private var isApplyingRecord = false
    private var isAdjustingWindowFrame = false
    private var pendingCollapseAnimation = false
    private var pendingNormalizedFrameAfterAnimation: CGRect?
    private var verticalZoomRestoreFrame: CGRect?
    private var shouldAllowClose = false
    private var isCompactDragging = false

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
            }
        )
        _ = contentViewController.view
        super.init(window: panel)
        self.pinContentViewController = contentViewController

        contentViewController.onToggleCollapse = { [weak self] in
            self?.toggleCollapsedState()
        }
        contentViewController.onToggleVerticalZoom = { [weak self] in
            self?.toggleVerticalZoom()
        }
        contentViewController.onCollapsedResizeCommitted = { [weak self] frame in
            self?.commitCollapsedResize(frame)
        }
        contentViewController.onCompactDragEnded = { [weak self] dropPoint in
            self?.handleCompactDragEnded(dropPoint)
        }
        contentViewController.onCompactDragMoved = { [weak self] point in
            self?.handleCompactDragMoved(point)
        }
        contentViewController.onCompactDragStateChanged = { [weak self] isDragging in
            self?.handleCompactDragStateChanged(isDragging)
        }
        panel.delegate = self
        panel.contentViewController = contentViewController

        apply(record: item.record, forceFrame: true)

        recordCancellable = item.$record.sink { [weak self] record in
            self?.apply(record: record, forceFrame: false)
        }
        screenParametersCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.synchronizeWindowFrame()
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPinWindow(fromDockFrame dockFrame: CGRect? = nil) {
        guard let window else {
            return
        }

        if let dockFrame {
            let targetFrame = window.frame
            let sourceFrame = dockTransitionSourceFrame(for: targetFrame, dockIconFrame: dockFrame)
            if let snapshotImage = windowSnapshotImage(for: window) {
                dockTransitionWindowController.show(
                    image: snapshotImage,
                    frame: sourceFrame,
                    alpha: 0.96
                )
                animateDockTransition(
                    on: dockTransitionWindowController,
                    to: targetFrame,
                    finalAlpha: CGFloat(item.record.opacity)
                ) { [weak self] in
                    self?.dockTransitionWindowController.hide()
                    self?.presentWindow(window)
                }
                return
            }
        }

        presentWindow(window)
    }

    func closeWindowProgrammatically() {
        shouldAllowClose = true
        window?.orderOut(nil)
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

        return NSSize(width: PinPanel.compactNoteDiameter, height: PinPanel.compactNoteDiameter)
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
        guard !isApplyingRecord, !isAdjustingWindowFrame, let window else {
            return
        }

        let visibleFrame = constrainedFrameKeepingHeaderVisible(for: window.frame, record: item.record)
        if !window.frame.isAlmostEqual(to: visibleFrame) {
            setWindowFrame(visibleFrame, on: window)
        }

        item.updateFrameFromWindow(visibleFrame)
    }

    private func toggleCollapsedState() {
        guard let window else {
            return
        }

        let currentFrame = window.frame

        if item.record.isCollapsed {
            verticalZoomRestoreFrame = nil
            pinContentViewController?.setVerticalZoomed(false)
            pendingCollapseAnimation = true
            let minimumExpandedSize = minimumExpandedSize(for: item.record.kind)
            let targetWidth = max(CGFloat(item.record.expandedWidth ?? currentFrame.width), minimumExpandedSize.width)
            let targetHeight = max(CGFloat(item.record.expandedHeight ?? currentFrame.height), minimumExpandedSize.height)
            let expandedFrame = CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - targetHeight,
                width: targetWidth,
                height: targetHeight
            )
            item.applyCollapsedState(
                false,
                frame: expandedFrame,
                expandedSize: CGSize(width: targetWidth, height: targetHeight)
            )
        } else {
            verticalZoomRestoreFrame = nil
            pinContentViewController?.setVerticalZoomed(false)
            let expandedSize = CGSize(width: currentFrame.width, height: currentFrame.height)
            coordinator?.preparePinForInventoryClose(id: item.id)

            if let dockFrame = coordinator?.dockIconFrame(
                for: item.id,
                preferredPoint: CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            ) {
                let destinationFrame = dockTransitionSourceFrame(for: currentFrame, dockIconFrame: dockFrame)
                if let snapshotImage = windowSnapshotImage(for: window) {
                    dockTransitionWindowController.show(
                        image: snapshotImage,
                        frame: currentFrame,
                        alpha: CGFloat(item.record.opacity)
                    )
                    window.orderOut(nil)
                    animateDockTransition(
                        on: dockTransitionWindowController,
                        to: destinationFrame,
                        finalAlpha: 0.92
                    ) { [weak self] in
                        guard let self else {
                            return
                        }

                        self.dockTransitionWindowController.hide()
                        self.coordinator?.finishInventoryClose(
                            id: self.item.id,
                            frame: currentFrame,
                            expandedSize: expandedSize
                        )
                    }
                    return
                }
            }

            coordinator?.finishInventoryClose(id: item.id, frame: currentFrame, expandedSize: expandedSize)
        }
    }

    private func toggleVerticalZoom() {
        guard let window, !item.record.isCollapsed else {
            return
        }

        let currentFrame = window.frame
        let targetFrame: CGRect
        let isVerticalZoomed: Bool
        if let restoreFrame = verticalZoomRestoreFrame {
            verticalZoomRestoreFrame = nil
            targetFrame = constrainedFrameKeepingHeaderVisible(for: restoreFrame, record: item.record)
            isVerticalZoomed = false
        } else {
            guard let visibleFrame = preferredVisibleFrame(for: currentFrame, record: item.record) else {
                return
            }

            verticalZoomRestoreFrame = currentFrame
            isVerticalZoomed = true
            targetFrame = constrainedFrameKeepingHeaderVisible(
                for: CGRect(
                    x: currentFrame.minX,
                    y: visibleFrame.minY,
                    width: currentFrame.width,
                    height: visibleFrame.height
                ),
                record: item.record
            )
        }
        pinContentViewController?.setVerticalZoomed(isVerticalZoomed)

        setWindowFrame(targetFrame, on: window, animated: true) { [weak self] in
            self?.item.updateFrameFromWindow(targetFrame)
        }
    }

    private func commitCollapsedResize(_ frame: CGRect) {
        item.updateCollapsedFrameFromResize(frame)
    }

    private func handleCompactDragEnded(_ dropPoint: CGPoint) {
        coordinator?.handleCollapsedPinDragEnded(id: item.id, dropPoint: dropPoint)
    }

    private func handleCompactDragMoved(_ point: CGPoint) {
        coordinator?.updateDockInteractionDrag(pinID: item.id, point: point)
    }

    private func handleCompactDragStateChanged(_ isDragging: Bool) {
        guard let panel = window as? PinPanel else {
            return
        }

        if isDragging {
            isCompactDragging = true
            coordinator?.beginDockInteractionDrag()
            panel.level = .spacePinDragOverlay
            panel.orderFrontRegardless()
        } else {
            isCompactDragging = false
            coordinator?.clearDockInteractionDrag()
            coordinator?.endDockInteractionDrag()
            if item.record.isDockedPin && item.record.isCollapsed {
                panel.orderOut(nil)
                return
            }
            panel.applyBehavior(for: item.record)
        }
    }

    private func apply(record: PinRecord, forceFrame: Bool) {
        guard let panel = window as? PinPanel else {
            return
        }

        isApplyingRecord = true

        if record.isDockedPin && record.isCollapsed {
            verticalZoomRestoreFrame = nil
            pinContentViewController?.setVerticalZoomed(false)
            panel.orderOut(nil)
            isApplyingRecord = false
            return
        }

        panel.applyBehavior(for: record)
        if record.isCollapsed {
            verticalZoomRestoreFrame = nil
            pinContentViewController?.setVerticalZoomed(false)
        }
        if isCompactDragging {
            panel.level = .spacePinDragOverlay
            panel.orderFrontRegardless()
        }

        let originalFrame = record.frame.cgRect
        let targetFrame = constrainedFrameKeepingHeaderVisible(for: originalFrame, record: record)
        let shouldPersistNormalizedFrame = !originalFrame.isAlmostEqual(to: targetFrame)
        let shouldAnimateFrame = pendingCollapseAnimation && !forceFrame && panel.isVisible
        let shouldUpdateWindowFrame = forceFrame || !panel.frame.isAlmostEqual(to: targetFrame)
        pendingCollapseAnimation = false
        pendingNormalizedFrameAfterAnimation = (
            shouldAnimateFrame && shouldPersistNormalizedFrame && shouldUpdateWindowFrame
        ) ? targetFrame : nil
        if shouldUpdateWindowFrame {
            setWindowFrame(targetFrame, on: panel, animated: shouldAnimateFrame)
        }

        isApplyingRecord = false

        if shouldPersistNormalizedFrame {
            if !shouldAnimateFrame {
                item.updateFrameFromWindow(targetFrame)
            }
        }
    }

    private func minimumExpandedSize(for kind: PinKind) -> CGSize {
        switch kind {
        case .note:
            return CGSize(width: 180, height: 120)
        case .image:
            return CGSize(width: 140, height: 90)
        }
    }

    private func constrainedFrameKeepingHeaderVisible(for frame: CGRect, record: PinRecord) -> CGRect {
        let normalizedFrame = normalizedFrame(for: frame, record: record)

        guard let visibleFrame = preferredVisibleFrame(for: normalizedFrame, record: record) else {
            return normalizedFrame.integral
        }

        let headerHeight = headerHeight(for: record, frame: normalizedFrame)
        let requiredVisibleHeaderHeight = min(headerHeight, visibleFrame.height)
        let requiredVisibleHeaderWidth = min(
            minimumVisibleHeaderWidth(for: record, frame: normalizedFrame),
            visibleFrame.width,
            normalizedFrame.width
        )

        var constrainedFrame = normalizedFrame
        let minimumX = visibleFrame.minX + requiredVisibleHeaderWidth - constrainedFrame.width
        let maximumX = visibleFrame.maxX - requiredVisibleHeaderWidth
        constrainedFrame.origin.x = min(max(constrainedFrame.minX, minimumX), maximumX)

        let minimumTopY = visibleFrame.minY + requiredVisibleHeaderHeight
        let maximumTopY = visibleFrame.maxY
        let constrainedTopY = min(max(constrainedFrame.maxY, minimumTopY), maximumTopY)
        constrainedFrame.origin.y = constrainedTopY - constrainedFrame.height

        return constrainedFrame.integral
    }

    private func normalizedFrame(for frame: CGRect, record: PinRecord) -> CGRect {
        guard record.isCollapsed else {
            return frame
        }

        switch record.kind {
        case .note:
            return CGRect(
                x: frame.minX,
                y: frame.maxY - PinPanel.compactNoteDiameter,
                width: PinPanel.compactNoteDiameter,
                height: PinPanel.compactNoteDiameter
            )
        case .image:
            return CGRect(
                x: frame.minX,
                y: frame.maxY - PinPanel.compactNoteDiameter,
                width: PinPanel.compactNoteDiameter,
                height: PinPanel.compactNoteDiameter
            )
        }
    }

    private func preferredVisibleFrame(for frame: CGRect, record: PinRecord) -> CGRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        let headerFrame = headerFrame(for: frame, record: record)

        if let screen = screenWithLargestIntersection(for: headerFrame, in: screens) {
            return screen.visibleFrame
        }

        if let screen = screenWithLargestIntersection(for: frame, in: screens) {
            return screen.visibleFrame
        }

        let headerCenter = CGPoint(x: headerFrame.midX, y: headerFrame.midY)
        return screens.min { lhs, rhs in
            lhs.visibleFrame.distanceSquared(to: headerCenter) < rhs.visibleFrame.distanceSquared(to: headerCenter)
        }?.visibleFrame
    }

    private func screenWithLargestIntersection(for frame: CGRect, in screens: [NSScreen]) -> NSScreen? {
        let scoredScreens = screens.map { screen in
            (screen: screen, area: screen.visibleFrame.intersection(frame).area)
        }

        guard let bestScreen = scoredScreens.max(by: { $0.area < $1.area }), bestScreen.area > 0 else {
            return nil
        }

        return bestScreen.screen
    }

    private func headerFrame(for frame: CGRect, record: PinRecord) -> CGRect {
        let headerHeight = headerHeight(for: record, frame: frame)
        return CGRect(
            x: frame.minX,
            y: frame.maxY - headerHeight,
            width: frame.width,
            height: headerHeight
        )
    }

    private func headerHeight(for record: PinRecord, frame: CGRect) -> CGFloat {
        if record.isCollapsed {
            return min(frame.height, PinPanel.compactNoteDiameter)
        }

        return min(frame.height, PinPanel.collapsedHeight)
    }

    private func minimumVisibleHeaderWidth(for record: PinRecord, frame: CGRect) -> CGFloat {
        if record.isCollapsed {
            return min(frame.width, PinPanel.compactNoteDiameter)
        }

        return min(frame.width, 140)
    }

    private func setWindowFrame(
        _ frame: CGRect,
        on window: NSWindow,
        animated: Bool = false,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        isAdjustingWindowFrame = true
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.collapseAnimationDuration
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.isAdjustingWindowFrame = false
                    if let self, let normalizedFrame = self.pendingNormalizedFrameAfterAnimation {
                        self.pendingNormalizedFrameAfterAnimation = nil
                        self.item.updateFrameFromWindow(normalizedFrame)
                    }

                    completion?()
                }
            }
        } else {
            window.setFrame(frame, display: true)
            isAdjustingWindowFrame = false
            completion?()
        }
    }

    private func animateDockTransition(
        on controller: DockTransitionWindowController,
        to frame: CGRect,
        finalAlpha: CGFloat,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        controller.animate(
            to: frame,
            alpha: finalAlpha,
            duration: Self.dockTransitionDuration,
            completion: completion
        )
    }

    private func presentWindow(_ window: NSWindow) {
        window.alphaValue = CGFloat(item.record.opacity)
        if item.record.clickThrough {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func windowSnapshotImage(for window: NSWindow) -> NSImage? {
        guard let contentView = window.contentView else {
            return nil
        }

        contentView.layoutSubtreeIfNeeded()
        let bounds = contentView.bounds.integral
        guard bounds.width > 1, bounds.height > 1,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func dockTransitionSourceFrame(for targetFrame: CGRect, dockIconFrame: CGRect) -> CGRect {
        let scale = min(
            dockIconFrame.width / targetFrame.width,
            dockIconFrame.height / targetFrame.height
        )
        let sourceSize = CGSize(
            width: max(1, targetFrame.width * scale),
            height: max(1, targetFrame.height * scale)
        )
        return CGRect(
            x: dockIconFrame.midX - (sourceSize.width / 2),
            y: dockIconFrame.midY - (sourceSize.height / 2),
            width: sourceSize.width,
            height: sourceSize.height
        ).integral
    }
}

@MainActor
private final class DockTransitionWindowController: NSWindowController {
    private let imageView = NSImageView()

    init() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .spacePinDragOverlay
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true

        panel.contentView = imageView
        super.init(window: panel)
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(image: NSImage, frame: CGRect, alpha: CGFloat) {
        guard let window else {
            return
        }

        imageView.image = image
        window.alphaValue = alpha
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func animate(
        to frame: CGRect,
        alpha: CGFloat,
        duration: TimeInterval,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard let window else {
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
        } completionHandler: {
            Task { @MainActor in
                completion?()
            }
        }
    }

    func hide() {
        imageView.image = nil
        window?.orderOut(nil)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard width > 0, height > 0 else {
            return 0
        }

        return width * height
    }

    func distanceSquared(to point: CGPoint) -> CGFloat {
        let deltaX: CGFloat
        if point.x < minX {
            deltaX = minX - point.x
        } else if point.x > maxX {
            deltaX = point.x - maxX
        } else {
            deltaX = 0
        }

        let deltaY: CGFloat
        if point.y < minY {
            deltaY = minY - point.y
        } else if point.y > maxY {
            deltaY = point.y - maxY
        } else {
            deltaY = 0
        }

        return (deltaX * deltaX) + (deltaY * deltaY)
    }

    func isAlmostEqual(to other: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance &&
        abs(origin.y - other.origin.y) <= tolerance &&
        abs(size.width - other.size.width) <= tolerance &&
        abs(size.height - other.size.height) <= tolerance
    }
}
