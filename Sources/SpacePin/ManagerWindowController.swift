import AppKit
import SwiftUI

@MainActor
final class ManagerWindowController: NSWindowController, NSWindowDelegate {
    init(coordinator: AppCoordinator) {
        let hostingController = NSHostingController(
            rootView: ManagerView()
                .environmentObject(coordinator)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SpacePin"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 500))
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SpacePinManagerWindow")

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
