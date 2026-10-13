import Foundation

enum TestInterval: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case thirtyMinutes
    case sixtyMinutes

    static let standard = TestInterval.thirtyMinutes

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .sixtyMinutes: return 60 * 60
        }
    }

    var label: String {
        switch self {
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .sixtyMinutes: return "Every 60 minutes"
        }
    }
}

enum SlowDownloadAlert: String, CaseIterable, Identifiable {
    case off
    case below10Megabits
    case below25Megabits
    case below50Megabits
    case below100Megabits

    static let standard = SlowDownloadAlert.off

    var id: String { rawValue }

    var limit: SlowDownloadLimit {
        switch self {
        case .off: return .off
        case .below10Megabits: return .below(megabitsPerSecond: 10)
        case .below25Megabits: return .below(megabitsPerSecond: 25)
        case .below50Megabits: return .below(megabitsPerSecond: 50)
        case .below100Megabits: return .below(megabitsPerSecond: 100)
        }
    }

    var label: String {
        switch limit {
        case .off: return "Off"
        case .below(let megabitsPerSecond): return "Below \(formatNoDecimals(megabitsPerSecond)) Mbps"
        }
    }
}

/// The download speed of the internet contract. The statistics compare the measured download with it.
enum ContractSpeed: Equatable {
    case notSet
    case megabitsPerSecond(Int)

    /// 0 or a negative number means that no contract speed is set.
    init(storedMegabitsPerSecond: Int) {
        self = storedMegabitsPerSecond > 0 ? .megabitsPerSecond(storedMegabitsPerSecond) : .notSet
    }

    var storedMegabitsPerSecond: Int {
        switch self {
        case .notSet: return 0
        case .megabitsPerSecond(let megabitsPerSecond): return megabitsPerSecond
        }
    }
}

enum SlowDownloadLimit: Equatable {
    case off
    case below(megabitsPerSecond: Double)
}

/// The time span that the panel and the export use.
enum HistoryRange: String, CaseIterable, Identifiable {
    case today
    case lastSevenDays
    case lastThirtyDays
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .lastSevenDays: return "7 days"
        case .lastThirtyDays: return "30 days"
        case .all: return "All"
        }
    }

    func start(now: Date, calendar: Calendar) -> RangeStart {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return .from(startOfToday)
        case .lastSevenDays:
            return .from(daysBefore(startOfToday, dayCount: 6, calendar: calendar))
        case .lastThirtyDays:
            return .from(daysBefore(startOfToday, dayCount: 29, calendar: calendar))
        case .all:
            return .unbounded
        }
    }

    private func daysBefore(_ date: Date, dayCount: Int, calendar: Calendar) -> Date {
        guard let earlierDate = calendar.date(byAdding: .day, value: -dayCount, to: date) else {
            preconditionFailure("Calendar \(calendar.identifier) cannot go back \(dayCount) days from \(date)")
        }
        return earlierDate
    }
}

enum RangeStart: Equatable {
    case unbounded
    case from(Date)
}
