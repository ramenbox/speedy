import Charts
import SwiftUI

let chartHeight: CGFloat = 150
let recentTestsHeight: CGFloat = 150
/// The list below the chart shows at most this many tests, newest first.
let recentTestsMaximumCount = 100

struct HistoryView: View {
    @ObservedObject var model: SpeedyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Range", selection: Binding(get: { model.historyRange }, set: model.selectHistoryRange)) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.history {
        case .unavailable(let message):
            Text("The history cannot be shown. \(message)")
                .font(.caption)
                .foregroundStyle(.red)
        case .loaded(let records, .noTests):
            Text("No tests in this range.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
            RecentTestsView(records: records)
        case .loaded(let records, .onlyFailures(let failedCount)):
            Text(failedCount == 1 ? "The only test in this range failed." : "All \(failedCount) tests in this range failed.")
                .foregroundStyle(.red)
            RecentTestsView(records: records)
        case .loaded(let records, .measured(let summary)):
            SpeedChartView(records: records, contractSpeed: model.contractSpeed)
            SummaryView(summary: summary, contractSpeed: model.contractSpeed)
            RecentTestsView(records: records)
        }
    }
}

enum SpeedDirection: String {
    case download = "Download"
    case upload = "Upload"
}

struct SpeedPoint: Identifiable {
    let startedAt: Date
    let direction: SpeedDirection
    let megabitsPerSecond: Double

    var id: String { "\(direction.rawValue)-\(startedAt.timeIntervalSince1970)" }
}

struct SpeedChartView: View {
    let records: [TestRecord]
    let contractSpeed: ContractSpeed

    var body: some View {
        Chart {
            ForEach(failureTimes, id: \.self) { startedAt in
                RuleMark(x: .value("Time", startedAt))
                    .foregroundStyle(Color.red.opacity(0.35))
            }
            // Chart content has no empty mark, so this is an "if case" and not a switch.
            if case .megabitsPerSecond(let megabitsPerSecond) = contractSpeed {
                RuleMark(y: .value("Contract", megabitsPerSecond))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Contract \(megabitsPerSecond)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.startedAt),
                    y: .value("Mbps", point.megabitsPerSecond),
                )
                .foregroundStyle(by: .value("Direction", point.direction.rawValue))
                .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([
            SpeedDirection.download.rawValue: Color.accentColor,
            SpeedDirection.upload.rawValue: Color.teal,
        ])
        .chartYAxisLabel("Mbps")
        .chartLegend(position: .top, alignment: .leading)
        .frame(height: chartHeight)
    }

    private var points: [SpeedPoint] {
        records.flatMap { record -> [SpeedPoint] in
            switch record.result {
            case .measured(let measurement):
                return [
                    SpeedPoint(startedAt: record.startedAt, direction: .download, megabitsPerSecond: measurement.downloadMegabitsPerSecond),
                    SpeedPoint(startedAt: record.startedAt, direction: .upload, megabitsPerSecond: measurement.uploadMegabitsPerSecond),
                ]
            case .failed:
                return []
            }
        }
    }

    private var failureTimes: [Date] {
        records.compactMap { record in
            switch record.result {
            case .measured:
                return nil
            case .failed:
                return record.startedAt
            }
        }
    }
}

struct SummaryView: View {
    let summary: SpeedSummary
    let contractSpeed: ContractSpeed

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 2) {
                GridRow {
                    Text("")
                    Text("Average")
                    Text("Min")
                    Text("Max")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                spreadRow(title: "Download Mbps", spread: summary.download, format: formatOneDecimal)
                spreadRow(title: "Upload Mbps", spread: summary.upload, format: formatOneDecimal)
                spreadRow(title: "Ping ms", spread: summary.ping, format: formatNoDecimals)
                spreadRow(title: "Responsiveness RPM", spread: summary.responsiveness, format: formatNoDecimals)
                    .help("Round trips per minute while the line is busy. Higher is better. A low value means lag in calls and games.")
            }
            contractText
            Text(countText)
                .font(.caption)
                .foregroundStyle(summary.failedCount == 0 ? Color.secondary : Color.red)
        }
    }

    @ViewBuilder
    private var contractText: some View {
        switch contractSpeed {
        case .notSet:
            EmptyView()
        case .megabitsPerSecond(let megabitsPerSecond):
            let comparison = compareToContract(download: summary.download, contractMegabitsPerSecond: Double(megabitsPerSecond))
            Text("Download: average \(formatNoDecimals(comparison.averagePercent)) %, lowest \(formatNoDecimals(comparison.minimumPercent)) % of the \(megabitsPerSecond) Mbps contract")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func spreadRow(title: String, spread: ValueSpread, format: @escaping (Double) -> String) -> some View {
        GridRow {
            Text(title)
                .gridColumnAlignment(.leading)
                .foregroundStyle(.secondary)
            Text(format(spread.average))
            Text(format(spread.minimum))
            Text(format(spread.maximum))
        }
        .font(.callout.monospacedDigit())
    }

    private var countText: String {
        let measuredText = summary.measuredCount == 1 ? "1 test" : "\(summary.measuredCount) tests"
        switch summary.failedCount {
        case 0:
            return measuredText
        case 1:
            return "\(measuredText), 1 failed"
        default:
            return "\(measuredText), \(summary.failedCount) failed"
        }
    }
}

struct RecentTestsView: View {
    let records: [TestRecord]

    var body: some View {
        if !records.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(records.suffix(recentTestsMaximumCount).reversed(), id: \.startedAt) { record in
                        RecentTestRow(record: record)
                    }
                }
            }
            .frame(maxHeight: recentTestsHeight)
        }
    }
}

struct RecentTestRow: View {
    let record: TestRecord

    var body: some View {
        HStack(spacing: 8) {
            Text(describeTestTime(record.startedAt))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            switch record.result {
            case .measured(let measurement):
                Text("↓ \(formatOneDecimal(measurement.downloadMegabitsPerSecond))")
                    .frame(width: 56, alignment: .leading)
                Text("↑ \(formatOneDecimal(measurement.uploadMegabitsPerSecond))")
                    .frame(width: 56, alignment: .leading)
                Text("\(formatNoDecimals(measurement.baseRoundTripTimeMilliseconds)) ms")
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                Text("\(formatNoDecimals(measurement.responsivenessRoundTripsPerMinute)) RPM")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            }
            Spacer(minLength: 0)
        }
        .font(.caption.monospacedDigit())
    }
}
