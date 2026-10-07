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

            Picker("Slow download alert", selection: Binding(get: { model.slowDownloadAlert }, set: model.selectSlowDownloadAlert)) {
                ForEach(SlowDownloadAlert.allCases) { alert in
                    Text(alert.label).tag(alert)
                }
            }
            Toggle("Alert when a test fails", isOn: Binding(get: { model.alertsOnFailedTest }, set: model.setAlertsOnFailedTest))
            notificationPermissionNote

            Divider()
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
