import Foundation
import IOKit

final class GPUCollector {
    func sample() -> GPUStats {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return .unavailable
        }
        defer { IOObjectRelease(iterator) }

        var model: String?
        var usageValues: [Double] = []
        var memoryValues: [UInt64] = []
        var temperatures: [Double] = []
        var frequencies: [Double] = []

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            if model == nil {
                model = stringProperty("model", service: service)
            }

            guard let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ), let stats = property.takeRetainedValue() as? [String: Any] else {
                continue
            }

            if let usage = double(stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) {
                usageValues.append(min(max(usage / 100, 0), 1))
            }
            if let memory = uint64(stats["In use system memory"] ?? stats["Allocated system memory"]), memory > 0 {
                memoryValues.append(memory)
            }
            if let temperature = double(stats["Temperature(C)"]), temperature > 0 {
                temperatures.append(temperature)
            }
            if let frequency = double(stats["Core Clock(MHz)"]), frequency > 0 {
                frequencies.append(frequency)
            }
        }

        let usage = usageValues.average()
        let memory = memoryValues.max()
        let temperature = temperatures.average()
        let frequency = frequencies.average()
        let available = model != nil || usage != nil || memory != nil || temperature != nil || frequency != nil

        return GPUStats(
            isAvailable: available,
            model: model,
            usage: usage,
            memoryBytes: memory,
            temperatureCelsius: temperature,
            frequencyMHz: frequency
        )
    }

    private func stringProperty(_ key: String, service: io_registry_entry_t) -> String? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = property.takeRetainedValue()
        if let string = value as? String {
            return string
        }
        if let data = value as? Data {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? value as? Double
    }

    private func uint64(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        return nil
    }
}

private extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
