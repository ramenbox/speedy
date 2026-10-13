import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SpeedyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tests", selection: Binding(get: { model.testInterval }, set: model.selectTestInterval)) {
                ForEach(TestInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            Toggle("Skip tests on metered networks", isOn: Binding(get: { model.skipsMeteredNetworks }, set: model.setSkipsMeteredNetworks))
                .help("A test uses several hundred MB on a fast line. Scheduled tests do not run on a metered network, for example an iPhone hotspot, or with Low Data Mode. \"Run now\" always runs.")
            HStack {
                Text("Contract download speed")
                Spacer()
                TextField("Not set", value: Binding(get: { contractMegabitsPerSecond }, set: model.setContractMegabitsPerSecond), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("Mbps")
                    .foregroundStyle(.secondary)
            }
            .help("The download speed of your internet contract. The history compares the measured download with it. Leave it empty to turn it off.")

            Picker("Slow download alert", selection: Binding(get: { model.slowDownloadAlert }, set: model.selectSlowDownloadAlert)) {
                ForEach(SlowDownloadAlert.allCases) { alert in
                    Text(alert.label).tag(alert)
                }
            }
            Toggle("Alert when a test fails", isOn: Binding(get: { model.alertsOnFailedTest }, set: model.setAlertsOnFailedTest))
            notificationPermissionNote

            Divider()
            Toggle("Show download speed in the menu bar", isOn: Binding(get: { model.showsSpeedInMenuBar }, set: model.setShowsSpeedInMenuBar))
            Toggle("Start at login", isOn: Binding(get: { loginItemIsOn }, set: { _ in model.toggleStartAtLogin() }))
            loginItemNote

            Divider()
            Text("Computer: \(model.environment.computerName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Show data in Finder", action: model.showDataFolder)
                Spacer()
                Button("Delete history…", role: .destructive, action: model.deleteHistory)
            }
        }
    }

    private var contractMegabitsPerSecond: Int? {
        switch model.contractSpeed {
        case .notSet: return nil
        case .megabitsPerSecond(let megabitsPerSecond): return megabitsPerSecond
        }
    }

    private var alertsAreOn: Bool {
        switch model.slowDownloadAlert.limit {
        case .below:
            return true
        case .off:
            return model.alertsOnFailedTest
        }
    }

    @ViewBuilder
    private var notificationPermissionNote: some View {
        switch (alertsAreOn, model.notificationPermission) {
        case (true, .denied), (true, .unknown):
            HStack {
                Text("Notifications for Speedy are off in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Open", action: model.openNotificationSettings)
                    .font(.caption)
            }
        case (false, _), (true, .allowed), (true, .notAsked):
            EmptyView()
        }
    }

    private var loginItemIsOn: Bool {
        switch model.loginItemState {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unknown:
            return false
        }
    }

    @ViewBuilder
    private var loginItemNote: some View {
        switch model.loginItemState {
        case .requiresApproval:
            HStack {
                Text("Approve Speedy in System Settings > General > Login Items.")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("Open", action: model.openLoginItemSettings)
                    .font(.caption)
            }
        case .unknown:
            Text("macOS reports an unknown login item state.")
                .font(.caption)
                .foregroundStyle(.red)
        case .enabled, .disabled:
            EmptyView()
        }
    }
}
