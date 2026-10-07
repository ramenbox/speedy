import AppKit
import Combine
import SwiftUI

let testAnimationFrameSeconds: TimeInterval = 0.4
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
    private var testAnimationTimer: Timer?
    private var testAnimationFrame = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        self.statusItem = statusItem

        let hostingController = NSHostingController(rootView: PanelView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.delegate = self

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

    @objc private func togglePanel() {
        guard let button = statusItem?.button else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
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
            button.title = ""
        } else {
            button.image = nil
            button.title = "Speedy"
        }
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
