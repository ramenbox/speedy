import SwiftUI

let headerMessageMaximumCharacters = 120

struct HeaderView: View {
    let schedule: TestSchedule
    let latestTest: LatestTest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Speedy")
                    .font(.headline)
                Spacer()
                ScheduleStatusView(schedule: schedule)
            }
            LatestTestView(latestTest: latestTest)
        }
    }
}

/// A coloured label that shows if tests are active, running, paused or stopped.
struct ScheduleStatusView: View {
    let schedule: TestSchedule

    var body: some View {
        HStack(spacing: 5) {
            indicator
            label
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.15)))
        .foregroundStyle(tint)
        .help(help)
    }

    @ViewBuilder
    private var indicator: some View {
        switch schedule {
        case .waiting:
            Circle()
                .frame(width: 7, height: 7)
        case .testRunning:
            ProgressView()
                .controlSize(.mini)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.caption2)
        case .stopped:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch schedule {
        case .waiting(let nextTestAt):
            Text("Next test at \(clockTimeFormatter.string(from: nextTestAt))")
        case .testRunning(let startedAt, _):
            TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                Text("Testing… \(formatElapsedTime(timeline.date.timeIntervalSince(startedAt)))")
                    .monospacedDigit()
            }
        case .paused:
            Text("Paused")
        case .stopped(let reason):
            Text("Stopped: \(truncate(reason, maximumCharacters: 32))")
        }
    }

    private var tint: Color {
        switch schedule {
        case .waiting:
            return .green
        case .testRunning:
            return .blue
        case .paused:
            return .secondary
        case .stopped:
            return .red
        }
    }

    private var help: String {
        switch schedule {
        case .waiting:
            return "Tests are active."
        case .testRunning:
            return "A test is running. It takes about 20 seconds."
        case .paused:
            return "Tests are paused. Click Resume to start them again."
        case .stopped(let reason):
            return reason
        }
    }
}

struct LatestTestView: View {
    let latestTest: LatestTest

    var body: some View {
        switch latestTest {
        case .noTestYet:
            Text("No test result yet")
                .foregroundStyle(.secondary)
        case .finished(let record):
            switch record.result {
            case .measured(let measurement):
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    MetricView(title: "Download", value: formatOneDecimal(measurement.downloadMegabitsPerSecond), unit: "Mbps")
                    MetricView(title: "Upload", value: formatOneDecimal(measurement.uploadMegabitsPerSecond), unit: "Mbps")
                    MetricView(title: "Ping", value: formatNoDecimals(measurement.baseRoundTripTimeMilliseconds), unit: "ms")
                    Spacer()
                    Text(describeTestTime(record.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last test failed at \(describeTestTime(record.startedAt))")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Text(truncate(message, maximumCharacters: headerMessageMaximumCharacters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(message)
                }
            }
        }
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "14:30" for today, "15 Sep 14:30" for an earlier day.
func describeTestTime(_ date: Date) -> String {
    guard Calendar.current.isDateInToday(date) else {
        return dayAndClockTimeFormatter.string(from: date)
    }
    return clockTimeFormatter.string(from: date)
}
