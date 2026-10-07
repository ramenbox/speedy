import AppKit
import Foundation
import SystemConfiguration

let dataFolderName = "Speedy"
let databaseFileName = "speedy.sqlite"
/// The panel loads at most this many results for one range. 30 days at 15 minutes is 2,880.
let historyMaximumRecordCount = 20_000
let exportMaximumRecordCount = 1_000_000
let nextTestTimerToleranceSeconds: TimeInterval = 10

enum AfterTest: Equatable {
    case continueSchedule
    /// "Run now" was used while tests were paused.
    case returnToPause
}

enum TestSchedule: Equatable {
    case paused
    case testRunning(startedAt: Date, afterTest: AfterTest)
    case waiting(nextTestAt: Date)
    /// Tests cannot run until the problem is fixed, for example when the database is not writable.
    case stopped(reason: String)
}

enum LatestTest: Equatable {
    case noTestYet
    case finished(TestRecord)
}

enum HistoryState: Equatable {
    case unavailable(message: String)
    case loaded(records: [TestRecord], summary: RangeSummary)
}

enum PanelNotice: Equatable {
    case none
    case information(String)
    case problem(String)
}

/// Where Speedy keeps its data and how it names this Mac.
struct SpeedyEnvironment {
    let dataFolderURL: URL
    let computerName: String

    static func standard() -> SpeedyEnvironment {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return SpeedyEnvironment(
            dataFolderURL: homeURL.appendingPathComponent("Library/Application Support/\(dataFolderName)", isDirectory: true),
            computerName: readComputerName(),
        )
    }
}

enum StoreState {
    case open(ResultStore)
    case unavailable(message: String)
}

/// The state of Speedy and every user action. The panel and the menu bar icon read it.
@MainActor
final class SpeedyModel: ObservableObject {
    @Published private(set) var schedule: TestSchedule = .paused
    @Published private(set) var latestTest: LatestTest = .noTestYet
    @Published private(set) var historyRange: HistoryRange = .today
    @Published private(set) var history: HistoryState = .loaded(records: [], summary: .noTests)
    @Published private(set) var notice: PanelNotice = .none
    @Published private(set) var testInterval: TestInterval
    @Published private(set) var slowDownloadAlert: SlowDownloadAlert
    @Published private(set) var alertsOnFailedTest: Bool
    @Published private(set) var loginItemState: LoginItemState = .disabled
    @Published private(set) var notificationPermission: NotificationPermission = .notAsked

    let environment: SpeedyEnvironment
    private let storeState: StoreState
    private let settings: SettingsStorage
    private let notifier = SpeedNotifier()
    private var currentRunner: NetworkQualityRunner?
    private var nextTestTimer: Timer?
    private var sleepPreventionActivity: NSObjectProtocol?

    init(settings: SettingsStorage, environment: SpeedyEnvironment) {
        self.settings = settings
        self.environment = environment
        testInterval = settings.testInterval
        slowDownloadAlert = settings.slowDownloadAlert
        alertsOnFailedTest = settings.alertsOnFailedTest
        switch ResultStore.open(fileURL: environment.dataFolderURL.appendingPathComponent(databaseFileName, isDirectory: false)) {
        case .success(let store):
            storeState = .open(store)
        case .failure(let error):
            storeState = .unavailable(message: error.message)
        }
    }

    #if SPEEDY_SCREENSHOTS
    /// Only in the screenshot tool: shows a schedule without running tests.
    func showScheduleForScreenshot(_ demoSchedule: TestSchedule) {
        schedule = demoSchedule
    }
    #endif

    // MARK: Start and stop

    func start() {
        loadLatestTest()
        reloadHistory()
        refreshSystemStates()
        if settings.testsPaused {
            schedule = .paused
        } else {
            activateTests()
        }
    }

    func stopForQuit() {
        haltTests()
    }

    /// Called when the panel opens. "Today" can be a new day, and the user can change System Settings.
    func panelWillShow() {
        reloadHistory()
        refreshSystemStates()
    }

    private func refreshSystemStates() {
        loginItemState = readLoginItemState()
        notifier.readPermission { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    // MARK: Schedule

    /// Checks the requirements and starts a test. Stops the tests when a requirement is missing.
    private func activateTests() {
        guard FileManager.default.isExecutableFile(atPath: networkQualityPath) else {
            stopTests(reason: "\(networkQualityPath) is missing. This Mac needs macOS 12 or later.")
            return
        }
        switch storeState {
        case .open:
            startTest(afterTest: .continueSchedule)
        case .unavailable(let message):
            stopTests(reason: message)
        }
    }

    private func startTest(afterTest: AfterTest) {
        nextTestTimer?.invalidate()
        nextTestTimer = nil
        preventIdleSleep()
        let startedAt = Date()
        let runner = NetworkQualityRunner()
        currentRunner = runner
        schedule = .testRunning(startedAt: startedAt, afterTest: afterTest)
        runner.start { [weak self] outcome in
            Task { @MainActor in
                self?.finishTest(startedAt: startedAt, outcome: outcome)
            }
        }
    }

    private func finishTest(startedAt: Date, outcome: NetworkQualityRunOutcome) {
        // A test that was paused or replaced by a newer test is not recorded.
        guard case .testRunning(let runningTestStartedAt, let afterTest) = schedule, runningTestStartedAt == startedAt else {
            return
        }
        currentRunner = nil
        let result: TestResult
        switch outcome {
        case .cancelled:
            return
        case .finished(.success(let measurement)):
            result = .measured(measurement)
        case .finished(.failure(let failure)):
            result = .failed(message: failure.message)
        }
        let record = TestRecord(startedAt: startedAt, computerName: environment.computerName, result: result)
        switch saveRecord(record) {
        case .failure(let error):
            stopTests(reason: error.message)
            return
        case .success:
            break
        }
        sendAlertIfNeeded(for: record)
        latestTest = .finished(record)
        reloadHistory()
        switch afterTest {
        case .continueSchedule:
            scheduleNextTest(previousTestStartedAt: startedAt)
        case .returnToPause:
            allowIdleSleep()
            schedule = .paused
        }
    }

    private func saveRecord(_ record: TestRecord) -> Result<Void, StoreError> {
        switch storeState {
        case .open(let store):
            // 0 inserted means a result with the same start time exists. It is kept as it is.
            return store.insert([record]).map { _ in () }
        case .unavailable(let message):
            return .failure(.sqlite(action: "saving a result", detail: message))
        }
    }

    private func sendAlertIfNeeded(for record: TestRecord) {
        let previousResult: TestResult?
        switch latestTest {
        case .noTestYet:
            previousResult = nil
        case .finished(let previousRecord):
            previousResult = previousRecord.result
        }
        let decision = decideSpeedAlert(
            current: record.result,
            previous: previousResult,
            slowDownloadLimit: slowDownloadAlert.limit,
            alertsOnFailedTest: alertsOnFailedTest,
        )
        notifier.send(decision)
    }

    private func scheduleNextTest(previousTestStartedAt: Date) {
        let nextTestAt = max(previousTestStartedAt.addingTimeInterval(testInterval.seconds), Date().addingTimeInterval(1))
        nextTestTimer?.invalidate()
        let timer = Timer(fire: nextTestAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.nextTestTimerFired()
            }
        }
        timer.tolerance = nextTestTimerToleranceSeconds
        RunLoop.main.add(timer, forMode: .common)
        nextTestTimer = timer
        schedule = .waiting(nextTestAt: nextTestAt)
    }

    private func nextTestTimerFired() {
        guard case .waiting = schedule else {
            return
        }
        startTest(afterTest: .continueSchedule)
    }

    private func stopTests(reason: String) {
        haltTests()
        schedule = .stopped(reason: reason)
    }

    private func haltTests() {
        currentRunner?.cancel()
        currentRunner = nil
        nextTestTimer?.invalidate()
        nextTestTimer = nil
        allowIdleSleep()
    }

    /// Keeps the Mac from idle sleep while tests are active. A closed lid still stops the tests.
    private func preventIdleSleep() {
        guard sleepPreventionActivity == nil else {
            return
        }
        sleepPreventionActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "Speedy runs a speed test at a fixed interval",
        )
    }

    private func allowIdleSleep() {
        guard let activity = sleepPreventionActivity else {
            return
        }
        ProcessInfo.processInfo.endActivity(activity)
        sleepPreventionActivity = nil
    }

    // MARK: Test actions

    enum PauseOrResumeAction: Equatable {
        case pause
        case resume
        case tryAgain
    }

    var pauseOrResumeAction: PauseOrResumeAction {
        switch schedule {
        case .testRunning(_, .continueSchedule), .waiting:
            return .pause
        case .paused, .testRunning(_, .returnToPause):
            return .resume
        case .stopped:
            return .tryAgain
        }
    }

    var canRunTestNow: Bool {
        switch schedule {
        case .waiting, .paused:
            return true
        case .testRunning, .stopped:
            return false
        }
    }

    func pauseOrResume() {
        switch schedule {
        case .testRunning(_, .continueSchedule), .waiting:
            settings.testsPaused = true
            haltTests()
            schedule = .paused
        case .testRunning(let startedAt, .returnToPause):
            // The running test finishes and the schedule continues after it.
            settings.testsPaused = false
            schedule = .testRunning(startedAt: startedAt, afterTest: .continueSchedule)
        case .paused, .stopped:
            settings.testsPaused = false
            activateTests()
        }
    }

    func runTestNow() {
        switch schedule {
        case .waiting:
            startTest(afterTest: .continueSchedule)
        case .paused:
            startTest(afterTest: .returnToPause)
        case .testRunning, .stopped:
            return
        }
    }

    // MARK: History

    func selectHistoryRange(_ range: HistoryRange) {
        historyRange = range
        reloadHistory()
    }

    func reloadHistory() {
        switch loadRecords(range: historyRange, maximumCount: historyMaximumRecordCount) {
        case .success(let records):
            history = .loaded(records: records, summary: summarize(records))
        case .failure(let error):
            history = .unavailable(message: error.message)
        }
    }

    func loadLatestTest() {
        guard case .open(let store) = storeState else {
            return
        }
        switch store.newestRecords(count: 1) {
        case .success(let records):
            latestTest = records.first.map(LatestTest.finished) ?? .noTestYet
        case .failure(let error):
            notice = .problem(error.message)
        }
    }

    private func loadRecords(range: HistoryRange, maximumCount: Int) -> Result<[TestRecord], StoreError> {
        switch storeState {
        case .open(let store):
            return store.records(from: range.start(now: Date(), calendar: .current), maximumCount: maximumCount)
        case .unavailable(let message):
            return .failure(.sqlite(action: "reading the history", detail: message))
        }
    }

    // MARK: Export and delete

    func exportCsv(range: HistoryRange) {
        let records: [TestRecord]
        switch loadRecords(range: range, maximumCount: exportMaximumRecordCount) {
        case .success(let loadedRecords):
            records = loadedRecords
        case .failure(let error):
            notice = .problem("Export failed. \(error.message)")
            return
        }
        let suggestedFileName = "speedy-\(range.fileNamePart)-\(fileDateFormatter.string(from: Date())).csv"
        switch Dialogs.chooseExportDestination(suggestedFileName: suggestedFileName) {
        case .cancelled:
            return
        case .chosen(let url):
            do {
                try Data(csvDocument(for: records).utf8).write(to: url, options: .atomic)
                notice = .information("Exported \(records.count) results to \(url.lastPathComponent).")
            } catch {
                notice = .problem("Export failed. Could not write \(url.path): \(error.localizedDescription)")
            }
        }
    }

    func deleteHistory() {
        guard case .confirmed = Dialogs.confirmDeleteHistory() else {
            return
        }
        guard case .open(let store) = storeState else {
            notice = .problem("The history could not be deleted because the database is not open.")
            return
        }
        switch store.deleteAllResults() {
        case .success:
            latestTest = .noTestYet
            notice = .information("The history is deleted.")
        case .failure(let error):
            notice = .problem(error.message)
        }
        reloadHistory()
    }

    func showDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([environment.dataFolderURL])
    }

    func dismissNotice() {
        notice = .none
    }

    // MARK: Settings

    func selectTestInterval(_ interval: TestInterval) {
        settings.testInterval = interval
        testInterval = interval
        guard case .waiting = schedule else {
            return
        }
        switch latestTest {
        case .finished(let record):
            scheduleNextTest(previousTestStartedAt: record.startedAt)
        case .noTestYet:
            scheduleNextTest(previousTestStartedAt: Date())
        }
    }

    func selectSlowDownloadAlert(_ alert: SlowDownloadAlert) {
        settings.slowDownloadAlert = alert
        slowDownloadAlert = alert
        switch alert.limit {
        case .off:
            return
        case .below:
            askNotificationPermission()
        }
    }

    func setAlertsOnFailedTest(_ isOn: Bool) {
        settings.alertsOnFailedTest = isOn
        alertsOnFailedTest = isOn
        if isOn {
            askNotificationPermission()
        }
    }

    func toggleStartAtLogin() {
        switch toggleLoginItem() {
        case .changed(let state):
            loginItemState = state
        case .failed(let message):
            notice = .problem("Start at login could not be changed. \(message)")
            loginItemState = readLoginItemState()
        }
    }

    func openLoginItemSettings() {
        openSystemSettings(urlText: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    func openNotificationSettings() {
        openSystemSettings(urlText: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    private func askNotificationPermission() {
        notifier.requestPermission { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    private func openSystemSettings(urlText: String) {
        guard let url = URL(string: urlText) else {
            preconditionFailure("Invalid System Settings URL \(urlText)")
        }
        NSWorkspace.shared.open(url)
    }
}

func readComputerName() -> String {
    guard let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? else {
        return "unknown computer"
    }
    return computerName
}

extension HistoryRange {
    var fileNamePart: String {
        switch self {
        case .today: return "today"
        case .lastSevenDays: return "7-days"
        case .lastThirtyDays: return "30-days"
        case .all: return "all"
        }
    }
}
