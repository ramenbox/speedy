import AppKit
import SwiftUI

/// Draws the app icon, the README screenshots and the README hero image from demo data.
/// Run it with ./Tools/render-assets.sh. It does not read or change the real Speedy data.
@main
enum RenderAssets {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2 else {
            print("Usage: RenderAssets <project folder>")
            exit(2)
        }
        let projectURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            try renderAll(projectURL: projectURL)
        } catch {
            print("ERROR: \(error)")
            exit(1)
        }
    }

    @MainActor
    static func renderAll(projectURL: URL) throws {
        let imagesURL = projectURL.appendingPathComponent("docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)

        let icon = try drawAppIcon()
        try writePng(icon, to: imagesURL.appendingPathComponent("icon.png"))

        let model = try makeDemoModel()
        let historyLight = try renderPanel(model: model, page: .history, range: .lastSevenDays, appearanceName: .aqua)
        let historyDark = try renderPanel(model: model, page: .history, range: .lastSevenDays, appearanceName: .darkAqua)
        let settingsDark = try renderPanel(model: model, page: .settings, range: .lastSevenDays, appearanceName: .darkAqua)
        try writePng(historyLight, to: imagesURL.appendingPathComponent("panel-light.png"))
        try writePng(historyDark, to: imagesURL.appendingPathComponent("panel-dark.png"))
        try writePng(settingsDark, to: imagesURL.appendingPathComponent("settings-dark.png"))

        let hero = try drawHero(leftPanel: historyLight, rightPanel: settingsDark)
        try writePng(hero, to: imagesURL.appendingPathComponent("hero.png"))
    }

    @MainActor
    static func makeDemoModel() throws -> SpeedyModel {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("speedy-assets-\(UUID().uuidString)", isDirectory: true)
        let environment = SpeedyEnvironment(
            dataFolderURL: temporaryURL,
            legacyResultsFileURL: temporaryURL.appendingPathComponent("no-legacy-results.csv"),
            computerName: demoComputerName,
        )
        guard let defaults = UserDefaults(suiteName: "speedy-assets-demo") else {
            preconditionFailure("UserDefaults rejected the asset suite name")
        }
        defaults.removePersistentDomain(forName: "speedy-assets-demo")
        defaults.set(TestInterval.thirtyMinutes.rawValue, forKey: "testInterval")
        defaults.set(SlowDownloadAlert.below50Megabits.rawValue, forKey: "slowDownloadAlert")
        defaults.set(true, forKey: "alertsOnFailedTest")

        let model = SpeedyModel(settings: SettingsStorage(defaults: defaults), environment: environment)
        let records = makeDemoRecords(now: Date(), calendar: .current)
        let databaseURL = temporaryURL.appendingPathComponent(databaseFileName)
        switch ResultStore.open(fileURL: databaseURL).flatMap({ store in store.insert(records) }) {
        case .success:
            break
        case .failure(let error):
            preconditionFailure("Could not store the demo records: \(error.message)")
        }
        model.loadLatestTest()
        guard let latestRecord = records.last else {
            preconditionFailure("The demo history is empty")
        }
        model.showScheduleForScreenshot(.waiting(nextTestAt: latestRecord.startedAt.addingTimeInterval(TestInterval.thirtyMinutes.seconds)))
        return model
    }

    @MainActor
    static func renderPanel(model: SpeedyModel, page: PanelPage, range: HistoryRange, appearanceName: NSAppearance.Name) throws -> NSBitmapImageRep {
        model.selectHistoryRange(range)
        let panel = PanelView(model: model, initialPage: page)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.locale, Locale(identifier: "en_US"))
        return try renderView(panel, appearanceName: appearanceName)
    }
}
