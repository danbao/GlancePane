import Foundation
import IOKit

final class StorageCollector {
    private var previousIO: StorageIOSample?

    func sample() -> StorageStats {
        let capacity = sampleCapacity()
        let speed = sampleIOSpeed()

        return StorageStats(
            usedBytes: capacity.used,
            totalBytes: capacity.total,
            readBytesPerSecond: speed.read,
            writeBytesPerSecond: speed.write
        )
    }

    private func sampleCapacity() -> (used: UInt64, total: UInt64) {
        do {
            let values = try URL(fileURLWithPath: "/").resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            )
            let total = UInt64(max(values.volumeTotalCapacity ?? 0, 0))
            let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
            return (total > available ? total - available : 0, total)
        } catch {
            return (0, 0)
        }
    }

    private func sampleIOSpeed() -> (read: Double, write: Double) {
        let current = sampleIOBytes()
        defer { previousIO = current }

        guard let previousIO else {
            return (0, 0)
        }

        let elapsed = current.capturedAt.timeIntervalSince(previousIO.capturedAt)
        guard elapsed > 0 else {
            return (0, 0)
        }

        let readDelta = current.readBytes >= previousIO.readBytes ? current.readBytes - previousIO.readBytes : 0
        let writeDelta = current.writeBytes >= previousIO.writeBytes ? current.writeBytes - previousIO.writeBytes : 0

        return (Double(readDelta) / elapsed, Double(writeDelta) / elapsed)
    }

    private func sampleIOBytes() -> StorageIOSample {
        var iterator: io_iterator_t = 0
        var readBytes: UInt64 = 0
        var writeBytes: UInt64 = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return StorageIOSample(readBytes: 0, writeBytes: 0, capturedAt: Date())
        }

        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 {
                break
            }
            defer { IOObjectRelease(service) }

            guard let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0) else {
                continue
            }

            guard let statistics = property.takeRetainedValue() as? [String: Any] else {
                continue
            }

            readBytes += number(statistics["Bytes (Read)"])
            writeBytes += number(statistics["Bytes (Write)"])
        }

        return StorageIOSample(readBytes: readBytes, writeBytes: writeBytes, capturedAt: Date())
    }

    private func number(_ value: Any?) -> UInt64 {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? Int64 {
            return UInt64(max(value, 0))
        }
        return 0
    }
}

private struct StorageIOSample {
    let readBytes: UInt64
    let writeBytes: UInt64
    let capturedAt: Date
}
