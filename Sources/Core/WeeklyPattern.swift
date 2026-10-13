import Foundation

/// One hour on one day of the week. `weekday` uses the Calendar numbering: 1 is Sunday, 7 is Saturday.
struct WeekdayHour: Hashable {
    let weekday: Int
    let hour: Int
}

struct HourlyAverage: Equatable {
    let averageDownloadMegabitsPerSecond: Double
    let measuredCount: Int
}

enum WeeklyPattern: Equatable {
    case noMeasurements
    case measured(averages: [WeekdayHour: HourlyAverage], slowest: Double, fastest: Double)
}

/// Pure: the average download for each weekday and hour. Failed tests are not part of an average.
func makeWeeklyPattern(_ records: [TestRecord], calendar: Calendar) -> WeeklyPattern {
    var totals: [WeekdayHour: (sum: Double, count: Int)] = [:]
    for record in records {
        switch record.result {
        case .measured(let measurement):
            let components = calendar.dateComponents([.weekday, .hour], from: record.startedAt)
            guard let weekday = components.weekday, let hour = components.hour else {
                preconditionFailure("Calendar \(calendar.identifier) gives no weekday or hour for \(record.startedAt)")
            }
            let key = WeekdayHour(weekday: weekday, hour: hour)
            let previous = totals[key] ?? (sum: 0, count: 0)
            totals[key] = (sum: previous.sum + measurement.downloadMegabitsPerSecond, count: previous.count + 1)
        case .failed:
            continue
        }
    }
    let averages = totals.mapValues { total in
        HourlyAverage(averageDownloadMegabitsPerSecond: total.sum / Double(total.count), measuredCount: total.count)
    }
    let speeds = averages.values.map(\.averageDownloadMegabitsPerSecond)
    guard let slowest = speeds.min(), let fastest = speeds.max() else {
        return .noMeasurements
    }
    return .measured(averages: averages, slowest: slowest, fastest: fastest)
}

/// Pure: puts a speed into one of `levelCount` equal steps between slowest and fastest.
/// Level 0 is the slowest step. When all speeds are equal, the speed is in the middle step.
func speedLevel(_ megabitsPerSecond: Double, slowest: Double, fastest: Double, levelCount: Int) -> Int {
    precondition(levelCount > 0, "speedLevel needs at least one level")
    guard fastest > slowest else {
        return levelCount / 2
    }
    let position = (megabitsPerSecond - slowest) / (fastest - slowest)
    return min(levelCount - 1, max(0, Int(position * Double(levelCount))))
}
