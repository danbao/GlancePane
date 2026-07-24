import Foundation

protocol ThermalCollecting: AnyObject {
    func sample(enabled: Bool) -> ThermalStats
    func resetConnection()
}

final class ThermalCollector: ThermalCollecting {
    private let sensorAdapter: SMCSensorAdapter

    init(sensorAdapter: SMCSensorAdapter = SMCSensorAdapter()) {
        self.sensorAdapter = sensorAdapter
    }

    func sample(enabled: Bool) -> ThermalStats {
        guard enabled else {
            return .unavailable
        }
        return sensorAdapter.sample()
    }

    func resetConnection() {
        sensorAdapter.resetConnection()
    }
}
