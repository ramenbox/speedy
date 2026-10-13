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
    let responsiveness: ValueSpread
}

/// The measured download compared with the speed of the internet contract.
struct ContractComparison: Equatable {
    let contractMegabitsPerSecond: Double
    let averagePercent: Double
    let minimumPercent: Double
}

/// Pure: the average and minimum download as a percentage of the contract speed.
func compareToContract(download: ValueSpread, contractMegabitsPerSecond: Double) -> ContractComparison {
    precondition(contractMegabitsPerSecond > 0, "The contract speed must be above 0")
    return ContractComparison(
        contractMegabitsPerSecond: contractMegabitsPerSecond,
        averagePercent: download.average / contractMegabitsPerSecond * 100,
        minimumPercent: download.minimum / contractMegabitsPerSecond * 100,
    )
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
        responsiveness: spread(first: firstMeasurement.responsivenessRoundTripsPerMinute, others: otherMeasurements.map(\.responsivenessRoundTripsPerMinute)),
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
