import Foundation

/// The user's choices, saved in UserDefaults. A missing or unknown saved value gives the standard choice.
struct SettingsStorage {
    private enum Key: String {
        case testsPaused
        case testInterval
        case slowDownloadAlert
        case alertsOnFailedTest
        case skipsMeteredNetworks
        case contractMegabitsPerSecond
        case showsSpeedInMenuBar
    }

    let defaults: UserDefaults

    var testsPaused: Bool {
        get { defaults.bool(forKey: Key.testsPaused.rawValue) }
        nonmutating set { defaults.set(newValue, forKey: Key.testsPaused.rawValue) }
    }

    var testInterval: TestInterval {
        get { TestInterval(rawValue: defaults.string(forKey: Key.testInterval.rawValue) ?? "") ?? .standard }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.testInterval.rawValue) }
    }

    var slowDownloadAlert: SlowDownloadAlert {
        get { SlowDownloadAlert(rawValue: defaults.string(forKey: Key.slowDownloadAlert.rawValue) ?? "") ?? .standard }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.slowDownloadAlert.rawValue) }
    }

    var alertsOnFailedTest: Bool {
        get { defaults.bool(forKey: Key.alertsOnFailedTest.rawValue) }
        nonmutating set { defaults.set(newValue, forKey: Key.alertsOnFailedTest.rawValue) }
    }

    /// On when nothing is saved: a test on a metered network can cost money.
    var skipsMeteredNetworks: Bool {
        get { defaults.object(forKey: Key.skipsMeteredNetworks.rawValue) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.skipsMeteredNetworks.rawValue) }
    }

    var contractSpeed: ContractSpeed {
        get { ContractSpeed(storedMegabitsPerSecond: defaults.integer(forKey: Key.contractMegabitsPerSecond.rawValue)) }
        nonmutating set { defaults.set(newValue.storedMegabitsPerSecond, forKey: Key.contractMegabitsPerSecond.rawValue) }
    }

    var showsSpeedInMenuBar: Bool {
        get { defaults.bool(forKey: Key.showsSpeedInMenuBar.rawValue) }
        nonmutating set { defaults.set(newValue, forKey: Key.showsSpeedInMenuBar.rawValue) }
    }
}
