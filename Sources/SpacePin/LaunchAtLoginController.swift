import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    private enum DefaultsKey {
        static let suppressPrompt = "launchAtLoginPromptSuppressed"
    }

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let service: SMAppService
    private let userDefaults: UserDefaults

    init(
        service: SMAppService = .loginItem(identifier: MenuBarBridge.helperBundleIdentifier()),
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.userDefaults = userDefaults
        status = service.status
    }

    var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var shouldPromptOnLaunch: Bool {
        !isEnabled && !isPromptSuppressed
    }

    var isPromptSuppressed: Bool {
        userDefaults.bool(forKey: DefaultsKey.suppressPrompt)
    }

    func refreshStatus() {
        status = service.status
    }

    func setPromptSuppressed(_ suppressed: Bool) {
        userDefaults.set(suppressed, forKey: DefaultsKey.suppressPrompt)
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil

        do {
            if enabled {
                if service.status == .enabled || service.status == .requiresApproval {
                    refreshStatus()
                    return
                }

                try service.register()
            } else {
                if service.status == .notRegistered || service.status == .notFound {
                    refreshStatus()
                    return
                }

                try service.unregister()
            }

            refreshStatus()
        } catch {
            refreshStatus()
            errorMessage = L10n.format(
                "error.launch_at_login_update_failed",
                fallback: "Couldn't update launch at login: %@",
                error.localizedDescription
            )
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
