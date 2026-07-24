import Foundation

struct SystemHistory: Equatable {
    var samples: [SystemHistorySample]
    var windowSeconds: TimeInterval

    static let empty = SystemHistory(samples: [], windowSeconds: HistoryConfig.default.durationSeconds)
}

struct SystemHistorySample: Equatable, Identifiable {
    var timestamp: Date
    var cpuUser: Double?
    var cpuSystem: Double?
    var memoryUsage: Double?
    var gpuUsage: Double?
    var networkDownBytesPerSecond: Double?
    var networkUpBytesPerSecond: Double?
    var storageReadBytesPerSecond: Double?
    var storageWriteBytesPerSecond: Double?
    var temperatureCelsius: Double? = nil
    var powerWatts: Double? = nil

    var id: Date { timestamp }

    static func gap(at timestamp: Date) -> SystemHistorySample {
        SystemHistorySample(
            timestamp: timestamp,
            cpuUser: nil,
            cpuSystem: nil,
            memoryUsage: nil,
            gpuUsage: nil,
            networkDownBytesPerSecond: nil,
            networkUpBytesPerSecond: nil,
            storageReadBytesPerSecond: nil,
            storageWriteBytesPerSecond: nil,
            temperatureCelsius: nil,
            powerWatts: nil
        )
    }
}

final class MetricHistoryStore {
    private var samples: [SystemHistorySample] = []
    private var lastSampleDate: Date?

    func record(snapshot: SystemSnapshot, config: HistoryConfig, at now: Date = Date()) -> SystemHistory {
        let config = config.normalized()
        guard config.enabled else {
            reset()
            return SystemHistory(samples: [], windowSeconds: config.durationSeconds)
        }

        if let lastSampleDate {
            let elapsed = now.timeIntervalSince(lastSampleDate)
            if elapsed >= 0, elapsed < config.sampleIntervalSeconds {
                return current(windowSeconds: config.durationSeconds, now: now)
            }
            if elapsed > config.sampleIntervalSeconds * 2.5 {
                samples.append(.gap(at: lastSampleDate.addingTimeInterval(config.sampleIntervalSeconds)))
            }
        }

        samples.append(
            SystemHistorySample(
                timestamp: now,
                cpuUser: snapshot.state(for: .vitals).isActive ? snapshot.cpu.userUsage : nil,
                cpuSystem: snapshot.state(for: .vitals).isActive ? snapshot.cpu.systemUsage : nil,
                memoryUsage: snapshot.state(for: .vitals).isActive ? snapshot.memory.usage : nil,
                gpuUsage: snapshot.state(for: .gpu).isActive ? snapshot.gpu.usage : nil,
                networkDownBytesPerSecond: snapshot.state(for: .network).isActive ? snapshot.network.downBytesPerSecond : nil,
                networkUpBytesPerSecond: snapshot.state(for: .network).isActive ? snapshot.network.upBytesPerSecond : nil,
                storageReadBytesPerSecond: snapshot.state(for: .storage).isActive ? snapshot.storage.readBytesPerSecond : nil,
                storageWriteBytesPerSecond: snapshot.state(for: .storage).isActive ? snapshot.storage.writeBytesPerSecond : nil,
                temperatureCelsius: snapshot.state(for: .thermals).isActive ? snapshot.thermal.primaryTemperatureCelsius : nil,
                powerWatts: snapshot.state(for: .thermals).isActive ? snapshot.thermal.powerWatts : nil
            )
        )
        lastSampleDate = now
        trim(windowSeconds: config.durationSeconds, now: now)
        return SystemHistory(samples: samples, windowSeconds: config.durationSeconds)
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        lastSampleDate = nil
    }

    private func current(windowSeconds: TimeInterval, now: Date) -> SystemHistory {
        trim(windowSeconds: windowSeconds, now: now)
        return SystemHistory(samples: samples, windowSeconds: windowSeconds)
    }

    private func trim(windowSeconds: TimeInterval, now: Date) {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }
}
