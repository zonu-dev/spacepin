import AppKit
import Combine
import Foundation
import SpacePinCore
import UniformTypeIdentifiers

@MainActor
protocol DockDropTarget: AnyObject {
    func containsDockDropPoint(_ point: CGPoint) -> Bool
    func dockInsertionIndex(for point: CGPoint) -> Int?
    func currentDockDragInsertionIndex(for pinID: UUID) -> Int?
    func updateDockDrag(pinID: UUID?, point: CGPoint?)
    func dockIconFrame(for pinID: UUID, preferredPoint: CGPoint?) -> CGRect?
}

@MainActor
final class AppCoordinator: ObservableObject {
    private static let defaultInventorySlotLimit = 40

    @Published private(set) var pins: [PinItem] = []
    @Published private(set) var isDockInteractionDragging = false
    @Published var lastErrorMessage: String?

    private let repository: PinRepository
    private let imageStore: ImageAssetStore
    private var windowControllers: [UUID: PinWindowController] = [:]
    private lazy var managerWindowController = ManagerWindowController(coordinator: self)
    private var hasStarted = false
    private var persistWorkItem: DispatchWorkItem?
    private var terminationObserver: NSObjectProtocol?
    private weak var dockDropTarget: DockDropTarget?
    private var dockInteractionDragCount = 0

    var dockedPins: [PinItem] {
        pins
            .filter { $0.record.isDockedPin }
            .sorted(by: dockSortPrecedes)
    }

    func inventorySlots(limit: Int) -> [PinItem?] {
        let slotLimit = max(0, limit)
        var slots = Array<PinItem?>(repeating: nil, count: slotLimit)
        guard slotLimit > 0 else {
            return slots
        }

        var unassignedPins: [PinItem] = []
        for pin in pins {
            if let order = pin.record.inventoryOrder,
               order >= 0,
               order < slotLimit,
               slots[order] == nil {
                slots[order] = pin
            } else {
                unassignedPins.append(pin)
            }
        }

        var nextAvailableIndex = 0
        for pin in unassignedPins {
            while nextAvailableIndex < slotLimit, slots[nextAvailableIndex] != nil {
                nextAvailableIndex += 1
            }

            guard nextAvailableIndex < slotLimit else {
                break
            }

            slots[nextAvailableIndex] = pin
        }

        return slots
    }

    func inventoryIndex(for id: UUID, limit: Int) -> Int? {
        inventorySlots(limit: limit).firstIndex { item in
            item?.id == id
        }
    }

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        let storageDirectory: URL

        if let rootDirectory {
            storageDirectory = rootDirectory
        } else {
            storageDirectory = (try? SpacePinPaths.defaultRootDirectory(fileManager: fileManager))
                ?? fileManager.temporaryDirectory.appendingPathComponent("SpacePin", isDirectory: true)
        }

        repository = PinRepository(rootDirectory: storageDirectory, fileManager: fileManager)
        imageStore = ImageAssetStore(rootDirectory: storageDirectory, fileManager: fileManager)
    }

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        observeAppTermination()
        restorePins()
    }

    func setDockDropTarget(_ dockDropTarget: DockDropTarget?) {
        self.dockDropTarget = dockDropTarget
    }

    func beginDockInteractionDrag() {
        dockInteractionDragCount += 1
        isDockInteractionDragging = true
    }

    func endDockInteractionDrag() {
        dockInteractionDragCount = max(0, dockInteractionDragCount - 1)
        isDockInteractionDragging = dockInteractionDragCount > 0
    }

    func updateDockInteractionDrag(pinID: UUID, point: CGPoint) {
        dockDropTarget?.updateDockDrag(pinID: pinID, point: point)
    }

    func clearDockInteractionDrag() {
        dockDropTarget?.updateDockDrag(pinID: nil, point: nil)
    }

    func dockIconFrame(for id: UUID, preferredPoint: CGPoint? = nil) -> CGRect? {
        dockDropTarget?.dockIconFrame(for: id, preferredPoint: preferredPoint)
    }

    func createNotePin() {
        clearError()
        NSApp.activate(ignoringOtherApps: true)

        let noteFrame = defaultFrame(for: CGSize(width: 320, height: 240))
        let record = PinRecord.makeNote(frame: noteFrame, title: "", noteText: "")
        addPin(record, bringToFront: true)
    }

    func presentImageImporter() {
        clearError()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = L10n.text("error.choose_images", fallback: "Choose Images")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else {
            return
        }

        importImagePins(from: panel.urls)
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else {
            return false
        }

        clearError()

        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, error in
                guard let self else {
                    return
                }

                if let error {
                    Task { @MainActor in
                        self.lastErrorMessage = error.localizedDescription
                    }
                    return
                }

                guard let fileURL = Self.extractFileURL(from: item) else {
                    Task { @MainActor in
                        self.lastErrorMessage = L10n.text(
                            "error.dropped_item_not_file_url",
                            fallback: "Dropped item could not be resolved as a file URL."
                        )
                    }
                    return
                }

                Task { @MainActor in
                    self.importImagePins(from: [fileURL])
                }
            }
        }

        return true
    }

    func duplicatePin(id: UUID) {
        guard let pin = pins.first(where: { $0.id == id }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let duplicate = pin.record.duplicated()
        addPin(duplicate, bringToFront: true)
    }

    func deletePin(id: UUID) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedPin = pins[index]
        let controller = windowControllers.removeValue(forKey: id)
        pins.remove(at: index)
        controller?.closeWindowProgrammatically()
        if removedPin.record.isDockedPin {
            normalizeDockOrder()
        }
        persistImmediately()
    }

    func bringToFront(id: UUID) {
        guard let pin = pinItem(for: id) else {
            return
        }

        if pin.record.isDockedPin {
            openDockedPin(id: id, bringToFront: true)
            return
        }

        ensureWindowController(for: pin).showPinWindow()
    }

    func bringAllPinsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        pins.filter { !$0.record.isDockedPin || !$0.record.isCollapsed }.forEach { pin in
            ensureWindowController(for: pin).showPinWindow()
        }
    }

    func handleCollapsedPinDragEnded(id: UUID, dropPoint: CGPoint) {
        guard
            let pin = pinItem(for: id),
            pin.record.isCollapsed
        else {
            return
        }

        let dockInsertionIndex = dockDropTarget?.dockInsertionIndex(for: dropPoint)
            ?? dockDropTarget?.currentDockDragInsertionIndex(for: id)
            ?? ((dockDropTarget?.containsDockDropPoint(dropPoint) == true) ? dockedPins.count : nil)
        guard let dockInsertionIndex else {
            return
        }

        dockPin(id: id, toDockIndex: dockInsertionIndex)
    }

    func dockPin(id: UUID, toDockIndex targetIndex: Int? = nil) {
        guard let pin = pinItem(for: id), pin.record.isCollapsed else {
            return
        }

        let frame = pin.record.frame.cgRect
        let expandedSize = CGSize(
            width: CGFloat(pin.record.expandedWidth ?? frame.width),
            height: CGFloat(pin.record.expandedHeight ?? frame.height)
        )
        let collapsedFrame = CGRect(
            x: frame.minX,
            y: frame.maxY - PinPanel.compactNoteDiameter,
            width: PinPanel.compactNoteDiameter,
            height: PinPanel.compactNoteDiameter
        )
        pin.applyCollapsedState(true, frame: collapsedFrame, expandedSize: expandedSize)

        closeAndRemoveWindowController(for: id)

        var reorderedIDs = dockedPins.map(\.id).filter { $0 != id }
        let insertionIndex = max(0, min(targetIndex ?? reorderedIDs.count, reorderedIDs.count))
        reorderedIDs.insert(id, at: insertionIndex)
        applyDockOrder(for: reorderedIDs)
        refreshPinsCollection()
    }

    func undockPin(id: UUID, dropScreenPoint: CGPoint? = nil, bringToFront: Bool) {
        guard let pin = pinItem(for: id) else {
            return
        }

        let remainingDockedIDs = dockedPins.map(\.id).filter { $0 != id }
        applyDockOrder(for: remainingDockedIDs)
        pin.setDockState(isDocked: false, order: nil)

        if let dropScreenPoint {
            let currentSize = pin.record.frame.cgRect.size
            let nextFrame = CGRect(
                x: dropScreenPoint.x - (currentSize.width / 2),
                y: dropScreenPoint.y - (currentSize.height / 2),
                width: currentSize.width,
                height: currentSize.height
            )
            pin.updateFrameFromWindow(nextFrame)
        }

        refreshPinsCollection()

        let controller = ensureWindowController(for: pin)
        if bringToFront {
            controller.showPinWindow()
        } else {
            controller.showWindow(nil)
        }
    }

    func moveDockedPin(id: UUID, toDockIndex targetIndex: Int) {
        var orderedIDs = dockedPins.map(\.id)
        guard let currentIndex = orderedIDs.firstIndex(of: id) else {
            return
        }

        let clampedTargetIndex = max(0, min(targetIndex, orderedIDs.count - 1))
        guard currentIndex != clampedTargetIndex else {
            return
        }

        let movedID = orderedIDs.remove(at: currentIndex)
        orderedIDs.insert(movedID, at: clampedTargetIndex)
        applyDockOrder(for: orderedIDs)
        refreshPinsCollection()
    }

    func movePinInInventory(id: UUID, toInventoryIndex targetIndex: Int, slotCount: Int) {
        guard
            let pin = pinItem(for: id),
            targetIndex >= 0,
            targetIndex < slotCount
        else {
            return
        }

        let slots = inventorySlots(limit: slotCount)
        guard let sourceIndex = slots.firstIndex(where: { item in item?.id == id }) else {
            return
        }

        guard sourceIndex != targetIndex else {
            return
        }

        let targetPin = slots[targetIndex]
        pin.setInventoryOrder(targetIndex)
        if let targetPin, targetPin.id != id {
            targetPin.setInventoryOrder(sourceIndex)
        }
        refreshPinsCollection()
    }

    func closePresentedDockedPin(id: UUID) {
        guard pinItem(for: id)?.record.isDockedPin == true else {
            return
        }

        closeAndRemoveWindowController(for: id)
    }

    func preparePinForInventoryClose(id: UUID) {
        ensureInventoryMembership(for: id)
    }

    func finishInventoryClose(id: UUID, frame: CGRect, expandedSize: CGSize) {
        guard let pin = pinItem(for: id) else {
            return
        }

        ensureInventoryMembership(for: id)
        pin.applyCollapsedState(true, frame: frame, expandedSize: expandedSize)
        closeAndRemoveWindowController(for: id)
        refreshPinsCollection()
    }

    func showManagerWindow() {
        managerWindowController.present()
    }

    func imageURL(for record: PinRecord) -> URL? {
        guard let filename = record.imageAssetFilename else {
            return nil
        }

        return imageStore.fileURL(for: filename)
    }

    private func normalizedRestoredRecord(_ record: PinRecord) -> PinRecord {
        var normalized = record

        if normalized.isDockedPin && !normalized.isCollapsed {
            normalized.isCollapsed = true
            let frame = normalized.frame.cgRect
            normalized.expandedWidth = normalized.expandedWidth ?? frame.width
            normalized.expandedHeight = normalized.expandedHeight ?? frame.height
        }

        if normalized.isDockedPin {
            return normalized
        }

        guard normalized.isCollapsed else {
            return normalized
        }

        let frame = normalized.frame.cgRect
        guard
            abs(frame.width - PinPanel.compactNoteDiameter) > 0.5 ||
            abs(frame.height - PinPanel.compactNoteDiameter) > 0.5
        else {
            return normalized
        }

        normalized.frame = PinFrame(CGRect(
            x: frame.minX,
            y: frame.maxY - PinPanel.compactNoteDiameter,
            width: PinPanel.compactNoteDiameter,
            height: PinPanel.compactNoteDiameter
        ))
        normalized.expandedWidth = normalized.expandedWidth ?? frame.width
        normalized.expandedHeight = normalized.expandedHeight ?? frame.height
        return normalized
    }

    private func restorePins() {
        do {
            let restoredPins = try repository.load()
            restoredPins.forEach { record in
                addPin(normalizedRestoredRecord(record), bringToFront: false, shouldSchedulePersistence: false)
            }
        } catch {
            lastErrorMessage = L10n.format(
                "error.failed_restore_pins",
                fallback: "Failed to restore pins: %@",
                error.localizedDescription
            )
        }
    }

    private func importImagePins(from urls: [URL]) {
        var importedAtLeastOne = false

        for url in urls {
            do {
                guard NSImage(contentsOf: url) != nil else {
                    throw SpacePinError.unsupportedImage(url.lastPathComponent)
                }

                let importedAsset = try imageStore.importImage(at: url)
                let frame = defaultImageFrame(for: importedAsset.fileURL)
                let record = PinRecord.makeImage(
                    frame: frame,
                    imageAssetFilename: importedAsset.filename,
                    sourceDisplayName: url.lastPathComponent
                )

                addPin(record, bringToFront: true)
                importedAtLeastOne = true
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        if importedAtLeastOne {
            clearError()
        }
    }

    private func addPin(
        _ record: PinRecord,
        bringToFront: Bool,
        shouldSchedulePersistence: Bool = true
    ) {
        let pin = PinItem(record: record)
        pin.onChange = { [weak self] _ in
            self?.schedulePersistence()
        }

        pins.append(pin)
        ensureInventoryOrder(for: pin)

        if !record.isDockedPin {
            let controller = ensureWindowController(for: pin)
            if bringToFront {
                controller.showPinWindow()
            } else {
                controller.showWindow(nil)
            }
        }

        if shouldSchedulePersistence {
            schedulePersistence()
        }
    }

    private func schedulePersistence() {
        persistWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.persistImmediately()
        }

        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func persistImmediately() {
        persistWorkItem?.cancel()
        persistWorkItem = nil

        do {
            try repository.save(pins.map(\.record))
            try imageStore.removeUnreferencedAssets(keeping: referencedImageFilenames())
        } catch {
            lastErrorMessage = L10n.format(
                "error.failed_save_pins",
                fallback: "Failed to save pins: %@",
                error.localizedDescription
            )
        }
    }

    private func referencedImageFilenames() -> Set<String> {
        Set(pins.compactMap(\.record.imageAssetFilename))
    }

    private func defaultFrame(for size: CGSize) -> CGRect {
        let visibleFrame = preferredVisibleFrame()

        let offsetIndex = CGFloat(pins.count % 6)
        let x = max(visibleFrame.minX + 20, visibleFrame.maxX - size.width - 28 - (offsetIndex * 24))
        let y = max(visibleFrame.minY + 20, visibleFrame.maxY - size.height - 64 - (offsetIndex * 24))

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func defaultImageFrame(for imageURL: URL) -> CGRect {
        let headerHeight: CGFloat = 34
        let fallbackSize = CGSize(width: 320, height: 220)
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 20
        let visibleFrame = preferredVisibleFrame()
        let maximumWindowSize = CGSize(
            width: max(1, floor(visibleFrame.width / 2)),
            height: max(1, floor(visibleFrame.height / 2))
        )

        guard let image = NSImage(contentsOf: imageURL), image.size.width > 0, image.size.height > 0 else {
            return defaultFrame(for: fallbackSize)
        }

        let minWindowSize = CGSize(
            width: min(220, maximumWindowSize.width),
            height: min(160, maximumWindowSize.height)
        )
        let naturalWindowSize = CGSize(
            width: image.size.width + horizontalPadding,
            height: image.size.height + headerHeight + verticalPadding
        )

        let fittedContentSize: CGSize
        if naturalWindowSize.width <= maximumWindowSize.width, naturalWindowSize.height <= maximumWindowSize.height {
            fittedContentSize = image.size
        } else {
            let maximumContentSize = CGSize(
                width: max(80, maximumWindowSize.width - horizontalPadding),
                height: max(80, maximumWindowSize.height - headerHeight - verticalPadding)
            )
            fittedContentSize = fittedSize(for: image.size, in: maximumContentSize)
        }

        let totalSize = CGSize(
            width: min(
                max(fittedContentSize.width + horizontalPadding, minWindowSize.width),
                maximumWindowSize.width
            ),
            height: min(
                max(fittedContentSize.height + headerHeight + verticalPadding, minWindowSize.height),
                maximumWindowSize.height
            )
        )
        return defaultFrame(for: totalSize)
    }

    private func pinItem(for id: UUID) -> PinItem? {
        pins.first(where: { $0.id == id })
    }

    private func openDockedPin(id: UUID, bringToFront: Bool) {
        guard let pin = pinItem(for: id), pin.record.isDockedPin else {
            return
        }

        let sourceDockFrame = pin.record.isCollapsed ? dockIconFrame(for: id) : nil

        if pin.record.isCollapsed {
            let expandedFrame = expandedFrameForOpeningCollapsedPin(pin)
            pin.applyCollapsedState(
                false,
                frame: expandedFrame,
                expandedSize: expandedFrame.size
            )
        }

        let controller = ensureWindowController(for: pin)
        if bringToFront {
            controller.showPinWindow(fromDockFrame: sourceDockFrame)
        } else {
            controller.showWindow(nil)
        }
    }

    private func ensureWindowController(for pin: PinItem) -> PinWindowController {
        if let existingController = windowControllers[pin.id] {
            return existingController
        }

        let controller = PinWindowController(item: pin, coordinator: self)
        windowControllers[pin.id] = controller
        return controller
    }

    private func closeAndRemoveWindowController(for id: UUID) {
        guard let controller = windowControllers.removeValue(forKey: id) else {
            return
        }

        controller.closeWindowProgrammatically()
    }

    private func ensureInventoryMembership(for id: UUID) {
        guard let pin = pinItem(for: id) else {
            return
        }

        ensureInventoryOrder(for: pin)

        let existingDockedIDs = dockedPins.map(\.id).filter { $0 != id }
        guard !pin.record.isDockedPin || pin.record.dockOrder == nil else {
            return
        }

        applyDockOrder(for: existingDockedIDs + [id])
        refreshPinsCollection()
    }

    private func ensureInventoryOrder(for pin: PinItem) {
        let slots = inventorySlots(limit: Self.defaultInventorySlotLimit)
        guard let resolvedIndex = slots.firstIndex(where: { item in
            item?.id == pin.id
        }) else {
            return
        }

        guard pin.record.inventoryOrder != resolvedIndex else {
            return
        }

        pin.setInventoryOrder(resolvedIndex)
    }

    private func applyDockOrder(for noteIDs: [UUID]) {
        for (index, id) in noteIDs.enumerated() {
            pinItem(for: id)?.setDockState(isDocked: true, order: index)
        }
    }

    private func normalizeDockOrder() {
        applyDockOrder(for: dockedPins.map(\.id))
    }

    private func refreshPinsCollection() {
        pins = pins
    }

    private func dockSortPrecedes(_ lhs: PinItem, _ rhs: PinItem) -> Bool {
        let lhsOrder = lhs.record.dockOrder ?? Int.max
        let rhsOrder = rhs.record.dockOrder ?? Int.max
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }

        return lhs.record.createdAt < rhs.record.createdAt
    }

    private func expandedFrameForOpeningCollapsedPin(_ pin: PinItem) -> CGRect {
        let storedFrame = pin.record.frame.cgRect
        let minimumExpandedSize = minimumExpandedSize(for: pin.record.kind)
        let targetWidth = max(
            CGFloat(pin.record.expandedWidth ?? storedFrame.width),
            storedFrame.width,
            minimumExpandedSize.width
        )
        let targetHeight = max(
            CGFloat(pin.record.expandedHeight ?? storedFrame.height),
            storedFrame.height,
            minimumExpandedSize.height
        )

        let storedFrameLooksExpanded = (
            storedFrame.width >= minimumExpandedSize.width &&
            storedFrame.height >= minimumExpandedSize.height
        )

        if storedFrameLooksExpanded {
            return CGRect(
                x: storedFrame.minX,
                y: storedFrame.minY,
                width: targetWidth,
                height: targetHeight
            ).integral
        }

        return CGRect(
            x: storedFrame.minX,
            y: storedFrame.maxY - targetHeight,
            width: targetWidth,
            height: targetHeight
        ).integral
    }

    private func minimumExpandedSize(for kind: PinKind) -> CGSize {
        switch kind {
        case .note:
            return CGSize(width: 180, height: 120)
        case .image:
            return CGSize(width: 140, height: 90)
        }
    }

    private func fittedSize(for originalSize: CGSize, in boundingSize: CGSize) -> CGSize {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return boundingSize
        }

        let scale = min(
            boundingSize.width / originalSize.width,
            boundingSize.height / originalSize.height
        )

        let appliedScale = min(scale, 1.0)
        return CGSize(
            width: max(1, floor(originalSize.width * appliedScale)),
            height: max(1, floor(originalSize.height * appliedScale))
        )
    }

    private func preferredVisibleFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen.visibleFrame
        }

        if let screen = NSApp.keyWindow?.screen {
            return screen.visibleFrame
        }

        return (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 120, y: 120, width: 1280, height: 800)
    }

    private func clearError() {
        lastErrorMessage = nil
    }

    private func observeAppTermination() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistImmediately()
            }
        }
    }

    nonisolated private static func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

private enum SpacePinError: LocalizedError {
    case unsupportedImage(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedImage(filename):
            return L10n.format(
                "error.unsupported_image",
                fallback: "%@ could not be loaded as an image.",
                filename
            )
        }
    }
}
