import Darwin
import Foundation

final class HostCollector {
    func sample() -> HostStats {
        var averages = [Double](repeating: 0, count: 3)
        let count = getloadavg(&averages, Int32(averages.count))

        return HostStats(
            loadAverage1Minute: count > 0 ? averages[0] : 0,
            loadAverage5Minutes: count > 1 ? averages[1] : 0,
            loadAverage15Minutes: count > 2 ? averages[2] : 0,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            thermalState: thermalState
        )
    }

    private var thermalState: SystemThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}
