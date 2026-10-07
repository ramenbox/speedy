import Foundation

enum SpeedAlertDecision: Equatable {
    case noAlert
    case slowDownload(megabitsPerSecond: Double, limitMegabitsPerSecond: Double)
    case testFailed(message: String)
}

/// Pure: decides whether a finished test needs a notification.
/// It alerts only when the state changes, so a long slow period gives one notification, not one per test.
func decideSpeedAlert(
    current: TestResult,
    previous: TestResult?,
    slowDownloadLimit: SlowDownloadLimit,
    alertsOnFailedTest: Bool,
) -> SpeedAlertDecision {
    switch current {
    case .measured(let measurement):
        return decideSlowDownloadAlert(measurement: measurement, previous: previous, limit: slowDownloadLimit)
    case .failed(let message):
        let previousTestAlsoFailed: Bool
        switch previous {
        case .some(.failed):
            previousTestAlsoFailed = true
        case .some(.measured), .none:
            previousTestAlsoFailed = false
        }
        return alertsOnFailedTest && !previousTestAlsoFailed ? .testFailed(message: message) : .noAlert
    }
}

private func decideSlowDownloadAlert(
    measurement: SpeedMeasurement,
    previous: TestResult?,
    limit: SlowDownloadLimit,
) -> SpeedAlertDecision {
    switch limit {
    case .off:
        return .noAlert
    case .below(let limitMegabitsPerSecond):
        guard measurement.downloadMegabitsPerSecond < limitMegabitsPerSecond else {
            return .noAlert
        }
        switch previous {
        case .some(.measured(let previousMeasurement)) where previousMeasurement.downloadMegabitsPerSecond < limitMegabitsPerSecond:
            return .noAlert
        case .some(.measured), .some(.failed), .none:
            return .slowDownload(megabitsPerSecond: measurement.downloadMegabitsPerSecond, limitMegabitsPerSecond: limitMegabitsPerSecond)
        }
    }
}
