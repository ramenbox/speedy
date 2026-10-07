import AppKit
import UniformTypeIdentifiers

enum ExportDestination: Equatable {
    case chosen(URL)
    case cancelled
}

enum Confirmation: Equatable {
    case confirmed
    case cancelled
}

/// The modal windows of Speedy. Each call waits for the user.
@MainActor
enum Dialogs {
    static func chooseExportDestination(suggestedFileName: String) -> ExportDestination {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Export CSV"
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        switch panel.runModal() {
        case .OK:
            guard let url = panel.url else {
                preconditionFailure("NSSavePanel returned OK without a URL")
            }
            return .chosen(url)
        default:
            return .cancelled
        }
    }

    static func confirmDeleteHistory() -> Confirmation {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Delete the test history?"
        alert.informativeText = "This removes all stored results from Speedy. Export a CSV first if you want to keep them. You cannot undo this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .confirmed
        default:
            return .cancelled
        }
    }
}
