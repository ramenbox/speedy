import Foundation

/// What macOS reports about the cost of the current network.
enum NetworkCost: Equatable {
    case unrestricted
    /// A metered connection, for example an iPhone hotspot.
    case expensive
    /// Low Data Mode is on for this network.
    case constrained
}

enum SkipReason: Equatable {
    case meteredNetwork
    case lowDataMode

    var label: String {
        switch self {
        case .meteredNetwork: return "metered network"
        case .lowDataMode: return "Low Data Mode"
        }
    }
}

enum ScheduledTestDecision: Equatable {
    case run
    case skip(SkipReason)
}

/// Pure: decides if a scheduled test runs. "Run now" does not use this decision and always runs.
func decideScheduledTest(networkCost: NetworkCost, skipsMeteredNetworks: Bool) -> ScheduledTestDecision {
    switch (networkCost, skipsMeteredNetworks) {
    case (.unrestricted, _), (_, false):
        return .run
    case (.expensive, true):
        return .skip(.meteredNetwork)
    case (.constrained, true):
        return .skip(.lowDataMode)
    }
}
