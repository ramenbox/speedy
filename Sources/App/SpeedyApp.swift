import AppKit
import Combine
import SwiftUI

let testAnimationFrameSeconds: TimeInterval = 0.4
/// The panel fades in and out like the system menu bar panels, for example Wi-Fi.
let panelFadeInSeconds: TimeInterval = 0.1
let panelFadeOutSeconds: TimeInterval = 0.15
let testAnimationSymbolNames = [
    "gauge.with.dots.needle.0percent",
    "gauge.with.dots.needle.33percent",
    "gauge.with.dots.needle.50percent",
    "gauge.with.dots.needle.67percent",
    "gauge.with.dots.needle.100percent",
    "gauge.with.dots.needle.67percent",
    "gauge.with.dots.needle.50percent",
    "gauge.with.dots.needle.33percent",
]

enum PanelFade {
    case idle
    /// The panel is open and fades out. It closes when the fade ends.
    case fadingOut
}

@main
enum SpeedyApp {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(appDelegate) {
            application.run()
        }
    }
}

/// Owns the menu bar icon and the panel that opens below it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = SpeedyModel(settings: SettingsStorage(defaults: .standard), environment: .standard())
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var scheduleSubscription: AnyCancellable?
    private var menuBarSpeedSubscription: AnyCancellable?
    /// The text next to the menu bar icon. Empty when the setting is off.
    private var menuBarSpeedText = ""
    private var testAnimationTimer: Timer?
    private var testAnimationFrame = 0
    private var panelFade: PanelFade = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        self.statusItem = statusItem

        let hostingController = NSHostingController(rootView: PanelView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        // The open animation of a popover this large takes about 500 ms and stutters.
        // Without it, the panel shows in under 10 ms. showPanel and fadeOutPanel add a short fade instead.
        popover.animates = false
        // The first layout of the panel and the chart takes about 70 ms. Doing it at launch keeps the first open fast.
        hostingController.view.layoutSubtreeIfNeeded()
        popover.delegate = self

        // A @Published value sends the new value before the property changes, so each sink uses the values it receives.
        menuBarSpeedSubscription = model.$latestTest.combineLatest(model.$showsSpeedInMenuBar).sink { [weak self] latestTest, showsSpeedInMenuBar in
            self?.refreshMenuBarSpeed(latestTest: latestTest, showsSpeedInMenuBar: showsSpeedInMenuBar)
        }
        scheduleSubscription = model.$schedule.sink { [weak self] schedule in
            self?.refreshStatusIcon(schedule: schedule)
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopForQuit()
    }

    func popoverWillShow(_ notification: Notification) {
        model.panelWillShow()
    }

    /// A click outside the panel or the Escape key closes the panel. The panel fades out first.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        fadeOutPanel()
        return false
    }

    @objc private func togglePanel() {
        if popover.isShown {
            fadeOutPanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard let panelWindow = popover.contentViewController?.view.window else {
            return
        }
        panelWindow.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelFadeInSeconds
            panelWindow.animator().alphaValue = 1
        }
    }

    private func fadeOutPanel() {
        switch panelFade {
        case .fadingOut:
            return
        case .idle:
            break
        }
        guard let panelWindow = popover.contentViewController?.view.window else {
            popover.close()
            return
        }
        panelFade = .fadingOut
        NSAnimationContext.runAnimationGroup { context in
            context.duration = panelFadeOutSeconds
            panelWindow.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finishFadeOut()
            }
        }
    }

    private func finishFadeOut() {
        // close() does not ask popoverShouldClose again.
        popover.close()
        panelFade = .idle
    }

    private func refreshStatusIcon(schedule: TestSchedule) {
        switch schedule {
        case .testRunning where !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion:
            startTestAnimation()
        case .testRunning, .paused, .waiting, .stopped:
            stopTestAnimation()
            showStatusSymbol(StatusSymbol(schedule: schedule), appearsDisabled: statusIconAppearsDisabled(schedule: schedule))
        }
    }

    /// Moves the gauge needle while a test runs.
    private func startTestAnimation() {
        guard testAnimationTimer == nil else {
            return
        }
        testAnimationFrame = 0
        showTestAnimationFrame()
        let timer = Timer(timeInterval: testAnimationFrameSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceTestAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        testAnimationTimer = timer
    }

    private func stopTestAnimation() {
        testAnimationTimer?.invalidate()
        testAnimationTimer = nil
    }

    private func advanceTestAnimation() {
        testAnimationFrame = (testAnimationFrame + 1) % testAnimationSymbolNames.count
        showTestAnimationFrame()
    }

    private func showTestAnimationFrame() {
        let symbol = StatusSymbol(name: testAnimationSymbolNames[testAnimationFrame], description: StatusSymbol.testRunningDescription)
        // A running test never shows a dimmed icon.
        showStatusSymbol(symbol, appearsDisabled: false)
    }

    private func refreshMenuBarSpeed(latestTest: LatestTest, showsSpeedInMenuBar: Bool) {
        menuBarSpeedText = describeMenuBarSpeed(latestTest: latestTest, showsSpeedInMenuBar: showsSpeedInMenuBar)
        guard let button = statusItem?.button else {
            return
        }
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = menuBarTitle(hasImage: button.image != nil)
    }

    /// Without a symbol image the button shows the name, so the menu bar item is never empty.
    private func menuBarTitle(hasImage: Bool) -> String {
        switch (hasImage, menuBarSpeedText.isEmpty) {
        case (true, _):
            return menuBarSpeedText
        case (false, true):
            return "Speedy"
        case (false, false):
            return "Speedy \(menuBarSpeedText)"
        }
    }

    private func statusIconAppearsDisabled(schedule: TestSchedule) -> Bool {
        switch schedule {
        case .paused:
            return true
        case .testRunning, .waiting, .stopped:
            return false
        }
    }

    private func showStatusSymbol(_ symbol: StatusSymbol, appearsDisabled: Bool) {
        guard let button = statusItem?.button else {
            return
        }
        if let image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: symbol.description) {
            image.isTemplate = true
            button.image = image
        } else {
            button.image = nil
        }
        button.title = menuBarTitle(hasImage: button.image != nil)
        button.appearsDisabled = appearsDisabled
        button.toolTip = symbol.description
    }
}

struct StatusSymbol {
    static let testRunningDescription = "Speedy: test running"

    let name: String
    let description: String

    init(name: String, description: String) {
        self.name = name
        self.description = description
    }

    init(schedule: TestSchedule) {
        switch schedule {
        case .paused:
            name = "gauge.with.dots.needle.0percent"
            description = "Speedy: paused"
        case .testRunning:
            name = "gauge.with.dots.needle.100percent"
            description = StatusSymbol.testRunningDescription
        case .waiting:
            name = "gauge.with.dots.needle.67percent"
            description = "Speedy: active"
        case .stopped:
            name = "exclamationmark.triangle"
            description = "Speedy: stopped"
        }
    }
}

/// "142" for the last download in Mbps, "–" after a failed test, "" when the setting is off or no test ran yet.
func describeMenuBarSpeed(latestTest: LatestTest, showsSpeedInMenuBar: Bool) -> String {
    switch (showsSpeedInMenuBar, latestTest) {
    case (false, _), (true, .noTestYet):
        return ""
    case (true, .finished(let record)):
        switch record.result {
        case .measured(let measurement):
            return formatNoDecimals(measurement.downloadMegabitsPerSecond)
        case .failed:
            return "–"
        }
    }
}
