import AppKit
import Carbon
import Combine
import Foundation
import SpacePinCore
import SwiftUI

enum AppLaunchMode {
    case foreground
    case background

    init(processInfo: ProcessInfo = .processInfo) {
        self = MenuBarBridge.isBackgroundLaunch(processInfo: processInfo) ? .background : .foreground
    }

    var shouldPromptForLaunchAtLogin: Bool {
        self == .foreground
    }
}

@main
struct SpacePinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator: AppCoordinator
    @StateObject private var launchAtLoginController: LaunchAtLoginController
    @StateObject private var quickPaletteShortcutStore: QuickPaletteShortcutStore

    init() {
        let coordinator = AppCoordinator()
        coordinator.startIfNeeded()
        let launchAtLoginController = LaunchAtLoginController()
        let quickPaletteShortcutStore = QuickPaletteShortcutStore()
        AppDelegate.pendingCoordinator = coordinator
        AppDelegate.pendingLaunchAtLoginController = launchAtLoginController
        AppDelegate.pendingQuickPaletteShortcutStore = quickPaletteShortcutStore
        AppDelegate.pendingLaunchMode = AppLaunchMode()
        _coordinator = StateObject(wrappedValue: coordinator)
        _launchAtLoginController = StateObject(wrappedValue: launchAtLoginController)
        _quickPaletteShortcutStore = StateObject(wrappedValue: quickPaletteShortcutStore)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .environmentObject(launchAtLoginController)
                .environmentObject(quickPaletteShortcutStore)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("action.open_settings", fallback: "Settings…")) {
                    AppDelegate.showSettingsWindowFromMenu()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var shared: AppDelegate?

    static var pendingCoordinator: AppCoordinator?
    static var pendingLaunchAtLoginController: LaunchAtLoginController?
    static var pendingQuickPaletteShortcutStore: QuickPaletteShortcutStore?
    static var pendingLaunchMode: AppLaunchMode?

    private var coordinator: AppCoordinator?
    private var launchAtLoginController: LaunchAtLoginController?
    private var quickPaletteShortcutStore: QuickPaletteShortcutStore?
    private var launchMode: AppLaunchMode = .foreground
    private var hasScheduledLaunchAtLoginPrompt = false
    private var commandObservers: [NSObjectProtocol] = []
    private var settingsWindowController: SettingsWindowController?
    private var quickPaletteWindowController: QuickPaletteWindowController?
    private var quickPaletteHotKeyController: QuickPaletteHotKeyController?

    static func showSettingsWindowFromMenu() {
        Task { @MainActor in
            shared?.showSettingsWindow()
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarBridge.terminateOtherSpacePinApplications(
            allowedBundleURLs: [
                Bundle.main.bundleURL,
                MenuBarBridge.helperAppURL()
            ]
        )

        if let pendingCoordinator = Self.pendingCoordinator,
           let pendingLaunchAtLoginController = Self.pendingLaunchAtLoginController,
           let pendingQuickPaletteShortcutStore = Self.pendingQuickPaletteShortcutStore {
            Self.pendingCoordinator = nil
            Self.pendingLaunchAtLoginController = nil
            Self.pendingQuickPaletteShortcutStore = nil
            launchMode = Self.pendingLaunchMode ?? .foreground
            Self.pendingLaunchMode = nil
            configure(
                with: pendingCoordinator,
                launchAtLoginController: pendingLaunchAtLoginController,
                quickPaletteShortcutStore: pendingQuickPaletteShortcutStore
            )
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchAtLoginController?.refreshStatus()
        publishLaunchAtLoginStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.compactMap { MenuBarBridge.command(from: $0) }.forEach(handle)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        commandObservers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
        }
        if Self.shared === self {
            Self.shared = nil
        }
    }

    @objc
    private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString),
            let command = MenuBarBridge.command(from: url)
        else {
            return
        }

        handle(command: command)
    }

    private func configure(
        with coordinator: AppCoordinator,
        launchAtLoginController: LaunchAtLoginController,
        quickPaletteShortcutStore: QuickPaletteShortcutStore
    ) {
        guard self.coordinator == nil else {
            return
        }

        self.coordinator = coordinator
        self.launchAtLoginController = launchAtLoginController
        self.quickPaletteShortcutStore = quickPaletteShortcutStore
        let quickPaletteWindowController = QuickPaletteWindowController(coordinator: coordinator)
        self.quickPaletteWindowController = quickPaletteWindowController
        quickPaletteHotKeyController = QuickPaletteHotKeyController(
            shortcutStore: quickPaletteShortcutStore
        ) { [weak self] in
            self?.quickPaletteWindowController?.show()
        }
        coordinator.setDockDropTarget(quickPaletteWindowController)
        launchMenuBarHelperIfNeeded()
        observeRemoteCommands()
        publishLaunchAtLoginStatus()
        publishQuickPaletteShortcut()

        scheduleLaunchAtLoginPromptIfNeeded()
    }

    private func launchMenuBarHelperIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let helperBundleIdentifier = MenuBarBridge.helperBundleIdentifier(for: bundleIdentifier)
        let helperURL = MenuBarBridge.helperAppURL()
        MenuBarAppLauncher.launchIfNeeded(
            bundleIdentifier: helperBundleIdentifier,
            appURL: helperURL,
            arguments: [],
            activates: false
        )
    }

    private func observeRemoteCommands() {
        commandObservers = MenuBarBridge.commandNotifications.map { notificationName in
            DistributedNotificationCenter.default().addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let command = MenuBarBridge.command(from: notification) else {
                    return
                }

                Task { @MainActor in
                    self?.handle(command: command)
                }
            }
        }
    }

    private func handle(command: MenuBarCommand) {
        switch command {
        case .showQuickPalette:
            quickPaletteWindowController?.show()
        case .openManager:
            coordinator?.showManagerWindow()
        case .openSettings:
            showSettingsWindow()
        case .newNotePin:
            coordinator?.createNotePin()
        case .importImage:
            coordinator?.presentImageImporter()
        case .bringAllPinsForward:
            coordinator?.bringAllPinsToFront()
        case .enableLaunchAtLogin:
            launchAtLoginController?.setEnabled(true)
            publishLaunchAtLoginStatus()
        case .disableLaunchAtLogin:
            launchAtLoginController?.setEnabled(false)
            publishLaunchAtLoginStatus()
        case .syncQuickPaletteShortcut:
            publishQuickPaletteShortcut()
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func publishLaunchAtLoginStatus() {
        guard let launchAtLoginController else {
            return
        }

        MenuBarBridge.postLaunchAtLoginStatus(
            launchAtLoginController.status,
            errorMessage: launchAtLoginController.errorMessage
        )
    }

    private func publishQuickPaletteShortcut() {
        guard let quickPaletteShortcutStore else {
            return
        }

        MenuBarBridge.postQuickPaletteShortcut(quickPaletteShortcutStore.shortcut)
    }

    private func showSettingsWindow() {
        guard let coordinator, let launchAtLoginController, let quickPaletteShortcutStore else {
            return
        }

        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                coordinator: coordinator,
                launchAtLoginController: launchAtLoginController,
                quickPaletteShortcutStore: quickPaletteShortcutStore
            )
        }

        settingsWindowController?.present()
    }

    private func scheduleLaunchAtLoginPromptIfNeeded() {
        guard launchMode.shouldPromptForLaunchAtLogin, !hasScheduledLaunchAtLoginPrompt else {
            return
        }

        hasScheduledLaunchAtLoginPrompt = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.presentLaunchAtLoginPromptIfNeeded()
        }
    }

    private func presentLaunchAtLoginPromptIfNeeded() {
        guard let launchAtLoginController, launchAtLoginController.shouldPromptOnLaunch else {
            return
        }

        let suppressButton = NSButton(
            checkboxWithTitle: L10n.text(
                "prompt.launch_at_login_do_not_ask_again",
                fallback: "Don't ask again"
            ),
            target: nil,
            action: nil
        )

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text(
            "prompt.launch_at_login_message",
            fallback: "Open SpacePin automatically when you log in?"
        )
        alert.informativeText = L10n.text(
            "prompt.launch_at_login_info",
            fallback: "You can change this later from the menu bar or Settings. macOS may ask you to approve SpacePin in Login Items."
        )
        alert.addButton(withTitle: L10n.text(
            "prompt.launch_at_login_enable",
            fallback: "Enable"
        ))
        alert.addButton(withTitle: L10n.text(
            "prompt.not_now",
            fallback: "Not Now"
        ))
        alert.accessoryView = suppressButton

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if suppressButton.state == .on {
            launchAtLoginController.setPromptSuppressed(true)
        }

        if response == .alertFirstButtonReturn {
            launchAtLoginController.setEnabled(true)
            publishLaunchAtLoginStatus()
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController
    @EnvironmentObject private var quickPaletteShortcutStore: QuickPaletteShortcutStore

    @State private var isRecordingShortcut = false
    @State private var shortcutRecordingError: String?
    @State private var shortcutEventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("app.name", fallback: "SpacePin"))
                .font(.title2.bold())

            Text(L10n.text("settings.storage_path", fallback: "Pins are stored in ~/Library/Application Support/SpacePin."))
                .foregroundStyle(.secondary)

            Toggle(
                L10n.text("settings.launch_at_login", fallback: "Launch at login"),
                isOn: Binding(get: {
                    launchAtLoginController.isEnabled
                }, set: { newValue in
                    launchAtLoginController.setEnabled(newValue)
                })
            )

            Text(L10n.text(
                "settings.launch_at_login_help",
                fallback: "Automatically open SpacePin when you log in."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)

            if launchAtLoginController.requiresApproval {
                Text(L10n.text(
                    "settings.launch_at_login_requires_approval",
                    fallback: "Allow SpacePin in System Settings > General > Login Items."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                Button(L10n.text("action.open_login_items_settings", fallback: "Open Login Items Settings")) {
                    launchAtLoginController.openSystemSettings()
                }
            }

            if let errorMessage = launchAtLoginController.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("settings.quick_palette_shortcut", fallback: "Quick palette shortcut"))
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(quickPaletteShortcutStore.shortcut.displayString)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minWidth: 98, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.075))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )

                    Button(isRecordingShortcut
                        ? L10n.text("action.recording_shortcut", fallback: "Press shortcut…")
                        : L10n.text("action.change_shortcut", fallback: "Change")
                    ) {
                        beginShortcutRecording()
                    }

                    Button(L10n.text("action.reset", fallback: "Reset")) {
                        stopShortcutRecording()
                        shortcutRecordingError = nil
                        quickPaletteShortcutStore.resetToDefault()
                    }
                    .disabled(quickPaletteShortcutStore.shortcut == .default)
                }

                Text(L10n.text(
                    "settings.quick_palette_shortcut_help",
                    fallback: "Use at least one of Control, Option, or Command with a key. Press Esc to cancel recording."
                ))
                .font(.callout)
                .foregroundStyle(.secondary)

                if let shortcutRecordingError {
                    Text(shortcutRecordingError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Button(L10n.text("action.open_manager", fallback: "Open Manager")) {
                coordinator.showManagerWindow()
            }
        }
        .frame(width: 430)
        .padding(24)
        .background(SettingsWindowForegroundingView())
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private func beginShortcutRecording() {
        shortcutRecordingError = nil
        stopShortcutRecording()
        isRecordingShortcut = true

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == kVK_Escape {
                stopShortcutRecording()
                return nil
            }

            guard let shortcut = QuickPaletteShortcut(event: event) else {
                shortcutRecordingError = L10n.text(
                    "error.shortcut_requires_modifier",
                    fallback: "Press a key with Control, Option, or Command."
                )
                return nil
            }

            quickPaletteShortcutStore.setShortcut(shortcut)
            stopShortcutRecording()
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
            self.shortcutEventMonitor = nil
        }
        isRecordingShortcut = false
    }
}

private struct SettingsWindowForegroundingView: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsWindowForegroundingNSView {
        SettingsWindowForegroundingNSView()
    }

    func updateNSView(_ nsView: SettingsWindowForegroundingNSView, context: Context) {
        nsView.foregroundSettingsWindowIfNeeded()
    }
}

private final class SettingsWindowForegroundingNSView: NSView {
    private weak var lastForegroundedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        foregroundSettingsWindowIfNeeded()
    }

    func foregroundSettingsWindowIfNeeded() {
        guard let window else {
            return
        }

        guard lastForegroundedWindow !== window || !window.isKeyWindow else {
            return
        }

        lastForegroundedWindow = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else {
                return
            }

            Self.foreground(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak window] in
                guard let window, window.isVisible else {
                    return
                }

                Self.foreground(window)
            }
        }
    }

    private static func foreground(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        window.makeKeyAndOrderFront(nil)

        if !window.isKeyWindow {
            window.orderFrontRegardless()
        }
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        coordinator: AppCoordinator,
        launchAtLoginController: LaunchAtLoginController,
        quickPaletteShortcutStore: QuickPaletteShortcutStore
    ) {
        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(coordinator)
                .environmentObject(launchAtLoginController)
                .environmentObject(quickPaletteShortcutStore)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.text("app.name", fallback: "SpacePin")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 478, height: 408))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SpacePinSettingsWindow")
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        showWindow(nil)
        foreground(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let window = self?.window, window.isVisible else {
                return
            }

            self?.foreground(window)
        }
    }

    private func foreground(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        window.makeKeyAndOrderFront(nil)

        if !window.isKeyWindow {
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
private final class QuickPaletteWindowController: NSWindowController, DockDropTarget {
    private enum Metrics {
        static let width: CGFloat = 780
        static let height: CGFloat = 510
        static let screenMargin: CGFloat = 24
        static let dropExpansion: CGFloat = 24
        static let columns = 10
        static let slotCount = 40
        static let slotSize: CGFloat = 60
        static let cellWidth: CGFloat = 60
        static let cellHeight: CGFloat = 72
        static let columnSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 18
        static let iconFrameSize: CGFloat = 60
        static let contentPadding: CGFloat = 18
        static let headerHeight: CGFloat = 24
        static let sectionSpacing: CGFloat = 12
        static let gridPadding: CGFloat = 12
    }

    private final class PalettePanel: NSPanel {
        var onCancel: (() -> Void)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        override func cancelOperation(_ sender: Any?) {
            onCancel?()
        }
    }

    private let coordinator: AppCoordinator
    private let hostingController: NSHostingController<QuickPaletteView>
    private var pinsCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var pinIconFrames: [UUID: CGRect] = [:]

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        hostingController = NSHostingController(
            rootView: QuickPaletteView(
                coordinator: coordinator,
                onDismiss: {},
                onOpenManager: {},
                onCreateNote: {},
                onImportImage: {},
                onBringAllPinsForward: {},
                onOpenPin: { _ in },
                onMovePin: { _, _ in },
                onPinFrameChanged: { _, _ in }
            )
        )

        let panel = PalettePanel(
            contentRect: CGRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = hostingController

        super.init(window: panel)

        panel.onCancel = { [weak self] in
            self?.hide()
        }
        rebuildRootView()
        observePins()
        installEventMonitors()
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let panel = window else {
            return
        }

        rebuildRootView()
        centerPanel(on: preferredScreen())
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        hostingController.view.layoutSubtreeIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func rebuildRootView() {
        hostingController.rootView = QuickPaletteView(
            coordinator: coordinator,
            onDismiss: { [weak self] in
                self?.hide()
            },
            onOpenManager: { [weak self] in
                self?.hide()
                self?.coordinator.showManagerWindow()
            },
            onCreateNote: { [weak self] in
                self?.hide()
                self?.coordinator.createNotePin()
            },
            onImportImage: { [weak self] in
                self?.hide()
                self?.coordinator.presentImageImporter()
            },
            onBringAllPinsForward: { [weak self] in
                self?.hide()
                self?.coordinator.bringAllPinsToFront()
            },
            onOpenPin: { [weak self] id in
                self?.coordinator.bringToFront(id: id)
                self?.hide()
            },
            onMovePin: { [weak self] id, targetIndex in
                self?.coordinator.movePinInInventory(id: id, toInventoryIndex: targetIndex, slotCount: Metrics.slotCount)
            },
            onPinFrameChanged: { [weak self] id, frame in
                if let frame {
                    self?.pinIconFrames[id] = frame
                } else {
                    self?.pinIconFrames.removeValue(forKey: id)
                }
            }
        )
    }

    private func observePins() {
        pinsCancellable = coordinator.$pins.sink { [weak self] _ in
            Task { @MainActor in
                self?.rebuildRootView()
                if self?.window?.isVisible == true {
                    self?.centerPanel(on: self?.window?.screen ?? self?.preferredScreen())
                }
            }
        }
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            if event.type == .keyDown, event.keyCode == 53 {
                self.hide()
                return nil
            }

            if self.window?.isVisible == true,
               let panel = self.window,
               event.window !== panel {
                self.hide()
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func centerPanel(on screen: NSScreen?) {
        guard let panel = window else {
            return
        }

        let visibleFrame = (screen ?? preferredScreen())?.visibleFrame
            ?? CGRect(x: 120, y: 120, width: 1280, height: 800)
        let width = min(Metrics.width, max(280, visibleFrame.width - (Metrics.screenMargin * 2)))
        let height = min(Metrics.height, max(260, visibleFrame.height - (Metrics.screenMargin * 2)))
        let frame = CGRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        ).integral

        if !panel.frame.equalTo(frame) {
            panel.setFrame(frame, display: true)
        }
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        return NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    func containsDockDropPoint(_ point: CGPoint) -> Bool {
        guard let panel = window, panel.isVisible else {
            return false
        }

        return panel.frame.insetBy(dx: -Metrics.dropExpansion, dy: -Metrics.dropExpansion).contains(point)
    }

    func dockInsertionIndex(for point: CGPoint) -> Int? {
        containsDockDropPoint(point) ? coordinator.dockedPins.count : nil
    }

    func currentDockDragInsertionIndex(for pinID: UUID) -> Int? {
        nil
    }

    func updateDockDrag(pinID: UUID?, point: CGPoint?) {}

    func dockIconFrame(for pinID: UUID, preferredPoint: CGPoint?) -> CGRect? {
        if window?.isVisible != true {
            show()
        }

        hostingController.view.layoutSubtreeIfNeeded()
        window?.contentView?.layoutSubtreeIfNeeded()

        if let frame = pinIconFrames[pinID] {
            return frame
        }

        guard let panel = window, panel.isVisible else {
            return nil
        }

        if let index = coordinator.inventoryIndex(for: pinID, limit: Metrics.slotCount),
           index < Metrics.slotCount {
            return fallbackIconFrame(forInventoryIndex: index, in: panel.frame)
        }

        return CGRect(
            x: panel.frame.midX - 17,
            y: panel.frame.midY - 17,
            width: 34,
            height: 34
        ).integral
    }

    private func fallbackIconFrame(forInventoryIndex index: Int, in panelFrame: CGRect) -> CGRect {
        let column = CGFloat(index % Metrics.columns)
        let row = CGFloat(index / Metrics.columns)
        let horizontalPitch = Metrics.cellWidth + Metrics.columnSpacing
        let verticalPitch = Metrics.cellHeight + Metrics.rowSpacing
        let slotCenterX = panelFrame.minX
            + Metrics.contentPadding
            + Metrics.gridPadding
            + (Metrics.cellWidth / 2)
            + (column * horizontalPitch)
        let slotCenterY = panelFrame.maxY
            - Metrics.contentPadding
            - Metrics.headerHeight
            - Metrics.sectionSpacing
            - Metrics.gridPadding
            - (Metrics.slotSize / 2)
            - (row * verticalPitch)

        return CGRect(
            x: slotCenterX - (Metrics.iconFrameSize / 2),
            y: slotCenterY - (Metrics.iconFrameSize / 2),
            width: Metrics.iconFrameSize,
            height: Metrics.iconFrameSize
        ).integral
    }
}

private struct QuickPaletteView: View {
    private enum Metrics {
        static let columns = 10
        static let rows = 4
        static let slotCount = columns * rows
        static let slotSize: CGFloat = 60
        static let cellWidth: CGFloat = 60
        static let cellHeight: CGFloat = 72
        static let columnSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 18
    }

    @ObservedObject var coordinator: AppCoordinator

    let onDismiss: () -> Void
    let onOpenManager: () -> Void
    let onCreateNote: () -> Void
    let onImportImage: () -> Void
    let onBringAllPinsForward: () -> Void
    let onOpenPin: (UUID) -> Void
    let onMovePin: (UUID, Int) -> Void
    let onPinFrameChanged: (UUID, CGRect?) -> Void

    @State private var draggedPinID: UUID?
    @State private var dragSourceIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGSize = .zero

    private var inventorySlots: [PinItem?] {
        coordinator.inventorySlots(limit: Metrics.slotCount)
    }

    private var draggedInventoryItem: PinItem? {
        guard let draggedPinID else {
            return nil
        }

        return inventorySlots.compactMap(\.self).first { item in
            item.id == draggedPinID
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(Metrics.cellWidth), spacing: Metrics.columnSpacing),
            count: Metrics.columns
        )
    }

    var body: some View {
        ZStack {
            DockVisualEffectView(material: .popover)

            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.86, blue: 0.66).opacity(0.10),
                    Color(red: 0.58, green: 0.78, blue: 0.70).opacity(0.08),
                    Color(red: 0.70, green: 0.60, blue: 0.82).opacity(0.07),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(L10n.text("app.name", fallback: "SpacePin"))
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(L10n.text("action.close", fallback: "Close"))
                }

                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: columns, spacing: Metrics.rowSpacing) {
                        ForEach(0..<Metrics.slotCount, id: \.self) { index in
                            if let item = inventorySlots[index] {
                                let isDragging = draggedPinID == item.id
                                QuickPaletteInventoryCell(
                                    item: item,
                                    isDragging: isDragging,
                                    isDropTarget: draggedPinID != nil && dragTargetIndex == index && !isDragging,
                                    onBeginDrag: {
                                        draggedPinID = item.id
                                        dragSourceIndex = index
                                        dragTargetIndex = index
                                        dragTranslation = .zero
                                    },
                                    onUpdateDrag: { translation in
                                        dragTranslation = translation
                                        dragTargetIndex = targetIndex(forSourceIndex: index, translation: translation)
                                    },
                                    onEndDrag: { didDrag in
                                        if didDrag,
                                           let dragTargetIndex,
                                           draggedPinID == item.id {
                                            onMovePin(item.id, dragTargetIndex)
                                        } else {
                                            onOpenPin(item.id)
                                        }
                                        resetDragState()
                                    },
                                    onFrameChange: { frame in
                                        onPinFrameChanged(item.id, frame)
                                    }
                                )
                            } else {
                                QuickPaletteEmptySlot(
                                    isDropTarget: draggedPinID != nil && dragTargetIndex == index
                                )
                            }
                        }
                    }

                    if let draggedInventoryItem, let dragSourceIndex {
                        let origin = iconOrigin(forInventoryIndex: dragSourceIndex)
                        QuickPaletteInventoryIcon(
                            item: draggedInventoryItem,
                            isHovered: false,
                            isDropTarget: false
                        )
                        .scaleEffect(1.07)
                        .opacity(0.96)
                        .offset(
                            x: origin.x + dragTranslation.width,
                            y: origin.y + dragTranslation.height
                        )
                        .allowsHitTesting(false)
                        .zIndex(1000)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.105),
                                    Color(red: 0.70, green: 0.88, blue: 0.78).opacity(0.050),
                                    Color(red: 0.93, green: 0.82, blue: 0.56).opacity(0.035),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

                HStack(alignment: .bottom, spacing: 8) {
                    QuickPaletteActionButton(
                        systemName: "note.text.badge.plus",
                        title: L10n.text("action.new_text_memo", fallback: "Text Memo"),
                        action: onCreateNote
                    )

                    QuickPaletteActionButton(
                        systemName: "photo.badge.plus",
                        title: L10n.text("action.new_image_memo", fallback: "Image Memo"),
                        action: onImportImage
                    )

                    QuickPaletteActionButton(
                        systemName: "square.grid.2x2",
                        title: L10n.text("action.manager_short", fallback: "Manager"),
                        action: onOpenManager
                    )

                    QuickPaletteActionButton(
                        systemName: "rectangle.stack",
                        title: L10n.text("action.bring_all_forward_short", fallback: "All Memos Front"),
                        action: onBringAllPinsForward
                    )
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func targetIndex(forSourceIndex sourceIndex: Int, translation: CGSize) -> Int {
        let horizontalPitch = Metrics.cellWidth + Metrics.columnSpacing
        let verticalPitch = Metrics.cellHeight + Metrics.rowSpacing
        let sourceColumn = sourceIndex % Metrics.columns
        let sourceRow = sourceIndex / Metrics.columns
        let targetColumn = max(
            0,
            min(Metrics.columns - 1, sourceColumn + Int((translation.width / horizontalPitch).rounded()))
        )
        let targetRow = max(
            0,
            min(Metrics.rows - 1, sourceRow + Int((translation.height / verticalPitch).rounded()))
        )
        return (targetRow * Metrics.columns) + targetColumn
    }

    private func iconOrigin(forInventoryIndex index: Int) -> CGPoint {
        let horizontalPitch = Metrics.cellWidth + Metrics.columnSpacing
        let verticalPitch = Metrics.cellHeight + Metrics.rowSpacing
        return CGPoint(
            x: CGFloat(index % Metrics.columns) * horizontalPitch,
            y: CGFloat(index / Metrics.columns) * verticalPitch
        )
    }

    private func resetDragState() {
        draggedPinID = nil
        dragSourceIndex = nil
        dragTargetIndex = nil
        dragTranslation = .zero
    }
}

private struct QuickPaletteActionButton: View {
    @State private var isHovered = false

    let systemName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.17 : 0.105))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.26 : 0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { isHovered = $0 }
    }
}

private struct QuickPaletteInventoryCell: View {
    @ObservedObject var item: PinItem
    @State private var isHovered = false
    @State private var hasDragged = false

    let isDragging: Bool
    let isDropTarget: Bool
    let onBeginDrag: () -> Void
    let onUpdateDrag: (CGSize) -> Void
    let onEndDrag: (Bool) -> Void
    let onFrameChange: (CGRect?) -> Void

    var body: some View {
        QuickPaletteInventoryIcon(
            item: item,
            isHovered: isHovered,
            isDropTarget: isDropTarget
        )
        .scaleEffect(isDragging ? 1.0 : (isHovered ? 1.035 : 1.0))
        .opacity(isDragging ? 0.001 : 1.0)
        .background(DockIconFrameReporter(onFrameChange: onFrameChange))
        .help(item.displayTitle)
        .onHover { isHovered = $0 }
        .onDisappear {
            onFrameChange(nil)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard hasDragged || hypot(value.translation.width, value.translation.height) >= 4 else {
                        return
                    }

                    if !hasDragged {
                        hasDragged = true
                        onBeginDrag()
                    }
                    isHovered = false
                    onUpdateDrag(value.translation)
                }
                .onEnded { value in
                    if hasDragged {
                        onUpdateDrag(value.translation)
                        hasDragged = false
                        onEndDrag(true)
                    } else {
                        onEndDrag(false)
                    }
                }
        )
    }
}

private struct QuickPaletteInventoryIcon: View {
    @ObservedObject var item: PinItem

    let isHovered: Bool
    let isDropTarget: Bool

    private var theme: NoteTheme {
        item.record.frameColorPreset.theme
    }

    private var isOpen: Bool {
        !item.record.isCollapsed
    }

    private var slotShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var outerIconShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var innerIconShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                slotShape
                    .fill(slotFill)
                    .overlay(
                        slotShape
                            .stroke(slotStroke, lineWidth: 1)
                    )
                    .shadow(
                        color: Color.black.opacity(0.07),
                        radius: 3,
                        x: 0,
                        y: 1
                    )

                outerIconShape
                    .fill(Color(nsColor: theme.headerBackground).opacity(isHovered ? 1.0 : 0.94))
                    .overlay(
                        outerIconShape
                            .stroke(
                                Color(nsColor: theme.swatch).opacity(isHovered ? 0.94 : 0.78),
                                lineWidth: 1.4
                            )
                    )
                    .shadow(
                        color: Color(nsColor: theme.swatch).opacity(isHovered ? 0.28 : 0.18),
                        radius: isHovered ? 7 : 5,
                        x: 0,
                        y: 3
                    )
                    .frame(width: 60, height: 60)

                innerIconShape
                    .fill(Color(nsColor: theme.bodyBackground).opacity(0.96))
                    .overlay(
                        innerIconShape
                            .stroke(Color(nsColor: theme.swatch).opacity(0.76), lineWidth: 1)
                    )
                    .frame(width: 46, height: 46)

                if item.record.headerIconMode == .titleInitial {
                    Text(item.record.localizedHeaderMonogram)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(nsColor: theme.bodyText))
                } else {
                    Image(systemName: item.record.headerIconSymbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(nsColor: theme.bodyText))
                }
            }
            .frame(width: 60, height: 60)
            .overlay(alignment: .topTrailing) {
                if item.record.kind == .image {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 17)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.accentColor.opacity(0.92))
                        )
                        .offset(x: 6, y: -4)
                }
            }
            .overlay {
                if isDropTarget {
                    slotShape
                        .stroke(Color.accentColor.opacity(0.82), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .frame(width: 60, height: 60)
                }
            }

            if isOpen {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.black.opacity(0.36), radius: 1.5, x: 0, y: 1)
            } else {
                Color.clear
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 60, height: 72, alignment: .top)
        .contentShape(Rectangle())
    }

    private var slotFill: Color {
        Color.black.opacity(isHovered ? 0.105 : 0.075)
    }

    private var slotStroke: Color {
        return Color.white.opacity(isHovered ? 0.17 : 0.11)
    }
}

private struct QuickPaletteEmptySlot: View {
    let isDropTarget: Bool

    private var slotShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 5) {
            slotShape
                .fill(isDropTarget ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.050))
                .overlay(
                    slotShape
                        .stroke(
                            isDropTarget ? Color.accentColor.opacity(0.82) : Color.white.opacity(0.090),
                            style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [5, 3] : [])
                        )
                )
                .frame(width: 60, height: 60)

            Color.clear
                .frame(width: 7, height: 7)
        }
        .frame(width: 60, height: 72, alignment: .top)
    }
}

private struct QuickPalettePinRow: View {
    @ObservedObject var item: PinItem
    @State private var isHovered = false

    let onOpen: () -> Void
    let onFrameChange: (CGRect?) -> Void

    private var theme: NoteTheme {
        item.record.frameColorPreset.theme
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                DockGlyphCircle(
                    systemName: item.record.headerIconSymbolName,
                    outerFill: Color(nsColor: theme.headerBackground),
                    innerFill: Color(nsColor: theme.bodyBackground),
                    borderColor: Color(nsColor: theme.swatch).opacity(0.95),
                    iconColor: Color(nsColor: theme.bodyText)
                )
                .background(DockIconFrameReporter(onFrameChange: onFrameChange))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.notePreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.11 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(item.displayTitle)
        .onHover { isHovered = $0 }
        .onDisappear {
            onFrameChange(nil)
        }
    }
}

private struct DockPinPreviewAppearance {
    let systemName: String
    let outerFill: NSColor
    let innerFill: NSColor
    let borderColor: NSColor
    let iconColor: NSColor
}

private struct DockPinPreviewView: View {
    let appearance: DockPinPreviewAppearance

    var body: some View {
        DockGlyphCircle(
            systemName: appearance.systemName,
            outerFill: Color(nsColor: appearance.outerFill),
            innerFill: Color(nsColor: appearance.innerFill),
            borderColor: Color(nsColor: appearance.borderColor),
            iconColor: Color(nsColor: appearance.iconColor)
        )
        .padding(4)
        .background(Color.clear)
    }
}

@MainActor
private final class DockDragPreviewWindowController: NSWindowController {
    private let hostingController: NSHostingController<DockPinPreviewView>

    init() {
        hostingController = NSHostingController(
            rootView: DockPinPreviewView(
                appearance: DockPinPreviewAppearance(
                    systemName: "note.text",
                    outerFill: .windowBackgroundColor,
                    innerFill: .windowBackgroundColor,
                    borderColor: .separatorColor,
                    iconColor: .labelColor
                )
            )
        )

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 42, height: 42),
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
        panel.contentViewController = hostingController

        super.init(window: panel)
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(appearance: DockPinPreviewAppearance, at point: CGPoint) {
        hostingController.rootView = DockPinPreviewView(appearance: appearance)
        updatePosition(to: point)
        window?.orderFrontRegardless()
    }

    func updatePosition(to point: CGPoint) {
        guard let window else {
            return
        }

        window.setFrameOrigin(CGPoint(
            x: point.x - (window.frame.width / 2),
            y: point.y - (window.frame.height / 2)
        ))
        window.orderFrontRegardless()
    }

    func hidePreview() {
        window?.orderOut(nil)
    }
}

@MainActor
private final class EdgeDockWindowController: NSWindowController, DockDropTarget {
    private enum Metrics {
        static let panelWidth: CGFloat = 58
        static let minimumPanelHeight: CGFloat = 104
        static let maximumPanelMargin: CGFloat = 72
        static let revealDistance: CGFloat = 4
        static let dockLeadingInset: CGFloat = 8
        static let itemSlotHeight: CGFloat = 44
        static let baseItemCount: CGFloat = 2
        static let chromeHeight: CGFloat = 28
        static let noteListTopInset: CGFloat = 106
        static let dropExpansionX: CGFloat = 88
        static let dropExpansionY: CGFloat = 40
    }

    private final class DockPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let coordinator: AppCoordinator
    private let hostingController: NSHostingController<EdgeDockView>
    private let dragPreviewWindowController = DockDragPreviewWindowController()
    private var pinsCancellable: AnyCancellable?
    private var dragStateCancellable: AnyCancellable?
    private var mouseMonitorTimer: Timer?
    private var screenParametersObserver: NSObjectProtocol?
    private var isPointerInsideDock = false
    private var internalDraggedPinID: UUID?
    private var isInternalDragInsideDock = true
    private var externalDraggedPinID: UUID?
    private var externalDragInsertionIndex: Int?
    private var dockIconFrames: [UUID: CGRect] = [:]
    private weak var activeScreen: NSScreen?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        hostingController = NSHostingController(
            rootView: EdgeDockView(
                coordinator: coordinator,
                onHoverChanged: { _ in },
                onOpenManager: {},
                onCreateNote: {},
                onOpenPin: { _ in },
                onMovePin: { _, _ in },
                onUndockPin: { _, _ in },
                onBeginPinDrag: { _, _, _ in },
                onUpdatePinDrag: { _, _ in },
                onEndPinDrag: {},
                externalDraggedPinID: nil,
                externalDragInsertionIndex: nil,
                isPointInVisibleDock: { _ in false },
                onPinFrameChanged: { _, _ in }
            )
        )

        let panel = DockPanel(
            contentRect: CGRect(x: 0, y: 0, width: Metrics.panelWidth, height: Metrics.minimumPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.ignoresMouseEvents = false
        panel.contentViewController = hostingController

        super.init(window: panel)

        rebuildRootView()
        observePins()
        observeDragState()
        observeScreenParameters()
        startMouseMonitor()
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func rebuildRootView() {
        hostingController.rootView = EdgeDockView(
            coordinator: coordinator,
            onHoverChanged: { [weak self] isHovering in
                self?.isPointerInsideDock = isHovering
            },
            onOpenManager: { [weak self] in
                self?.coordinator.showManagerWindow()
            },
            onCreateNote: { [weak self] in
                self?.coordinator.createNotePin()
            },
            onOpenPin: { [weak self] id in
                self?.coordinator.bringToFront(id: id)
            },
            onMovePin: { [weak self] id, targetIndex in
                self?.coordinator.moveDockedPin(id: id, toDockIndex: targetIndex)
            },
            onUndockPin: { [weak self] id, dropPoint in
                self?.coordinator.undockPin(id: id, dropScreenPoint: dropPoint, bringToFront: true)
            },
            onBeginPinDrag: { [weak self] id, appearance, point in
                self?.beginDockPinDrag(id: id, appearance: appearance, at: point)
            },
            onUpdatePinDrag: { [weak self] id, point in
                self?.updateDockPinDrag(id: id, at: point)
            },
            onEndPinDrag: { [weak self] in
                self?.endDockPinDrag()
            },
            externalDraggedPinID: externalDraggedPinID,
            externalDragInsertionIndex: externalDragInsertionIndex,
            isPointInVisibleDock: { [weak self] point in
                self?.containsVisibleDockPoint(point) ?? false
            },
            onPinFrameChanged: { [weak self] id, frame in
                if let frame {
                    self?.dockIconFrames[id] = frame
                } else {
                    self?.dockIconFrames.removeValue(forKey: id)
                }
            }
        )
    }

    private func observePins() {
        pinsCancellable = coordinator.$pins.sink { [weak self] _ in
            self?.refreshFrameIfNeeded()
        }
    }

    private func observeDragState() {
        dragStateCancellable = coordinator.$isDockInteractionDragging.sink { [weak self] _ in
            self?.updateVisibilityForCurrentMouseLocation()
        }
    }

    private func observeScreenParameters() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFrameIfNeeded()
            }
        }
    }

    private func startMouseMonitor() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateVisibilityForCurrentMouseLocation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseMonitorTimer = timer
        updateVisibilityForCurrentMouseLocation()
    }

    private func updateVisibilityForCurrentMouseLocation() {
        let mouseLocation = NSEvent.mouseLocation

        if coordinator.isDockInteractionDragging {
            if let draggingScreen = screen(containing: mouseLocation) ?? activeScreen ?? window?.screen {
                activeScreen = draggingScreen
                show(on: draggingScreen)
            }
            return
        }

        if let revealScreen = revealScreen(for: mouseLocation) {
            activeScreen = revealScreen
            show(on: revealScreen)
            return
        }

        if shouldRemainVisible(for: mouseLocation) {
            if let visibleScreen = activeScreen ?? window?.screen {
                show(on: visibleScreen)
            }
            return
        }

        hide()
    }

    private func beginDockPinDrag(id: UUID, appearance: DockPinPreviewAppearance, at point: CGPoint) {
        coordinator.beginDockInteractionDrag()
        internalDraggedPinID = id
        isInternalDragInsideDock = containsVisibleDockPoint(point)
        if let draggingScreen = screen(containing: point) ?? activeScreen ?? window?.screen {
            activeScreen = draggingScreen
            show(on: draggingScreen)
        }
        dragPreviewWindowController.show(appearance: appearance, at: point)
    }

    private func updateDockPinDrag(id: UUID, at point: CGPoint) {
        internalDraggedPinID = id
        isInternalDragInsideDock = containsVisibleDockPoint(point)
        if let draggingScreen = screen(containing: point) ?? activeScreen ?? window?.screen {
            activeScreen = draggingScreen
            show(on: draggingScreen)
        }
        dragPreviewWindowController.updatePosition(to: point)
        refreshFrameIfNeeded()
    }

    private func endDockPinDrag() {
        dragPreviewWindowController.hidePreview()
        internalDraggedPinID = nil
        isInternalDragInsideDock = true
        coordinator.endDockInteractionDrag()
        updateVisibilityForCurrentMouseLocation()
        refreshFrameIfNeeded()
    }

    private func revealScreen(for point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            let visibleFrame = screen.visibleFrame
            let withinVerticalBounds = point.y >= visibleFrame.minY && point.y <= visibleFrame.maxY
            let withinRevealBand = point.x >= visibleFrame.minX - 1 && point.x <= visibleFrame.minX + Metrics.revealDistance
            return withinVerticalBounds && withinRevealBand
        }
    }

    private func shouldRemainVisible(for point: NSPoint) -> Bool {
        guard let panel = window, panel.isVisible else {
            return false
        }

        if isPointerInsideDock {
            return true
        }

        return panel.frame.insetBy(dx: -20, dy: -16).contains(point)
    }

    private func show(on screen: NSScreen) {
        guard let panel = window else {
            return
        }

        let frame = dockFrame(for: screen)
        if !panel.frame.equalTo(frame) {
            panel.setFrame(frame, display: true)
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        if internalDraggedPinID != nil {
            dragPreviewWindowController.window?.orderFrontRegardless()
        }
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func refreshFrameIfNeeded() {
        rebuildRootView()

        guard let currentScreen = activeScreen ?? window?.screen else {
            return
        }

        show(on: currentScreen)
    }

    private func dockFrame(for screen: NSScreen) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let isDraggedPinStillDocked = internalDraggedPinID.map { draggedID in
            coordinator.dockedPins.contains(where: { $0.id == draggedID })
        } ?? false
        let effectiveNoteCount = max(
            0,
            coordinator.dockedPins.count - ((isDraggedPinStillDocked && !isInternalDragInsideDock) ? 1 : 0)
        )
        let noteCount = CGFloat(effectiveNoteCount)
        let preferredHeight = (Metrics.baseItemCount + noteCount) * Metrics.itemSlotHeight + Metrics.chromeHeight
        let maxHeight = max(Metrics.minimumPanelHeight, visibleFrame.height - Metrics.maximumPanelMargin)
        let height = min(max(Metrics.minimumPanelHeight, preferredHeight), maxHeight)
        let x = visibleFrame.minX + Metrics.dockLeadingInset
        let y = visibleFrame.midY - (height / 2)

        return CGRect(x: x, y: y, width: Metrics.panelWidth, height: height).integral
    }

    func containsDockDropPoint(_ point: CGPoint) -> Bool {
        if let revealScreen = revealScreen(for: point) {
            activeScreen = revealScreen
            show(on: revealScreen)
        }

        guard let panel = window else {
            return false
        }

        return expandedDockDropFrame(for: panel).contains(point)
    }

    private func containsVisibleDockPoint(_ point: CGPoint) -> Bool {
        guard let panel = window else {
            return false
        }

        return panel.frame.contains(point)
    }

    func dockInsertionIndex(for point: CGPoint) -> Int? {
        guard let panel = window, expandedDockDropFrame(for: panel).contains(point) else {
            return nil
        }

        let noteCount = coordinator.dockedPins.count
        guard noteCount > 0 else {
            return 0
        }

        let localY = panel.frame.maxY - point.y
        let relativeY = localY - Metrics.noteListTopInset + (Metrics.itemSlotHeight / 2)
        let rawIndex = Int(floor(relativeY / Metrics.itemSlotHeight))
        return max(0, min(rawIndex, noteCount))
    }

    func currentDockDragInsertionIndex(for pinID: UUID) -> Int? {
        guard externalDraggedPinID == pinID else {
            return nil
        }

        return externalDragInsertionIndex
    }

    func dockIconFrame(for pinID: UUID, preferredPoint: CGPoint?) -> CGRect? {
        if let measuredFrame = dockIconFrames[pinID] {
            return measuredFrame
        }

        guard let index = coordinator.dockedPins.firstIndex(where: { $0.id == pinID }) else {
            return nil
        }

        let preferredScreen = preferredPoint.flatMap { screen(containing: $0) }
            ?? activeScreen
            ?? window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let preferredScreen else {
            return nil
        }

        activeScreen = preferredScreen
        show(on: preferredScreen)

        guard let panel = window else {
            return nil
        }

        let iconDiameter: CGFloat = 34
        let centerX = panel.frame.midX
        let centerY = panel.frame.maxY - Metrics.noteListTopInset - (CGFloat(index) * Metrics.itemSlotHeight)
        return CGRect(
            x: centerX - (iconDiameter / 2),
            y: centerY - (iconDiameter / 2),
            width: iconDiameter,
            height: iconDiameter
        ).integral
    }

    func updateDockDrag(pinID: UUID?, point: CGPoint?) {
        let nextInsertionIndex = point.flatMap { dockInsertionIndex(for: $0) }
        guard externalDraggedPinID != pinID || externalDragInsertionIndex != nextInsertionIndex else {
            return
        }

        externalDraggedPinID = pinID
        externalDragInsertionIndex = nextInsertionIndex
        rebuildRootView()
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func expandedDockDropFrame(for panel: NSWindow) -> CGRect {
        panel.frame.insetBy(dx: -Metrics.dropExpansionX, dy: -Metrics.dropExpansionY)
    }
}

private struct EdgeDockView: View {
    @ObservedObject var coordinator: AppCoordinator

    let onHoverChanged: (Bool) -> Void
    let onOpenManager: () -> Void
    let onCreateNote: () -> Void
    let onOpenPin: (UUID) -> Void
    let onMovePin: (UUID, Int) -> Void
    let onUndockPin: (UUID, CGPoint) -> Void
    let onBeginPinDrag: (UUID, DockPinPreviewAppearance, CGPoint) -> Void
    let onUpdatePinDrag: (UUID, CGPoint) -> Void
    let onEndPinDrag: () -> Void
    let externalDraggedPinID: UUID?
    let externalDragInsertionIndex: Int?
    let isPointInVisibleDock: (CGPoint) -> Bool
    let onPinFrameChanged: (UUID, CGRect?) -> Void

    @State private var internalDraggedPinID: UUID?
    @State private var internalDragInsertionIndex: Int?
    @State private var isInternalDragInsideDock = true

    private var notePins: [PinItem] {
        coordinator.dockedPins
    }

    private var externalInsertionIndex: Int? {
        guard externalDraggedPinID != nil, let externalDragInsertionIndex else {
            return nil
        }

        return max(0, min(externalDragInsertionIndex, notePins.count))
    }

    var body: some View {
        ZStack {
            DockVisualEffectView(material: .hudWindow)

            VStack(spacing: 10) {
                DockActionButton(
                    systemName: "square.grid.2x2",
                    helpText: L10n.text("action.open_manager", fallback: "Open Manager"),
                    action: onOpenManager
                )

                DockActionButton(
                    systemName: "plus",
                    helpText: L10n.text("action.new_note_pin", fallback: "New Note Pin"),
                    action: onCreateNote
                )

                if !notePins.isEmpty {
                    Divider()
                        .overlay(Color.primary.opacity(0.15))
                        .padding(.vertical, 2)

                    VStack(spacing: 10) {
                        if externalInsertionIndex == 0 {
                            DockInsertionGap()
                        }

                        ForEach(Array(notePins.enumerated()), id: \.element.id) { index, item in
                            if let externalInsertionIndex, externalInsertionIndex == index, externalInsertionIndex != 0 {
                                DockInsertionGap()
                            }

                            DockPinButton(
                                item: item,
                                index: index,
                                itemCount: notePins.count,
                                slotHeight: 44,
                                onOpen: {
                                    onOpenPin(item.id)
                                },
                                onBeginDrag: { appearance, point in
                                    internalDraggedPinID = item.id
                                    internalDragInsertionIndex = notePins.firstIndex(where: { $0.id == item.id }) ?? index
                                    isInternalDragInsideDock = isPointInVisibleDock(point)
                                    onBeginPinDrag(item.id, appearance, point)
                                },
                                onUpdateDrag: { point, targetIndex in
                                    internalDragInsertionIndex = targetIndex
                                    isInternalDragInsideDock = isPointInVisibleDock(point)
                                    onUpdatePinDrag(item.id, point)
                                },
                                onEndDrag: { targetIndex, dropPoint, shouldRemainDocked in
                                    if shouldRemainDocked {
                                        onMovePin(item.id, targetIndex)
                                    } else {
                                        onUndockPin(item.id, dropPoint)
                                    }
                                    internalDraggedPinID = nil
                                    internalDragInsertionIndex = nil
                                    isInternalDragInsideDock = true
                                    onEndPinDrag()
                                },
                                isPointInVisibleDock: isPointInVisibleDock,
                                onFrameChange: { frame in
                                    onPinFrameChanged(item.id, frame)
                                }
                            )
                            .opacity(internalDraggedPinID == item.id ? 0.001 : 1.0)
                            .offset(y: internalDragOffset(for: item.id, at: index))
                        }

                        if externalInsertionIndex == notePins.count {
                            DockInsertionGap()
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(.easeOut(duration: 0.12), value: internalDragInsertionIndex)
                    .animation(.easeOut(duration: 0.12), value: externalInsertionIndex)
                    .animation(.easeOut(duration: 0.12), value: isInternalDragInsideDock)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onHover(perform: onHoverChanged)
        .onChange(of: coordinator.isDockInteractionDragging) { isDragging in
            guard !isDragging else {
                return
            }

            internalDraggedPinID = nil
            internalDragInsertionIndex = nil
            isInternalDragInsideDock = true
        }
    }

    private func internalDragOffset(for itemID: UUID, at index: Int) -> CGFloat {
        guard
            let internalDraggedPinID,
            let internalDragInsertionIndex,
            let originalIndex = notePins.firstIndex(where: { $0.id == internalDraggedPinID }),
            itemID != internalDraggedPinID
        else {
            return 0
        }

        let slotDistance: CGFloat = 44

        if !isInternalDragInsideDock {
            return index > originalIndex ? -slotDistance : 0
        }

        let targetIndex = max(0, min(internalDragInsertionIndex, max(0, notePins.count - 1)))

        if targetIndex > originalIndex, index > originalIndex, index <= targetIndex {
            return -slotDistance
        }

        if targetIndex < originalIndex, index >= targetIndex, index < originalIndex {
            return slotDistance
        }

        return 0
    }
}

private struct DockInsertionGap: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .frame(width: 34, height: 34)
            .frame(maxWidth: .infinity)
    }
}

private struct DockActionButton: View {
    @State private var isHovered = false

    let systemName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DockGlyphCircle(
                systemName: systemName,
                outerFill: Color.primary.opacity(isHovered ? 0.12 : 0.08),
                innerFill: Color(nsColor: .windowBackgroundColor).opacity(0.94),
                borderColor: Color.primary.opacity(0.16),
                iconColor: .primary
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isHovering in
            isHovered = isHovering
        }
    }
}

private struct DockPinButton: View {
    @ObservedObject var item: PinItem
    @State private var isHovered = false
    @State private var isDragging = false

    let index: Int
    let itemCount: Int
    let slotHeight: CGFloat
    let onOpen: () -> Void
    let onBeginDrag: (DockPinPreviewAppearance, CGPoint) -> Void
    let onUpdateDrag: (CGPoint, Int) -> Void
    let onEndDrag: (Int, CGPoint, Bool) -> Void
    let isPointInVisibleDock: (CGPoint) -> Bool
    let onFrameChange: (CGRect?) -> Void

    private var theme: NoteTheme {
        item.record.frameColorPreset.theme
    }

    private var previewAppearance: DockPinPreviewAppearance {
        DockPinPreviewAppearance(
            systemName: item.record.headerIconSymbolName,
            outerFill: theme.headerBackground,
            innerFill: theme.bodyBackground,
            borderColor: theme.swatch.withAlphaComponent(0.95),
            iconColor: theme.bodyText
        )
    }

    var body: some View {
        DockGlyphCircle(
            systemName: item.record.headerIconSymbolName,
            outerFill: Color(nsColor: theme.headerBackground)
                .opacity((isHovered || isDragging) ? 0.96 : 1.0),
            innerFill: Color(nsColor: theme.bodyBackground),
            borderColor: Color(nsColor: theme.swatch).opacity(0.95),
            iconColor: Color(nsColor: theme.bodyText)
        )
        .help(item.displayTitle)
        .scaleEffect(isDragging ? 1.04 : 1.0)
        .opacity(isDragging ? 0.001 : 1.0)
        .zIndex(isDragging ? 1 : 0)
        .onHover { isHovering in
            guard !isDragging else {
                return
            }

            isHovered = isHovering
        }
        .background(
            DockIconFrameReporter(onFrameChange: onFrameChange)
        )
        .onDisappear {
            onFrameChange(nil)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isDragging || hypot(value.translation.width, value.translation.height) >= 4 else {
                        return
                    }

                    if !isDragging {
                        onBeginDrag(previewAppearance, NSEvent.mouseLocation)
                    }
                    isDragging = true
                    isHovered = false
                    onUpdateDrag(NSEvent.mouseLocation, reorderedIndex(for: value.translation.height))
                }
                .onEnded { value in
                    guard isDragging else {
                        onOpen()
                        return
                    }

                    let dropPoint = NSEvent.mouseLocation
                    let shouldRemainDocked = isPointInVisibleDock(dropPoint)
                    let targetIndex = reorderedIndex(for: value.translation.height)
                    isDragging = false
                    onEndDrag(targetIndex, dropPoint, shouldRemainDocked)
                }
        )
    }

    private func reorderedIndex(for verticalTranslation: CGFloat) -> Int {
        let indexOffset = Int((verticalTranslation / slotHeight).rounded())
        return max(0, min(index + indexOffset, max(0, itemCount - 1)))
    }
}

private struct DockIconFrameReporter: NSViewRepresentable {
    let onFrameChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> DockIconFrameView {
        let view = DockIconFrameView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: DockIconFrameView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrameIfNeeded()
    }

    static func dismantleNSView(_ nsView: DockIconFrameView, coordinator: ()) {
        nsView.onFrameChange(nil)
    }
}

private final class DockIconFrameView: NSView {
    var onFrameChange: (CGRect?) -> Void = { _ in }
    private var lastReportedFrame: CGRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrameIfNeeded()
    }

    override func layout() {
        super.layout()
        reportFrameIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportFrameIfNeeded()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        reportFrameIfNeeded()
    }

    func reportFrameIfNeeded() {
        guard let window else {
            if lastReportedFrame != nil {
                lastReportedFrame = nil
                onFrameChange(nil)
            }
            return
        }

        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow).integral
        guard frameInScreen != lastReportedFrame else {
            return
        }

        lastReportedFrame = frameInScreen
        onFrameChange(frameInScreen)
    }
}

private struct DockGlyphCircle: View {
    let systemName: String
    let outerFill: Color
    let innerFill: Color
    let borderColor: Color
    let iconColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(outerFill)
                .frame(width: 34, height: 34)

            Circle()
                .fill(innerFill)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: borderColor.opacity(0.18), radius: 3, x: 0, y: -1)

            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
}

private struct DockVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .withinWindow
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
