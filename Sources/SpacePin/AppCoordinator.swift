import AppKit
import Combine
import Foundation
import SpacePinCore
import UniformTypeIdentifiers

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var pins: [PinItem] = []
    @Published var lastErrorMessage: String?

    private let repository: PinRepository
    private let imageStore: ImageAssetStore
    private var windowControllers: [UUID: PinWindowController] = [:]
    private lazy var managerWindowController = ManagerWindowController(coordinator: self)
    private var hasStarted = false
    private var persistWorkItem: DispatchWorkItem?
    private var terminationObserver: NSObjectProtocol?

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

        let controller = windowControllers.removeValue(forKey: id)
        pins.remove(at: index)
        controller?.closeWindowProgrammatically()
        persistImmediately()
    }

    func bringToFront(id: UUID) {
        windowControllers[id]?.showPinWindow()
    }

    func bringAllPinsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        pins.forEach { pin in
            windowControllers[pin.id]?.showPinWindow()
        }
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

    private func restorePins() {
        do {
            let restoredPins = try repository.load()
            restoredPins.forEach { record in
                addPin(record, bringToFront: false, shouldSchedulePersistence: false)
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

        let controller = PinWindowController(item: pin, coordinator: self)
        windowControllers[pin.id] = controller

        if bringToFront {
            controller.showPinWindow()
        } else {
            controller.showWindow(nil)
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
        let maximumWindowSize = CGSize(
            width: preferredVisibleFrame().width - 48,
            height: preferredVisibleFrame().height - 48
        )

        guard let image = NSImage(contentsOf: imageURL), image.size.width > 0, image.size.height > 0 else {
            return defaultFrame(for: fallbackSize)
        }

        let minWindowSize = CGSize(width: 220, height: 160)
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
            width: max(fittedContentSize.width + horizontalPadding, minWindowSize.width),
            height: max(fittedContentSize.height + headerHeight + verticalPadding, minWindowSize.height)
        )
        return defaultFrame(for: totalSize)
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
