import Foundation
import IOKit
import IOKit.ps

final class PowerCollector {
    func sample() -> PowerStats {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
        let lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let source = psList.first,
              let description = IOPSGetPowerSourceDescription(psInfo, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return PowerStats(
                isAvailable: true,
                source: "AC Power",
                batteryLevel: nil,
                isCharging: false,
                isCharged: false,
                timeRemainingMinutes: nil,
                cycleCount: nil,
                healthPercent: nil,
                adapterWatts: adapterWatts(),
                hasBattery: false,
                lowPowerModeEnabled: lowPowerModeEnabled
            )
        }

        let currentCapacity = Double(description[kIOPSCurrentCapacityKey] as? Int ?? 0)
        let maxCapacity = Double(description[kIOPSMaxCapacityKey] as? Int ?? 100)
        let level = maxCapacity > 0 ? min(max(currentCapacity / maxCapacity, 0), 1) : nil
        let sourceState = description[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
        let hardware = batteryHardwareDetails()

        return PowerStats(
            isAvailable: true,
            source: sourceState,
            batteryLevel: level,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
            timeRemainingMinutes: timeRemaining(from: description),
            cycleCount: hardware.cycleCount,
            healthPercent: hardware.healthPercent,
            adapterWatts: adapterWatts(),
            hasBattery: true,
            lowPowerModeEnabled: lowPowerModeEnabled
        )
    }

    private func timeRemaining(from description: [String: Any]) -> Int? {
        let key = (description[kIOPSPowerSourceStateKey] as? String) == "AC Power"
            ? kIOPSTimeToFullChargeKey
            : kIOPSTimeToEmptyKey
        let value = description[key] as? Int
        guard let value, value >= 0 else {
            return nil
        }
        return value
    }

    private func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return details[kIOPSPowerAdapterWattsKey] as? Int
    }

    private func batteryHardwareDetails() -> (cycleCount: Int?, healthPercent: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return (nil, nil)
        }
        defer { IOObjectRelease(service) }

        let cycleCount = intProperty("CycleCount", service: service)
        let design = intProperty("DesignCapacity", service: service)
        let maxCapacity = intProperty("AppleRawMaxCapacity", service: service)
            ?? intProperty("MaxCapacity", service: service)
            ?? intProperty("NominalChargeCapacity", service: service)

        let health: Int?
        if let design, design > 0, let maxCapacity {
            health = Int((Double(maxCapacity) / Double(design) * 100).rounded())
        } else {
            health = nil
        }

        return (cycleCount, health)
    }

    private func intProperty(_ key: String, service: io_registry_entry_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue() as? Int
    }
}
