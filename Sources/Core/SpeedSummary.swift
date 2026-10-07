import Foundation

struct ValueSpread: Equatable {
    let average: Double
    let minimum: Double
    let maximum: Double
}

struct SpeedSummary: Equatable {
    let measuredCount: Int
    let failedCount: Int
    let download: ValueSpread
    let upload: ValueSpread
    let ping: ValueSpread
}

enum RangeSummary: Equatable {
    case noTests
    case onlyFailures(failedCount: Int)
    case measured(SpeedSummary)
}

/// Pure: computes the numbers the panel shows for a list of records.
func summarize(_ records: [TestRecord]) -> RangeSummary {
    var measurements: [SpeedMeasurement] = []
    var failedCount = 0
    for record in records {
        switch record.result {
        case .measured(let measurement):
            measurements.append(measurement)
        case .failed:
            failedCount += 1
        }
    }
    guard let firstMeasurement = measurements.first else {
        return failedCount == 0 ? .noTests : .onlyFailures(failedCount: failedCount)
    }
    let otherMeasurements = measurements.dropFirst()
    return .measured(SpeedSummary(
        measuredCount: measurements.count,
        failedCount: failedCount,
        download: spread(first: firstMeasurement.downloadMegabitsPerSecond, others: otherMeasurements.map(\.downloadMegabitsPerSecond)),
        upload: spread(first: firstMeasurement.uploadMegabitsPerSecond, others: otherMeasurements.map(\.uploadMegabitsPerSecond)),
        ping: spread(first: firstMeasurement.baseRoundTripTimeMilliseconds, others: otherMeasurements.map(\.baseRoundTripTimeMilliseconds)),
    ))
}

/// Takes the first value apart, so the list is never empty.
private func spread(first: Double, others: [Double]) -> ValueSpread {
    let total = others.reduce(first, +)
    return ValueSpread(
        average: total / Double(others.count + 1),
        minimum: others.reduce(first, min),
        maximum: others.reduce(first, max),
    )
}
