import Darwin
import Foundation

final class MemoryCollector {
    func sample() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryStats.empty
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let speculative = UInt64(stats.speculative_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let external = UInt64(stats.external_page_count) * pageSize

        let rawUsed = active + inactive + speculative + wired + compressed
        let reclaimed = min(rawUsed, purgeable + external)
        let used = min(rawUsed - reclaimed, total)
        let free = total > used ? total - used : 0
        let swap = sampleSwap()

        return MemoryStats(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: samplePressure()
        )
    }

    private func samplePressure() -> MemoryPressure {
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size

        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 else {
            return .unknown
        }

        switch pressureLevel {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }

    private func sampleSwap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            return (0, 0)
        }

        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }
}
