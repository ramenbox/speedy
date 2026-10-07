import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case enabled
    /// Registered, but the user must turn it on in System Settings > General > Login Items.
    case requiresApproval
    case disabled
    /// macOS reported a state that this version of Speedy does not know.
    case unknown
}

enum LoginItemChange: Equatable {
    case changed(LoginItemState)
    case failed(message: String)
}

func readLoginItemState() -> LoginItemState {
    switch SMAppService.mainApp.status {
    case .enabled:
        return .enabled
    case .requiresApproval:
        return .requiresApproval
    case .notRegistered, .notFound:
        return .disabled
    @unknown default:
        return .unknown
    }
}

/// Turns start at login on when it is off, and off when it is on.
func toggleLoginItem() -> LoginItemChange {
    let loginItemService = SMAppService.mainApp
    do {
        switch readLoginItemState() {
        case .enabled, .requiresApproval:
            try loginItemService.unregister()
        case .disabled:
            try loginItemService.register()
        case .unknown:
            return .failed(message: "macOS reports an unknown login item state.")
        }
    } catch {
        return .failed(message: "\(error.localizedDescription) Move Speedy to the Applications folder and try again.")
    }
    return .changed(readLoginItemState())
}
