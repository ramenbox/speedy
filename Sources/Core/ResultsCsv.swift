import Foundation

/// The columns of the CSV export. They are the same as in the results.csv of Office Speedtest.
let resultsCsvHeader = "timestamp,computer_name,status,download_mbps,upload_mbps,responsiveness_rpm,base_rtt_ms,interface_type,interface_name,test_endpoint,error"
let resultsCsvColumnCount = 11
let csvStatusMeasured = "ok"
let csvStatusFailed = "failed"

/// Wraps text in double quotes for CSV. Inner quotes are doubled, line breaks become spaces.
func csvQuote(_ text: String) -> String {
    let escapedText = collapseWhitespace(text).replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escapedText)\""
}

func csvLine(for record: TestRecord) -> String {
    let timestamp = csvTimestampFormatter.string(from: record.startedAt)
    let columns: [String]
    switch record.result {
    case .measured(let measurement):
        columns = [
            timestamp,
            csvQuote(record.computerName),
            csvStatusMeasured,
            formatOneDecimal(measurement.downloadMegabitsPerSecond),
            formatOneDecimal(measurement.uploadMegabitsPerSecond),
            formatNoDecimals(measurement.responsivenessRoundTripsPerMinute),
            formatOneDecimal(measurement.baseRoundTripTimeMilliseconds),
            measurement.interfaceType,
            measurement.interfaceName,
            measurement.testEndpoint,
            csvQuote(""),
        ]
    case .failed(let message):
        columns = [timestamp, csvQuote(record.computerName), csvStatusFailed, "", "", "", "", "", "", "", csvQuote(message)]
    }
    return columns.joined(separator: ",")
}

func csvDocument(for records: [TestRecord]) -> String {
    let lines = [resultsCsvHeader] + records.map(csvLine(for:))
    return lines.joined(separator: "\n") + "\n"
}

enum CsvLineProblem: Error, Equatable {
    case unterminatedQuote
    case textAfterClosingQuote(characterOffset: Int)
}

private enum CsvFieldState {
    case fieldStart
    case unquoted
    case quoted
    /// A quote inside a quoted field. It is a closing quote or the first half of a doubled quote.
    case quoteInQuoted
}

/// Splits one CSV line into fields. A quoted field can contain commas and doubled quotes.
/// Line breaks inside a quoted field are not supported. `csvQuote` never writes them.
func splitCsvLine(_ line: String) -> Result<[String], CsvLineProblem> {
    var fields: [String] = []
    var currentField = ""
    var state = CsvFieldState.fieldStart
    for (characterOffset, character) in line.enumerated() {
        switch (state, character) {
        case (.fieldStart, "\""):
            state = .quoted
        case (.fieldStart, ","), (.unquoted, ","), (.quoteInQuoted, ","):
            fields.append(currentField)
            currentField = ""
            state = .fieldStart
        case (.fieldStart, _), (.unquoted, _):
            currentField.append(character)
            state = .unquoted
        case (.quoted, "\""):
            state = .quoteInQuoted
        case (.quoted, _):
            currentField.append(character)
        case (.quoteInQuoted, "\""):
            currentField.append("\"")
            state = .quoted
        case (.quoteInQuoted, _):
            return .failure(.textAfterClosingQuote(characterOffset: characterOffset))
        }
    }
    switch state {
    case .quoted:
        return .failure(.unterminatedQuote)
    case .fieldStart, .unquoted, .quoteInQuoted:
        fields.append(currentField)
        return .success(fields)
    }
}
