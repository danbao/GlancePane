import Darwin
import Foundation

final class CPUCollector {
    private var previousTicks: [Int32]?
    private lazy var topology = sampleTopology()

    func sample() -> CPUStats {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let status = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )

        guard status == KERN_SUCCESS, let cpuInfo else {
            return .empty
        }

        defer {
            let byteCount = vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        let stateCount = Int(CPU_STATE_MAX)
        let tickCount = Int(cpuCount) * stateCount
        let ticks = (0..<tickCount).map { cpuInfo[$0] }

        guard let previousTicks, previousTicks.count == ticks.count else {
            self.previousTicks = ticks
            let perCore = Array(repeating: 0.0, count: Int(cpuCount))
            let groups = Self.coreGroups(
                values: perCore,
                performanceCount: topology.performance,
                efficiencyCount: topology.efficiency
            )
            return CPUStats(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 1,
                perCoreUsage: perCore,
                performanceCoreUsage: groups.performance,
                efficiencyCoreUsage: groups.efficiency,
                unknownCoreUsage: groups.unknown
            )
        }

        var userTotal: Int64 = 0
        var systemTotal: Int64 = 0
        var niceTotal: Int64 = 0
        var idleTotal: Int64 = 0
        var perCore: [Double] = []

        for index in 0..<Int(cpuCount) {
            let base = index * stateCount
            let user = delta(ticks, previousTicks, base + Int(CPU_STATE_USER))
            let system = delta(ticks, previousTicks, base + Int(CPU_STATE_SYSTEM))
            let nice = delta(ticks, previousTicks, base + Int(CPU_STATE_NICE))
            let idle = delta(ticks, previousTicks, base + Int(CPU_STATE_IDLE))
            let coreTotal = user + system + nice + idle

            userTotal += user
            systemTotal += system
            niceTotal += nice
            idleTotal += idle
            perCore.append(coreTotal > 0 ? Double(user + system + nice) / Double(coreTotal) : 0)
        }

        self.previousTicks = ticks

        let total = userTotal + systemTotal + niceTotal + idleTotal
        guard total > 0 else {
            let groups = Self.coreGroups(
                values: perCore,
                performanceCount: topology.performance,
                efficiencyCount: topology.efficiency
            )
            return CPUStats(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idleUsage: 1,
                perCoreUsage: perCore,
                performanceCoreUsage: groups.performance,
                efficiencyCoreUsage: groups.efficiency,
                unknownCoreUsage: groups.unknown
            )
        }

        let user = Double(userTotal + niceTotal) / Double(total)
        let system = Double(systemTotal) / Double(total)
        let idle = Double(idleTotal) / Double(total)

        let normalizedPerCore = perCore.map { min(max($0, 0), 1) }
        let groups = Self.coreGroups(
            values: normalizedPerCore,
            performanceCount: topology.performance,
            efficiencyCount: topology.efficiency
        )

        return CPUStats(
            totalUsage: min(max(user + system, 0), 1),
            userUsage: min(max(user, 0), 1),
            systemUsage: min(max(system, 0), 1),
            idleUsage: min(max(idle, 0), 1),
            perCoreUsage: normalizedPerCore,
            performanceCoreUsage: groups.performance,
            efficiencyCoreUsage: groups.efficiency,
            unknownCoreUsage: groups.unknown
        )
    }

    private func delta(_ current: [Int32], _ previous: [Int32], _ index: Int) -> Int64 {
        guard current.indices.contains(index), previous.indices.contains(index) else {
            return 0
        }
        return Self.tickDelta(current: current[index], previous: previous[index])
    }

    static func tickDelta(current: Int32, previous: Int32) -> Int64 {
        let currentBits = UInt32(bitPattern: current)
        let previousBits = UInt32(bitPattern: previous)
        return Int64(currentBits &- previousBits)
    }

    static func coreGroups(
        values: [Double],
        performanceCount: Int?,
        efficiencyCount: Int?
    ) -> (performance: [Double], efficiency: [Double], unknown: [Double]) {
        guard let performanceCount,
              let efficiencyCount,
              performanceCount >= 0,
              efficiencyCount >= 0,
              performanceCount + efficiencyCount == values.count
        else {
            return ([], [], values)
        }

        let performance = Array(values.prefix(performanceCount))
        let efficiency = Array(values.dropFirst(performanceCount).prefix(efficiencyCount))
        return (performance, efficiency, [])
    }

    private func sampleTopology() -> (performance: Int?, efficiency: Int?) {
        (
            sysctlInt("hw.perflevel0.logicalcpu"),
            sysctlInt("hw.perflevel1.logicalcpu")
        )
    }

    private func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value >= 0 else {
            return nil
        }
        return Int(value)
    }
}
