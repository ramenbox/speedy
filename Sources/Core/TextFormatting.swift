import Foundation

func collapseWhitespace(_ text: String) -> String {
    return text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
}

func truncate(_ text: String, maximumCharacters: Int) -> String {
    guard text.count > maximumCharacters else {
        return text
    }
    return String(text.prefix(maximumCharacters - 1)) + "…"
}

func formatOneDecimal(_ value: Double) -> String {
    return String(format: "%.1f", value)
}

func formatNoDecimals(_ value: Double) -> String {
    return String(format: "%.0f", value)
}

/// "0:07" for 7 seconds, "1:05" for 65 seconds. A negative duration shows as "0:00".
func formatElapsedTime(_ seconds: TimeInterval) -> String {
    let wholeSeconds = max(0, Int(seconds))
    return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
}

/// A fixed-pattern formatter in the local time zone. The pattern does not change with the user's locale.
func makeDateFormatter(pattern: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = pattern
    return formatter
}

/// The timestamp format of the CSV files. Local time, no time zone.
let csvTimestampFormatter = makeDateFormatter(pattern: "yyyy-MM-dd HH:mm:ss")
let clockTimeFormatter = makeDateFormatter(pattern: "HH:mm")
let dayAndClockTimeFormatter = makeDateFormatter(pattern: "d MMM HH:mm")
let fileDateFormatter = makeDateFormatter(pattern: "yyyy-MM-dd")
