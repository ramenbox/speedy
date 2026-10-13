import Foundation

/// Checks for the Speedy core logic. Run them with ./checks.sh.
/// The Command Line Tools have no XCTest, so this is a plain program that exits with 1 when a check fails.
final class CheckRun {
    private(set) var passedCount = 0
    private(set) var failures: [String] = []

    func expect(_ condition: Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
        guard condition else {
            failures.append("\(name) (\(file):\(line))")
            return
        }
        passedCount += 1
    }

    func expectEqual<Value: Equatable>(_ actual: Value, _ expected: Value, _ name: String, file: StaticString = #file, line: UInt = #line) {
        guard actual == expected else {
            failures.append("\(name) (\(file):\(line))\n    actual:   \(actual)\n    expected: \(expected)")
            return
        }
        passedCount += 1
    }

    func expectSuccess<Failure: Error>(_ result: Result<Void, Failure>, _ name: String, file: StaticString = #file, line: UInt = #line) {
        switch result {
        case .success:
            passedCount += 1
        case .failure(let error):
            failures.append("\(name) (\(file):\(line))\n    error: \(error)")
        }
    }
}

@main
enum SpeedyChecks {
    static func main() {
        let run = CheckRun()
        checkNetworkQualityParser(run)
        checkCsv(run)
        checkSummary(run)
        checkAlertDecision(run)
        checkHistoryRange(run)
        checkStore(run)
        checkTextFormatting(run)
        checkScheduledTestDecision(run)
        checkContractComparison(run)
        checkWeeklyPattern(run)
        for failure in run.failures {
            print("FAIL \(failure)")
        }
        print("\(run.passedCount) passed, \(run.failures.count) failed")
        exit(run.failures.isEmpty ? 0 : 1)
    }
}

// MARK: - Fixtures

let sampleMeasurement = SpeedMeasurement(
    downloadMegabitsPerSecond: 87.0,
    uploadMegabitsPerSecond: 98.9,
    responsivenessRoundTripsPerMinute: 146,
    baseRoundTripTimeMilliseconds: 13.5,
    interfaceType: "wifi",
    interfaceName: "en0",
    testEndpoint: "defra1-edge-fx-035.aaplimg.com",
)

func measurement(downloadMegabitsPerSecond: Double) -> SpeedMeasurement {
    return SpeedMeasurement(
        downloadMegabitsPerSecond: downloadMegabitsPerSecond,
        uploadMegabitsPerSecond: 50,
        responsivenessRoundTripsPerMinute: 500,
        baseRoundTripTimeMilliseconds: 20,
        interfaceType: "wifi",
        interfaceName: "en0",
        testEndpoint: "test.example",
    )
}

func timestamp(_ text: String) -> Date {
    guard let date = csvTimestampFormatter.date(from: text) else {
        preconditionFailure("Invalid fixture timestamp \(text)")
    }
    return date
}

func temporaryFileURL(name: String) -> URL {
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("speedy-checks-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name, isDirectory: false)
}

func openTemporaryStore(_ run: CheckRun) -> ResultStore {
    switch ResultStore.open(fileURL: temporaryFileURL(name: "speedy.sqlite")) {
    case .success(let store):
        return store
    case .failure(let error):
        preconditionFailure("Could not open a temporary store: \(error.message)")
    }
}

// MARK: - networkQuality output

func checkNetworkQualityParser(_ run: CheckRun) {
    let measuredOutput = """
        {"dl_throughput": 87000000, "ul_throughput": 98900000, "responsiveness": 146, "base_rtt": 13.5,
         "interface_name": "en0", "test_endpoint": "defra1-edge-fx-035.aaplimg.com",
         "other": {"interface-type": {"wifi": 188}}}
        """
    run.expectEqual(parseNetworkQualityOutput(Data(measuredOutput.utf8)), .success(sampleMeasurement), "parser reads a measurement")

    let twoInterfacesOutput = measuredOutput.replacingOccurrences(of: #"{"wifi": 188}"#, with: #"{"wifi": 10, "ethernet": 5}"#)
    let twoInterfacesType = parseNetworkQualityOutput(Data(twoInterfacesOutput.utf8)).map(\.interfaceType)
    run.expectEqual(twoInterfacesType, .success("ethernet+wifi"), "parser joins interface types")

    let offlineOutput = #"{ "end_date" : "2026-09-10 18:51:18.096", "error_code" : -1009, "error_domain" : "NSURLErrorDomain" }"#
    let offlineResult = parseNetworkQualityOutput(Data(offlineOutput.utf8))
    run.expectEqual(offlineResult, .failure(.networkError(domain: "NSURLErrorDomain", code: -1009)), "parser reads a network error")
    run.expectEqual(NetworkQualityFailure.networkError(domain: "NSURLErrorDomain", code: -1009).message, "No internet connection", "offline message is plain")

    let missingFieldOutput = measuredOutput.replacingOccurrences(of: #""dl_throughput": 87000000,"#, with: "")
    switch parseNetworkQualityOutput(Data(missingFieldOutput.utf8)) {
    case .failure(.outputUnreadable(let problem, _)):
        run.expectEqual(problem, "Field dl_throughput is missing", "parser names a missing field")
    case .success, .failure:
        run.expect(false, "parser fails on a missing field")
    }

    let negativeOutput = measuredOutput.replacingOccurrences(of: "\"base_rtt\": 13.5", with: "\"base_rtt\": -1")
    run.expectEqual(
        parseNetworkQualityOutput(Data(negativeOutput.utf8)),
        .failure(.invalidField(name: "base_rtt", problem: "has an unexpected value: -1.0")),
        "parser rejects a negative number",
    )

    let emptyInterfaceOutput = measuredOutput.replacingOccurrences(of: #""interface_name": "en0""#, with: #""interface_name": """#)
    run.expectEqual(
        parseNetworkQualityOutput(Data(emptyInterfaceOutput.utf8)),
        .failure(.invalidField(name: "interface_name", problem: "is empty")),
        "parser rejects an empty text field",
    )

    switch parseNetworkQualityOutput(Data("not json".utf8)) {
    case .failure(.outputUnreadable(let problem, let detail)):
        run.expectEqual(problem, "networkQuality output is not valid JSON", "parser names invalid JSON")
        run.expectEqual(detail, "not json", "parser keeps the output as detail")
    case .success, .failure:
        run.expect(false, "parser fails on invalid JSON")
    }
}

// MARK: - CSV

func checkCsv(_ run: CheckRun) {
    run.expectEqual(splitCsvLine(#"a,"b,c","say ""hi""",,"#), .success(["a", "b,c", #"say "hi""#, "", ""]), "split handles quotes and empty fields")
    run.expectEqual(splitCsvLine(#"a,"open"#), .failure(.unterminatedQuote), "split rejects an open quote")
    run.expectEqual(splitCsvLine(#""a"b"#), .failure(.textAfterClosingQuote(characterOffset: 3)), "split rejects text after a closing quote")

    let measuredRecord = TestRecord(startedAt: timestamp("2026-09-10 14:20:31"), computerName: "Office \"Mac\"", result: .measured(sampleMeasurement))
    run.expectEqual(
        csvLine(for: measuredRecord),
        #"2026-09-10 14:20:31,"Office ""Mac""",ok,87.0,98.9,146,13.5,wifi,en0,defra1-edge-fx-035.aaplimg.com,"""#,
        "export writes a measured line in the old format",
    )
    let failedRecord = TestRecord(startedAt: timestamp("2026-09-10 18:51:18"), computerName: "Mac", result: .failed(message: "No internet\nconnection"))
    run.expectEqual(
        csvLine(for: failedRecord),
        #"2026-09-10 18:51:18,"Mac",failed,,,,,,,,"No internet connection""#,
        "export writes a failed line on one line",
    )
    run.expectEqual(csvDocument(for: []), resultsCsvHeader + "\n", "export of no records is the header only")
}

// MARK: - Summary

func checkSummary(_ run: CheckRun) {
    let start = timestamp("2026-09-10 10:00:00")
    run.expectEqual(summarize([]), .noTests, "summary of nothing")
    let failed = TestRecord(startedAt: start, computerName: "Mac", result: .failed(message: "offline"))
    run.expectEqual(summarize([failed, failed]), .onlyFailures(failedCount: 2), "summary of only failures")
    let records = [
        TestRecord(startedAt: start, computerName: "Mac", result: .measured(measurement(downloadMegabitsPerSecond: 60))),
        failed,
        TestRecord(startedAt: start, computerName: "Mac", result: .measured(measurement(downloadMegabitsPerSecond: 90))),
    ]
    switch summarize(records) {
    case .measured(let summary):
        run.expectEqual(summary.measuredCount, 2, "summary counts measured tests")
        run.expectEqual(summary.failedCount, 1, "summary counts failed tests")
        run.expectEqual(summary.download, ValueSpread(average: 75, minimum: 60, maximum: 90), "summary spreads download")
        run.expectEqual(summary.responsiveness, ValueSpread(average: 500, minimum: 500, maximum: 500), "summary spreads responsiveness")
    case .noTests, .onlyFailures:
        run.expect(false, "summary with measurements is measured")
    }
}

// MARK: - Alerts

func checkAlertDecision(_ run: CheckRun) {
    let slow = TestResult.measured(measurement(downloadMegabitsPerSecond: 20))
    let fast = TestResult.measured(measurement(downloadMegabitsPerSecond: 80))
    let failed = TestResult.failed(message: "No internet connection")
    let limit = SlowDownloadLimit.below(megabitsPerSecond: 50)

    run.expectEqual(decideSpeedAlert(current: slow, previous: fast, slowDownloadLimit: limit, alertsOnFailedTest: false),
                    .slowDownload(megabitsPerSecond: 20, limitMegabitsPerSecond: 50), "alert when the speed becomes slow")
    run.expectEqual(decideSpeedAlert(current: slow, previous: nil, slowDownloadLimit: limit, alertsOnFailedTest: false),
                    .slowDownload(megabitsPerSecond: 20, limitMegabitsPerSecond: 50), "alert on the first slow test")
    run.expectEqual(decideSpeedAlert(current: slow, previous: slow, slowDownloadLimit: limit, alertsOnFailedTest: false),
                    .noAlert, "no second alert while the speed stays slow")
    run.expectEqual(decideSpeedAlert(current: fast, previous: slow, slowDownloadLimit: limit, alertsOnFailedTest: false),
                    .noAlert, "no alert for a fast test")
    run.expectEqual(decideSpeedAlert(current: slow, previous: fast, slowDownloadLimit: .off, alertsOnFailedTest: true),
                    .noAlert, "no slow alert when the limit is off")
    run.expectEqual(decideSpeedAlert(current: failed, previous: fast, slowDownloadLimit: .off, alertsOnFailedTest: true),
                    .testFailed(message: "No internet connection"), "alert when a test fails")
    run.expectEqual(decideSpeedAlert(current: failed, previous: failed, slowDownloadLimit: .off, alertsOnFailedTest: true),
                    .noAlert, "no second alert while tests keep failing")
    run.expectEqual(decideSpeedAlert(current: failed, previous: fast, slowDownloadLimit: limit, alertsOnFailedTest: false),
                    .noAlert, "no failure alert when it is off")
}

// MARK: - History range

func checkHistoryRange(_ run: CheckRun) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    let now = timestamp("2026-09-16 15:30:00")
    run.expectEqual(HistoryRange.today.start(now: now, calendar: calendar), .from(timestamp("2026-09-16 00:00:00")), "today starts at midnight")
    run.expectEqual(HistoryRange.lastSevenDays.start(now: now, calendar: calendar), .from(timestamp("2026-09-10 00:00:00")), "7 days include today")
    run.expectEqual(HistoryRange.lastThirtyDays.start(now: now, calendar: calendar), .from(timestamp("2026-08-18 00:00:00")), "30 days include today")
    run.expectEqual(HistoryRange.all.start(now: now, calendar: calendar), .unbounded, "all has no start")
}

// MARK: - Store

func checkStore(_ run: CheckRun) {
    let store = openTemporaryStore(run)
    let older = TestRecord(startedAt: timestamp("2026-09-09 10:00:00"), computerName: "Mac", result: .measured(sampleMeasurement))
    let newer = TestRecord(startedAt: timestamp("2026-09-10 10:00:00"), computerName: "Mac", result: .failed(message: "No internet connection"))

    run.expectEqual(store.insert([newer, older]), .success(2), "store inserts records")
    run.expectEqual(store.insert([older]), .success(0), "store skips a duplicate record")
    run.expectEqual(store.records(from: .unbounded, maximumCount: 10), .success([older, newer]), "store reads all records oldest first")
    run.expectEqual(store.records(from: .from(timestamp("2026-09-10 00:00:00")), maximumCount: 10), .success([newer]), "store reads from a start date")
    run.expectEqual(store.records(from: .unbounded, maximumCount: 1), .failure(.tooManyRecords(limit: 1)), "store fails closed over the limit")
    run.expectEqual(store.newestRecords(count: 1), .success([newer]), "store reads the newest record")

    run.expectSuccess(store.deleteAllResults(), "store deletes the history")
    run.expectEqual(store.records(from: .unbounded, maximumCount: 10), .success([]), "history is empty after delete")

    let reopenURL = temporaryFileURL(name: "reopen.sqlite")
    switch ResultStore.open(fileURL: reopenURL).flatMap({ firstStore in firstStore.insert([older]) }) {
    case .success:
        run.expectEqual(ResultStore.open(fileURL: reopenURL).flatMap { $0.newestRecords(count: 5) }, .success([older]), "store keeps records after reopen")
    case .failure(let error):
        run.expect(false, "store opens a new file: \(error.message)")
    }
}

func checkTextFormatting(_ run: CheckRun) {
    run.expectEqual(formatElapsedTime(0), "0:00", "elapsed time at start")
    run.expectEqual(formatElapsedTime(7.9), "0:07", "elapsed time drops the fraction")
    run.expectEqual(formatElapsedTime(65), "1:05", "elapsed time over one minute")
    run.expectEqual(formatElapsedTime(-3), "0:00", "negative elapsed time")
}

// MARK: - Scheduled test decision

func checkScheduledTestDecision(_ run: CheckRun) {
    run.expectEqual(decideScheduledTest(networkCost: .unrestricted, skipsMeteredNetworks: true), .run, "unrestricted network runs")
    run.expectEqual(decideScheduledTest(networkCost: .expensive, skipsMeteredNetworks: true), .skip(.meteredNetwork), "metered network skips")
    run.expectEqual(decideScheduledTest(networkCost: .constrained, skipsMeteredNetworks: true), .skip(.lowDataMode), "Low Data Mode skips")
    run.expectEqual(decideScheduledTest(networkCost: .expensive, skipsMeteredNetworks: false), .run, "metered network runs when the setting is off")
    run.expectEqual(decideScheduledTest(networkCost: .constrained, skipsMeteredNetworks: false), .run, "Low Data Mode runs when the setting is off")
}

// MARK: - Contract

func checkContractComparison(_ run: CheckRun) {
    run.expectEqual(
        compareToContract(download: ValueSpread(average: 125, minimum: 50, maximum: 240), contractMegabitsPerSecond: 250),
        ContractComparison(contractMegabitsPerSecond: 250, averagePercent: 50, minimumPercent: 20),
        "contract comparison in percent",
    )
    run.expectEqual(ContractSpeed(storedMegabitsPerSecond: 0), .notSet, "stored 0 is no contract")
    run.expectEqual(ContractSpeed(storedMegabitsPerSecond: -5), .notSet, "stored negative is no contract")
    run.expectEqual(ContractSpeed(storedMegabitsPerSecond: 250), .megabitsPerSecond(250), "stored contract speed")
    run.expectEqual(ContractSpeed.megabitsPerSecond(250).storedMegabitsPerSecond, 250, "contract speed stores its value")
}

// MARK: - Weekly pattern

func checkWeeklyPattern(_ run: CheckRun) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    run.expectEqual(makeWeeklyPattern([], calendar: calendar), .noMeasurements, "pattern of nothing")
    let failedOnly = [TestRecord(startedAt: timestamp("2026-09-10 10:00:00"), computerName: "Mac", result: .failed(message: "offline"))]
    run.expectEqual(makeWeeklyPattern(failedOnly, calendar: calendar), .noMeasurements, "pattern ignores failed tests")

    // 2026-09-10 is a Thursday (weekday 5) and 2026-09-11 is a Friday (weekday 6).
    let records = [
        TestRecord(startedAt: timestamp("2026-09-10 10:00:00"), computerName: "Mac", result: .measured(measurement(downloadMegabitsPerSecond: 100))),
        TestRecord(startedAt: timestamp("2026-09-10 10:30:00"), computerName: "Mac", result: .measured(measurement(downloadMegabitsPerSecond: 50))),
        TestRecord(startedAt: timestamp("2026-09-10 10:45:00"), computerName: "Mac", result: .failed(message: "offline")),
        TestRecord(startedAt: timestamp("2026-09-11 22:00:00"), computerName: "Mac", result: .measured(measurement(downloadMegabitsPerSecond: 200))),
    ]
    run.expectEqual(
        makeWeeklyPattern(records, calendar: calendar),
        .measured(
            averages: [
                WeekdayHour(weekday: 5, hour: 10): HourlyAverage(averageDownloadMegabitsPerSecond: 75, measuredCount: 2),
                WeekdayHour(weekday: 6, hour: 22): HourlyAverage(averageDownloadMegabitsPerSecond: 200, measuredCount: 1),
            ],
            slowest: 75,
            fastest: 200,
        ),
        "pattern averages each weekday and hour",
    )

    run.expectEqual(speedLevel(10, slowest: 10, fastest: 60, levelCount: 5), 0, "slowest speed is level 0")
    run.expectEqual(speedLevel(60, slowest: 10, fastest: 60, levelCount: 5), 4, "fastest speed is the top level")
    run.expectEqual(speedLevel(35, slowest: 10, fastest: 60, levelCount: 5), 2, "middle speed is the middle level")
    run.expectEqual(speedLevel(42, slowest: 42, fastest: 42, levelCount: 5), 2, "equal speeds are the middle level")
}
