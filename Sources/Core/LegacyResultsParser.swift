import Foundation

/// A results.csv of Office Speedtest larger than this is not imported.
let legacyResultsMaximumLineCount = 1_000_000

enum LegacyRowProblem: Error, Equatable {
    case unreadableLine(CsvLineProblem)
    case wrongColumnCount(found: Int)
    case invalidTimestamp(String)
    case unknownStatus(String)
    case invalidNumber(column: String, value: String)
}

struct LegacyRowError: Equatable {
    /// 1-based, the header is line 1.
    let lineNumber: Int
    let problem: LegacyRowProblem
}

struct LegacyParseReport: Equatable {
    let records: [TestRecord]
    /// Rows that could not be read. They are skipped.
    let rowErrors: [LegacyRowError]
}

enum LegacyFileProblem: Error, Equatable {
    case headerMismatch(found: String)
    case tooManyLines(limit: Int)
}

/// Reads the text of an Office Speedtest results.csv. Pure: no I/O.
func parseLegacyResultsCsv(_ text: String) -> Result<LegacyParseReport, LegacyFileProblem> {
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard lines.count <= legacyResultsMaximumLineCount else {
        return .failure(.tooManyLines(limit: legacyResultsMaximumLineCount))
    }
    let header = lines.first ?? ""
    guard header == resultsCsvHeader else {
        return .failure(.headerMismatch(found: truncate(header, maximumCharacters: 120)))
    }
    var records: [TestRecord] = []
    var rowErrors: [LegacyRowError] = []
    for (index, line) in lines.enumerated().dropFirst() where !line.isEmpty {
        switch parseLegacyRow(line) {
        case .success(let record):
            records.append(record)
        case .failure(let problem):
            rowErrors.append(LegacyRowError(lineNumber: index + 1, problem: problem))
        }
    }
    return .success(LegacyParseReport(records: records, rowErrors: rowErrors))
}

private func parseLegacyRow(_ line: String) -> Result<TestRecord, LegacyRowProblem> {
    let columns: [String]
    switch splitCsvLine(line) {
    case .success(let fields):
        columns = fields
    case .failure(let lineProblem):
        return .failure(.unreadableLine(lineProblem))
    }
    guard columns.count == resultsCsvColumnCount else {
        return .failure(.wrongColumnCount(found: columns.count))
    }
    guard let startedAt = csvTimestampFormatter.date(from: columns[0]) else {
        return .failure(.invalidTimestamp(columns[0]))
    }
    switch columns[2] {
    case csvStatusMeasured:
        return parseLegacyMeasurement(columns).map { measurement in
            TestRecord(startedAt: startedAt, computerName: columns[1], result: .measured(measurement))
        }
    case csvStatusFailed:
        return .success(TestRecord(startedAt: startedAt, computerName: columns[1], result: .failed(message: columns[10])))
    default:
        return .failure(.unknownStatus(columns[2]))
    }
}

private func parseLegacyMeasurement(_ columns: [String]) -> Result<SpeedMeasurement, LegacyRowProblem> {
    let numberColumns: [(name: String, value: String)] = [
        ("download_mbps", columns[3]),
        ("upload_mbps", columns[4]),
        ("responsiveness_rpm", columns[5]),
        ("base_rtt_ms", columns[6]),
    ]
    var numbers: [Double] = []
    for numberColumn in numberColumns {
        guard let number = Double(numberColumn.value), number.isFinite, number >= 0 else {
            return .failure(.invalidNumber(column: numberColumn.name, value: numberColumn.value))
        }
        numbers.append(number)
    }
    return .success(SpeedMeasurement(
        downloadMegabitsPerSecond: numbers[0],
        uploadMegabitsPerSecond: numbers[1],
        responsivenessRoundTripsPerMinute: numbers[2],
        baseRoundTripTimeMilliseconds: numbers[3],
        interfaceType: columns[7],
        interfaceName: columns[8],
        testEndpoint: columns[9],
    ))
}
