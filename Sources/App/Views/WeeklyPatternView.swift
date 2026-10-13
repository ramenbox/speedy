import SwiftUI

let weeklyPatternLevelCount = 5
let weeklyPatternCellWidth: CGFloat = 12
let weeklyPatternCellHeight: CGFloat = 15
let weeklyPatternCellSpacing: CGFloat = 1.4
let weeklyPatternDayLabelWidth: CGFloat = 30
/// One hue, light to dark: a faster hour is darker.
let weeklyPatternLevelOpacities: [Double] = [0.16, 0.34, 0.52, 0.72, 0.92]
let weeklyPatternEmptyOpacity: Double = 0.07

/// English weekday names, so the labels match the English date formats of the rest of the panel.
let englishShortWeekdaySymbols: [String] = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar.shortWeekdaySymbols
}()

/// Average download per weekday and hour. It shows if the line is slow at the same time every week.
struct WeeklyPatternView: View {
    let state: WeeklyPatternState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Average download by weekday and hour, last 30 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch state {
            case .unavailable(let message):
                Text("The pattern cannot be shown. \(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .loaded(.noMeasurements):
                Text("No tests in the last 30 days.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .loaded(.measured(let averages, let slowest, let fastest)):
                WeeklyPatternGrid(averages: averages, slowest: slowest, fastest: fastest)
                WeeklyPatternLegend(slowest: slowest, fastest: fastest)
                WeeklyPatternExtremes(averages: averages)
            }
        }
    }
}

struct WeeklyPatternGrid: View {
    let averages: [WeekdayHour: HourlyAverage]
    let slowest: Double
    let fastest: Double

    /// The weekdays in the order of the user's calendar, for example Monday first in Germany.
    private var orderedWeekdays: [Int] {
        let firstWeekday = Calendar.current.firstWeekday
        return (0..<7).map { offset in (firstWeekday - 1 + offset) % 7 + 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: weeklyPatternCellSpacing) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                HStack(spacing: weeklyPatternCellSpacing) {
                    Text(englishShortWeekdaySymbols[weekday - 1])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: weeklyPatternDayLabelWidth, alignment: .leading)
                    ForEach(0..<24, id: \.self) { hour in
                        cell(WeekdayHour(weekday: weekday, hour: hour))
                    }
                }
            }
            hourAxis
        }
    }

    private func cell(_ weekdayHour: WeekdayHour) -> some View {
        let label = "\(englishShortWeekdaySymbols[weekdayHour.weekday - 1]) \(formatHour(weekdayHour.hour))–\(formatHour(weekdayHour.hour + 1))"
        let fill: Color
        let help: String
        switch averages[weekdayHour] {
        case .none:
            fill = Color.secondary.opacity(weeklyPatternEmptyOpacity)
            help = "\(label): no tests"
        case .some(let average):
            let level = speedLevel(average.averageDownloadMegabitsPerSecond, slowest: slowest, fastest: fastest, levelCount: weeklyPatternLevelCount)
            fill = Color.accentColor.opacity(weeklyPatternLevelOpacities[level])
            let testCount = average.measuredCount == 1 ? "1 test" : "\(average.measuredCount) tests"
            help = "\(label): \(formatOneDecimal(average.averageDownloadMegabitsPerSecond)) Mbps average, \(testCount)"
        }
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(width: weeklyPatternCellWidth, height: weeklyPatternCellHeight)
            .help(help)
    }

    private var hourAxis: some View {
        HStack(spacing: weeklyPatternCellSpacing) {
            Color.clear
                .frame(width: weeklyPatternDayLabelWidth, height: 1)
            ForEach(0..<24, id: \.self) { hour in
                Text(hour % 6 == 0 ? formatHour(hour) : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: weeklyPatternCellWidth, alignment: .leading)
            }
        }
    }
}

struct WeeklyPatternLegend: View {
    let slowest: Double
    let fastest: Double

    var body: some View {
        HStack(spacing: 6) {
            Text("\(formatOneDecimal(slowest)) Mbps")
            HStack(spacing: weeklyPatternCellSpacing) {
                ForEach(weeklyPatternLevelOpacities, id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(opacity))
                        .frame(width: weeklyPatternCellWidth, height: 10)
                }
            }
            Text("\(formatOneDecimal(fastest)) Mbps")
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(weeklyPatternEmptyOpacity))
                .frame(width: weeklyPatternCellWidth, height: 10)
            Text("No tests")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// Names the slowest and the fastest hour, so the answer does not depend on reading colours.
struct WeeklyPatternExtremes: View {
    let averages: [WeekdayHour: HourlyAverage]

    var body: some View {
        let sorted = averages.sorted { first, second in
            first.value.averageDownloadMegabitsPerSecond < second.value.averageDownloadMegabitsPerSecond
        }
        VStack(alignment: .leading, spacing: 2) {
            if let slowestHour = sorted.first {
                row(title: "Slowest hour", weekdayHour: slowestHour.key, average: slowestHour.value)
            }
            if sorted.count > 1, let fastestHour = sorted.last {
                row(title: "Fastest hour", weekdayHour: fastestHour.key, average: fastestHour.value)
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func row(title: String, weekdayHour: WeekdayHour, average: HourlyAverage) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text("\(englishShortWeekdaySymbols[weekdayHour.weekday - 1]) \(formatHour(weekdayHour.hour))–\(formatHour(weekdayHour.hour + 1))")
                .frame(width: 92, alignment: .leading)
            Text("\(formatOneDecimal(average.averageDownloadMegabitsPerSecond)) Mbps")
        }
    }
}

/// "09:00" for 9. 24 shows as "24:00", the end of the last hour.
func formatHour(_ hour: Int) -> String {
    return String(format: "%02d:00", hour)
}
