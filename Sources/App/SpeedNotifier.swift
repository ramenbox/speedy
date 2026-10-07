import Foundation
import UserNotifications

enum NotificationPermission: Equatable {
    case notAsked
    case allowed
    case denied
    /// macOS reported a state that this version of Speedy does not know.
    case unknown
}

/// Sends the slow speed and failed test notifications.
final class SpeedNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Calls completion on the main actor.
    func readPermission(completion: @escaping @MainActor (NotificationPermission) -> Void) {
        center.getNotificationSettings { settings in
            let permission = Self.permission(from: settings.authorizationStatus)
            Task { @MainActor in
                completion(permission)
            }
        }
    }

    /// Shows the macOS permission prompt the first time. Later calls return the saved answer.
    func requestPermission(completion: @escaping @MainActor (NotificationPermission) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // The granted flag and error are not used: the settings are the source of truth after the prompt.
            self.readPermission(completion: completion)
        }
    }

    func send(_ decision: SpeedAlertDecision) {
        let content = UNMutableNotificationContent()
        switch decision {
        case .noAlert:
            return
        case .slowDownload(let megabitsPerSecond, let limitMegabitsPerSecond):
            content.title = "Slow internet"
            content.body = "Download is \(formatOneDecimal(megabitsPerSecond)) Mbps, below your limit of \(formatNoDecimals(limitMegabitsPerSecond)) Mbps."
        case .testFailed(let message):
            content.title = "Speed test failed"
            content.body = message
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                // A notification that macOS rejects is not a reason to stop the tests.
                NSLog("Speedy could not send a notification: %@", error.localizedDescription)
            }
        }
    }

    /// Shows the notification also when Speedy is the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }

    private static func permission(from status: UNAuthorizationStatus) -> NotificationPermission {
        switch status {
        case .notDetermined:
            return .notAsked
        case .authorized, .provisional:
            return .allowed
        case .denied:
            return .denied
        @unknown default:
            return .unknown
        }
    }
}
