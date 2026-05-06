import AppKit
import Carbon
import Combine
import Foundation
import ServiceManagement

enum MenuBarCommand: String, CaseIterable {
    case showQuickPalette
    case openManager
    case openSettings
    case newNotePin
    case importImage
    case bringAllPinsForward
    case enableLaunchAtLogin
    case disableLaunchAtLogin
    case syncQuickPaletteShortcut
    case quit
}

enum MenuBarBridge {
    static let helperBundleSuffix = ".menubar"
    static let helperAppName = "SpacePinMenuBar.app"
    static let backgroundLaunchArgument = "--spacepin-background"
    private static let commandURLHost = "command"

    static var commandNotifications: [Notification.Name] {
        MenuBarCommand.allCases.map { commandNotification(for: $0) }
    }

    static var launchAtLoginStatusNotifications: [Notification.Name] {
        knownLaunchAtLoginStatuses.map { launchAtLoginStatusNotification(for: $0) }
    }

    static var quickPaletteShortcutNotification: Notification.Name {
        Notification.Name(hostBundleIdentifier() + ".quickPaletteShortcut")
    }

    private static var commandNotificationPrefix: String {
        helperBundleIdentifier() + ".command."
    }

    private static var launchAtLoginStatusNotificationPrefix: String {
        hostBundleIdentifier() + ".launchAtLoginStatus."
    }

    private static let knownLaunchAtLoginStatuses: [SMAppService.Status] = [
        .enabled,
        .requiresApproval,
        .notRegistered,
        .notFound
    ]

    private enum QuickPaletteShortcutUserInfoKey {
        static let keyCode = "keyCode"
        static let modifiers = "modifiers"
    }

    static func helperBundleIdentifier(for bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "") -> String {
        guard !bundleIdentifier.isEmpty else {
            return "com.zoochigames.spacepin.menubar"
        }

        return bundleIdentifier.hasSuffix(helperBundleSuffix)
            ? bundleIdentifier
            : bundleIdentifier + helperBundleSuffix
    }

    static func hostBundleIdentifier(for bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "") -> String {
        guard bundleIdentifier.hasSuffix(helperBundleSuffix) else {
            return bundleIdentifier
        }

        return String(bundleIdentifier.dropLast(helperBundleSuffix.count))
    }

    static func helperAppURL(for hostBundleURL: URL = Bundle.main.bundleURL) -> URL {
        hostBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LoginItems", isDirectory: true)
            .appendingPathComponent(helperAppName, isDirectory: true)
    }

    static func hostAppURL(for helperBundleURL: URL = Bundle.main.bundleURL) -> URL {
        var hostURL = helperBundleURL
        for _ in 0..<4 {
            hostURL.deleteLastPathComponent()
        }

        return hostURL
    }

    static func isBackgroundLaunch(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(backgroundLaunchArgument)
    }

    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static func terminateOtherSpacePinApplications(allowedBundleURLs: [URL]) {
        let allowedPaths = Set(allowedBundleURLs.map(normalizedPath))
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        NSWorkspace.shared.runningApplications
            .filter { runningApplication in
                guard runningApplication.processIdentifier != currentProcessIdentifier,
                      let bundleIdentifier = runningApplication.bundleIdentifier,
                      isSpacePinBundleIdentifier(bundleIdentifier),
                      let bundleURL = runningApplication.bundleURL else {
                    return false
                }

                return !allowedPaths.contains(normalizedPath(for: bundleURL))
            }
            .forEach { runningApplication in
                NSLog(
                    "SpacePin terminating duplicate app: %@ %@",
                    runningApplication.bundleIdentifier ?? "unknown",
                    runningApplication.bundleURL?.path ?? "unknown"
                )
                runningApplication.terminate()
            }
    }

    static func hasOtherSpacePinHostApplication(allowedHostURL: URL) -> Bool {
        let allowedHostPath = normalizedPath(for: allowedHostURL)
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.contains { runningApplication in
            guard runningApplication.processIdentifier != currentProcessIdentifier,
                  let bundleIdentifier = runningApplication.bundleIdentifier,
                  isSpacePinHostBundleIdentifier(bundleIdentifier),
                  let bundleURL = runningApplication.bundleURL else {
                return false
            }

            return normalizedPath(for: bundleURL) != allowedHostPath
        }
    }

    static func post(command: MenuBarCommand) {
        DistributedNotificationCenter.default().postNotificationName(
            commandNotification(for: command),
            object: nil,
            userInfo: nil,
            options: [.deliverImmediately]
        )
    }

    static func open(command: MenuBarCommand) {
        guard let url = commandURL(for: command) else {
            post(command: command)
            return
        }

        NSWorkspace.shared.open(url)
    }

    static func command(from notification: Notification) -> MenuBarCommand? {
        let name = notification.name.rawValue
        guard name.hasPrefix(commandNotificationPrefix) else {
            return nil
        }

        let rawValue = String(name.dropFirst(commandNotificationPrefix.count))
        return MenuBarCommand(rawValue: rawValue)
    }

    static func command(from url: URL) -> MenuBarCommand? {
        guard url.scheme == hostBundleIdentifier(),
              url.host == commandURLHost,
              let rawValue = url.pathComponents.dropFirst().first else {
            return nil
        }

        return MenuBarCommand(rawValue: rawValue)
    }

    static func postLaunchAtLoginStatus(_ status: SMAppService.Status, errorMessage: String?) {
        DistributedNotificationCenter.default().postNotificationName(
            launchAtLoginStatusNotification(for: status),
            object: nil,
            userInfo: nil,
            options: [.deliverImmediately]
        )
    }

    static func launchAtLoginStatus(from notification: Notification) -> (status: SMAppService.Status, errorMessage: String?)? {
        let name = notification.name.rawValue
        guard name.hasPrefix(launchAtLoginStatusNotificationPrefix),
              let rawValue = Int(String(name.dropFirst(launchAtLoginStatusNotificationPrefix.count))),
              let status = SMAppService.Status(rawValue: rawValue) else {
            return nil
        }

        return (status, nil)
    }

    static func postQuickPaletteShortcut(_ shortcut: QuickPaletteShortcut) {
        DistributedNotificationCenter.default().postNotificationName(
            quickPaletteShortcutNotification,
            object: nil,
            userInfo: [
                QuickPaletteShortcutUserInfoKey.keyCode: Int(shortcut.keyCode),
                QuickPaletteShortcutUserInfoKey.modifiers: Int(shortcut.modifiers),
            ],
            options: [.deliverImmediately]
        )
    }

    static func quickPaletteShortcut(from notification: Notification) -> QuickPaletteShortcut? {
        guard notification.name == quickPaletteShortcutNotification,
              let keyCode = notification.userInfo?[QuickPaletteShortcutUserInfoKey.keyCode] as? Int,
              let modifiers = notification.userInfo?[QuickPaletteShortcutUserInfoKey.modifiers] as? Int else {
            return nil
        }

        return QuickPaletteShortcut(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }

    private static func commandNotification(for command: MenuBarCommand) -> Notification.Name {
        Notification.Name(commandNotificationPrefix + command.rawValue)
    }

    private static func commandURL(for command: MenuBarCommand) -> URL? {
        var components = URLComponents()
        components.scheme = hostBundleIdentifier()
        components.host = commandURLHost
        components.path = "/" + command.rawValue
        return components.url
    }

    private static func launchAtLoginStatusNotification(for status: SMAppService.Status) -> Notification.Name {
        Notification.Name(launchAtLoginStatusNotificationPrefix + String(status.rawValue))
    }

    private static func isSpacePinBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == "com.zoochigames.spacepin" ||
            bundleIdentifier == "com.zoochigames.spacepin.debug" ||
            bundleIdentifier == "com.zoochigames.spacepin.menubar" ||
            bundleIdentifier == "com.zoochigames.spacepin.debug.menubar"
    }

    private static func isSpacePinHostBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        bundleIdentifier == "com.zoochigames.spacepin" ||
            bundleIdentifier == "com.zoochigames.spacepin.debug"
    }

    private static func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

@MainActor
enum MenuBarAppLauncher {
    static func launchIfNeeded(bundleIdentifier: String, appURL: URL, arguments: [String], activates: Bool) {
        let expectedURL = appURL.standardizedFileURL
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let hasExpectedApplicationRunning = runningApplications.contains { runningApplication in
            runningApplication.bundleURL?.standardizedFileURL == expectedURL
        }

        guard !hasExpectedApplicationRunning else {
            return
        }

        let hasStaleApplicationRunning = !runningApplications.isEmpty
        runningApplications.forEach { runningApplication in
            runningApplication.terminate()
        }

        func launch() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = activates
            configuration.arguments = arguments

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    NSLog("SpacePin launch failed for %@: %@", appURL.path, error.localizedDescription)
                }
            }
        }

        if hasStaleApplicationRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                launch()
            }
        } else {
            launch()
        }
    }
}

struct QuickPaletteShortcut: Equatable {
    static let `default` = QuickPaletteShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let legacyDefault = QuickPaletteShortcut(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(cmdKey | optionKey | controlKey)
    )

    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers.containsCommandOptionOrControl else {
            return nil
        }

        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var displayString: String {
        modifierDisplayString + Self.keyDisplayString(for: keyCode)
    }

    var menuKeyEquivalent: String {
        Self.menuKeyEquivalents[keyCode] ?? ""
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var modifierFlags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 {
            modifierFlags.insert(.control)
        }
        if modifiers & UInt32(optionKey) != 0 {
            modifierFlags.insert(.option)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            modifierFlags.insert(.shift)
        }
        if modifiers & UInt32(cmdKey) != 0 {
            modifierFlags.insert(.command)
        }
        return modifierFlags
    }

    private var modifierDisplayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        return parts.joined()
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        return modifiers
    }

    private static func keyDisplayString(for keyCode: UInt32) -> String {
        keyDisplayNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyDisplayNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
    ]

    private static let menuKeyEquivalents: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "a",
        UInt32(kVK_ANSI_B): "b",
        UInt32(kVK_ANSI_C): "c",
        UInt32(kVK_ANSI_D): "d",
        UInt32(kVK_ANSI_E): "e",
        UInt32(kVK_ANSI_F): "f",
        UInt32(kVK_ANSI_G): "g",
        UInt32(kVK_ANSI_H): "h",
        UInt32(kVK_ANSI_I): "i",
        UInt32(kVK_ANSI_J): "j",
        UInt32(kVK_ANSI_K): "k",
        UInt32(kVK_ANSI_L): "l",
        UInt32(kVK_ANSI_M): "m",
        UInt32(kVK_ANSI_N): "n",
        UInt32(kVK_ANSI_O): "o",
        UInt32(kVK_ANSI_P): "p",
        UInt32(kVK_ANSI_Q): "q",
        UInt32(kVK_ANSI_R): "r",
        UInt32(kVK_ANSI_S): "s",
        UInt32(kVK_ANSI_T): "t",
        UInt32(kVK_ANSI_U): "u",
        UInt32(kVK_ANSI_V): "v",
        UInt32(kVK_ANSI_W): "w",
        UInt32(kVK_ANSI_X): "x",
        UInt32(kVK_ANSI_Y): "y",
        UInt32(kVK_ANSI_Z): "z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Space): " ",
        UInt32(kVK_Return): "\r",
        UInt32(kVK_Tab): "\t",
        UInt32(kVK_Delete): "\u{8}",
        UInt32(kVK_Escape): "\u{1b}",
        UInt32(kVK_LeftArrow): String(UnicodeScalar(NSLeftArrowFunctionKey)!),
        UInt32(kVK_RightArrow): String(UnicodeScalar(NSRightArrowFunctionKey)!),
        UInt32(kVK_UpArrow): String(UnicodeScalar(NSUpArrowFunctionKey)!),
        UInt32(kVK_DownArrow): String(UnicodeScalar(NSDownArrowFunctionKey)!),
        UInt32(kVK_F1): String(UnicodeScalar(NSF1FunctionKey)!),
        UInt32(kVK_F2): String(UnicodeScalar(NSF2FunctionKey)!),
        UInt32(kVK_F3): String(UnicodeScalar(NSF3FunctionKey)!),
        UInt32(kVK_F4): String(UnicodeScalar(NSF4FunctionKey)!),
        UInt32(kVK_F5): String(UnicodeScalar(NSF5FunctionKey)!),
        UInt32(kVK_F6): String(UnicodeScalar(NSF6FunctionKey)!),
        UInt32(kVK_F7): String(UnicodeScalar(NSF7FunctionKey)!),
        UInt32(kVK_F8): String(UnicodeScalar(NSF8FunctionKey)!),
        UInt32(kVK_F9): String(UnicodeScalar(NSF9FunctionKey)!),
        UInt32(kVK_F10): String(UnicodeScalar(NSF10FunctionKey)!),
        UInt32(kVK_F11): String(UnicodeScalar(NSF11FunctionKey)!),
        UInt32(kVK_F12): String(UnicodeScalar(NSF12FunctionKey)!),
    ]
}

private extension UInt32 {
    var containsCommandOptionOrControl: Bool {
        self & UInt32(cmdKey | optionKey | controlKey) != 0
    }
}

final class QuickPaletteShortcutStore: ObservableObject {
    private enum DefaultsKey {
        static let keyCode = "quickPaletteShortcut.keyCode"
        static let modifiers = "quickPaletteShortcut.modifiers"
    }

    @Published private(set) var shortcut: QuickPaletteShortcut

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let storedKeyCode = userDefaults.object(forKey: DefaultsKey.keyCode) as? Int
        let storedModifiers = userDefaults.object(forKey: DefaultsKey.modifiers) as? Int

        if let storedKeyCode, let storedModifiers {
            let storedShortcut = QuickPaletteShortcut(
                keyCode: UInt32(storedKeyCode),
                modifiers: UInt32(storedModifiers)
            )
            if storedShortcut == .legacyDefault {
                shortcut = .default
                userDefaults.removeObject(forKey: DefaultsKey.keyCode)
                userDefaults.removeObject(forKey: DefaultsKey.modifiers)
            } else {
                shortcut = storedShortcut
            }
        } else {
            shortcut = .default
        }
    }

    func setShortcut(_ shortcut: QuickPaletteShortcut) {
        guard self.shortcut != shortcut else {
            return
        }

        self.shortcut = shortcut
        userDefaults.set(Int(shortcut.keyCode), forKey: DefaultsKey.keyCode)
        userDefaults.set(Int(shortcut.modifiers), forKey: DefaultsKey.modifiers)
        MenuBarBridge.postQuickPaletteShortcut(shortcut)
    }

    func resetToDefault() {
        setShortcut(.default)
    }
}

final class QuickPaletteHotKeyController {
    private static let hotKeySignature = fourCharacterCode("SPQP")
    private static let hotKeyIDValue: UInt32 = 1

    private let shortcutStore: QuickPaletteShortcutStore
    private let action: @MainActor @Sendable () -> Void
    private var shortcutCancellable: AnyCancellable?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(
        shortcutStore: QuickPaletteShortcutStore,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.shortcutStore = shortcutStore
        self.action = action
        installEventHandler()
        shortcutCancellable = shortcutStore.$shortcut.sink { [weak self] shortcut in
            self?.registerHotKey(shortcut)
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let eventTarget = GetApplicationEventTarget()
        let handlerStatus = InstallEventHandler(
            eventTarget,
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<QuickPaletteHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return controller.handleHotKey(event)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            NSLog("SpacePin quick palette hot key handler registration failed: %d", handlerStatus)
            return
        }
    }

    private func registerHotKey(_ shortcut: QuickPaletteShortcut) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIDValue
        )
        var registeredHotKeyRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKeyRef
        )

        guard hotKeyStatus == noErr else {
            NSLog("SpacePin quick palette hot key registration failed: %d", hotKeyStatus)
            return
        }

        NSLog("SpacePin quick palette hot key registered: %@", shortcut.displayString)
        hotKeyRef = registeredHotKeyRef
    }

    private func handleHotKey(_ event: EventRef) -> OSStatus {
        var receivedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedHotKeyID
        )

        guard status == noErr,
              receivedHotKeyID.signature == Self.hotKeySignature,
              receivedHotKeyID.id == Self.hotKeyIDValue else {
            return OSStatus(eventNotHandledErr)
        }

        NSLog("SpacePin quick palette hot key pressed")
        Task { @MainActor [action] in
            action()
        }
        return noErr
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.unicodeScalars.prefix(4).reduce(0) { partialResult, scalar in
            (partialResult << 8) + OSType(scalar.value)
        }
    }
}
