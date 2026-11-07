import Darwin
import Foundation

final class ProcessCollector {
    private var previousCPUTimeByPID: [Int32: UInt64] = [:]
    private var previousSampleDate: Date?

    struct Candidate: Equatable {
        let pid: Int32
        let cpuPercent: Double
        let memoryBytes: UInt64
    }

    func sample(limit: Int, at now: Date = Date()) -> [ProcessStats] {
        let pids = allProcessIDs()
        let elapsed = previousSampleDate.map { max(0, now.timeIntervalSince($0)) } ?? 0
        var currentCPUTimeByPID: [Int32: UInt64] = [:]
        currentCPUTimeByPID.reserveCapacity(pids.count)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let task = taskInfo(pid: pid) else { continue }
            let totalCPUTime = task.pti_total_user &+ task.pti_total_system
            currentCPUTimeByPID[pid] = totalCPUTime
            candidates.append(
                Candidate(
                    pid: pid,
                    cpuPercent: Self.cpuPercent(
                        current: totalCPUTime,
                        previous: previousCPUTimeByPID[pid],
                        elapsedSeconds: elapsed
                    ),
                    memoryBytes: task.pti_resident_size
                )
            )
        }

        previousCPUTimeByPID = currentCPUTimeByPID
        previousSampleDate = now

        return Self.selectTopProcesses(
            candidates,
            limit: limit,
            resolveName: { processName(pid: $0) }
        )
    }

    static func selectTopProcesses(
        _ candidates: [Candidate],
        limit: Int,
        resolveName: (Int32) -> String
    ) -> [ProcessStats] {
        var namesByPID: [Int32: String] = [:]
        func resolvedName(for pid: Int32) -> String {
            if let cached = namesByPID[pid] {
                return cached
            }
            let resolved = resolveName(pid)
            namesByPID[pid] = resolved
            return resolved
        }

        return candidates
            .sorted {
                if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
                if $0.memoryBytes != $1.memoryBytes { return $0.memoryBytes > $1.memoryBytes }
                return resolvedName(for: $0.pid)
                    .localizedCaseInsensitiveCompare(resolvedName(for: $1.pid)) == .orderedAscending
            }
            .prefix(max(1, limit))
            .map {
                ProcessStats(
                    pid: $0.pid,
                    name: resolvedName(for: $0.pid),
                    cpuPercent: $0.cpuPercent,
                    memoryBytes: $0.memoryBytes
                )
            }
    }

    static func cpuPercent(current: UInt64, previous: UInt64?, elapsedSeconds: TimeInterval) -> Double {
        guard let previous, elapsedSeconds > 0, current >= previous else { return 0 }
        let usedNanoseconds = Double(current - previous)
        return max(0, usedNanoseconds / (elapsedSeconds * 1_000_000_000) * 100)
    }

    private func allProcessIDs() -> [Int32] {
        let estimatedCount = max(0, proc_listallpids(nil, 0))
        guard estimatedCount > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(estimatedCount) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private func taskInfo(pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let expectedSize = MemoryLayout<proc_taskinfo>.stride
        let actualSize = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, Int32(expectedSize))
        }
        return actualSize == expectedSize ? info : nil
    }

    private func processName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "PID \(pid)" }
        return String(cString: buffer)
    }
}
