import SwiftUI

let panelWidth: CGFloat = 380

enum PanelPage: Hashable, CaseIterable {
    case history
    case weeklyPattern
    case settings

    var title: String {
        switch self {
        case .history: return "History"
        case .weeklyPattern: return "Week"
        case .settings: return "Settings"
        }
    }
}

struct PanelView: View {
    @ObservedObject var model: SpeedyModel
    @State private var page: PanelPage

    init(model: SpeedyModel, initialPage: PanelPage = .history) {
        self.model = model
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView(schedule: model.schedule, skippedTest: model.skippedTest, latestTest: model.latestTest)
            Picker("Page", selection: $page) {
                ForEach(PanelPage.allCases, id: \.self) { panelPage in
                    Text(panelPage.title).tag(panelPage)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            Divider()
            switch page {
            case .history:
                HistoryView(model: model)
            case .weeklyPattern:
                WeeklyPatternView(state: model.weeklyPattern)
            case .settings:
                SettingsView(model: model)
            }
            NoticeView(notice: model.notice, dismiss: model.dismissNotice)
            Divider()
            ActionBarView(model: model)
        }
        .padding(14)
        .frame(width: panelWidth)
    }
}

struct NoticeView: View {
    let notice: PanelNotice
    let dismiss: () -> Void

    var body: some View {
        switch notice {
        case .none:
            EmptyView()
        case .information(let text):
            row(text: text, symbolName: "info.circle", style: .secondary)
        case .problem(let text):
            row(text: text, symbolName: "exclamationmark.triangle", style: .red)
        }
    }

    private func row(text: String, symbolName: String, style: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbolName)
                .foregroundStyle(style)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Hide this message")
        }
    }
}

struct ActionBarView: View {
    @ObservedObject var model: SpeedyModel

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.pauseOrResume) {
                Label(pauseOrResumeTitle, systemImage: pauseOrResumeSymbolName)
            }
            .buttonStyle(.borderedProminent)
            Button(action: model.runTestNow) {
                Label("Run now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(!model.canRunTestNow)
            Spacer()
            Menu {
                Menu("Export CSV") {
                    ForEach(HistoryRange.allCases) { range in
                        Button(range.label) {
                            model.exportCsv(range: range)
                        }
                    }
                }
                Divider()
                Button("Quit Speedy", action: quit)
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .background {
            // The app has no main menu, so this button gives the panel the ⌘Q shortcut.
            Button("Quit Speedy", action: quit)
                .keyboardShortcut("q")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func quit() {
        NSApp.terminate(nil)
    }

    private var pauseOrResumeTitle: String {
        switch model.pauseOrResumeAction {
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .tryAgain: return "Try again"
        }
    }

    private var pauseOrResumeSymbolName: String {
        switch model.pauseOrResumeAction {
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        case .tryAgain: return "arrow.counterclockwise"
        }
    }
}
