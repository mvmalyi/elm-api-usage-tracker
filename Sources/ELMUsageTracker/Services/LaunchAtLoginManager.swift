import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String? {
        guard isRunningFromAppBundle else {
            return "Build & run the .app bundle to enable Launch at Login."
        }
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Approve in System Settings → General → Login Items."
        default:
            return nil
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
