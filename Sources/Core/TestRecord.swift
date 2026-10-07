import Foundation

/// The values of one successful networkQuality test.
struct SpeedMeasurement: Equatable {
    let downloadMegabitsPerSecond: Double
    let uploadMegabitsPerSecond: Double
    /// Higher is better. Below 200 is low.
    let responsivenessRoundTripsPerMinute: Double
    /// The ping. Lower is better.
    let baseRoundTripTimeMilliseconds: Double
    /// "wifi", "ethernet", or "wifi+ethernet" when the test used more than one type.
    let interfaceType: String
    let interfaceName: String
    let testEndpoint: String
}

enum TestResult: Equatable {
    case measured(SpeedMeasurement)
    /// No measurement was possible. The message tells the user why.
    case failed(message: String)
}

/// One stored test. A record is a fact and does not change after it is made.
struct TestRecord: Equatable {
    let startedAt: Date
    let computerName: String
    let result: TestResult
}
