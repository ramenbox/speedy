import Foundation

let demoComputerName = "Office Mac mini"
let demoDayCount = 30
let demoTestIntervalMinutes = 30

/// A fixed pseudo random sequence, so every run draws the same demo history.
struct DemoRandomSequence {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// A value in 0..<1.
    mutating func nextUnit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }

    mutating func next(around center: Double, spread: Double) -> Double {
        return center + (nextUnit() * 2 - 1) * spread
    }
}

/// Test times every 30 minutes for the last 30 days, up to the last full half hour before now.
func demoTestTimes(now: Date, calendar: Calendar) -> [Date] {
    var slotComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
    let minute = slotComponents.minute ?? 0
    slotComponents.minute = minute - minute % demoTestIntervalMinutes
    guard let lastSlot = calendar.date(from: slotComponents) else {
        preconditionFailure("Calendar cannot round \(now) to a half hour")
    }
    let slotCount = demoDayCount * 24 * 60 / demoTestIntervalMinutes
    return (0..<slotCount).reversed().map { slotIndex in
        lastSlot.addingTimeInterval(-Double(slotIndex * demoTestIntervalMinutes * 60))
    }
}

/// A plausible office line: slower during office hours, a few failed tests.
func makeDemoRecords(now: Date, calendar: Calendar) -> [TestRecord] {
    var random = DemoRandomSequence(seed: 20_260_917)
    let endpoints = ["defra1-edge-fx-028.aaplimg.com", "nlams2-edge-fx-020.aaplimg.com", "defra3-edge-bx-031.aaplimg.com"]
    return demoTestTimes(now: now, calendar: calendar).map { startedAt in
        let hour = calendar.component(.hour, from: startedAt)
        let officeHoursLoad = (9...17).contains(hour) ? 0.72 : 1.0
        guard random.nextUnit() > 0.012 else {
            return TestRecord(startedAt: startedAt, computerName: demoComputerName, result: .failed(message: "No internet connection"))
        }
        let measurement = SpeedMeasurement(
            downloadMegabitsPerSecond: random.next(around: 175, spread: 18) * officeHoursLoad,
            uploadMegabitsPerSecond: random.next(around: 212, spread: 14) * (0.15 + 0.85 * officeHoursLoad),
            responsivenessRoundTripsPerMinute: random.next(around: 820, spread: 180),
            baseRoundTripTimeMilliseconds: random.next(around: 18, spread: 3) / officeHoursLoad,
            interfaceType: "ethernet",
            interfaceName: "en0",
            testEndpoint: endpoints[Int(random.nextUnit() * Double(endpoints.count))],
        )
        return TestRecord(startedAt: startedAt, computerName: demoComputerName, result: .measured(measurement))
    }
}
