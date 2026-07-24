import Foundation
import Network

protocol NetworkProbing {
    func measureLatency(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> Double?
}

final class NetworkProbeService: NetworkProbing {
    func measureLatency(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> Double? {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }

        return await withCheckedContinuation { continuation in
            let attempt = NetworkProbeAttempt(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                timeoutSeconds: timeoutSeconds,
                continuation: continuation
            )
            attempt.start()
        }
    }
}

private final class NetworkProbeAttempt {
    private let queue = DispatchQueue(label: "dev.danbao.glancepane.network-probe")
    private let connection: NWConnection
    private let timeoutSeconds: TimeInterval
    private let continuation: CheckedContinuation<Double?, Never>
    private let startedAt = DispatchTime.now()
    private let lock = NSLock()
    private var completed = false

    init(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeoutSeconds: TimeInterval,
        continuation: CheckedContinuation<Double?, Never>
    ) {
        connection = NWConnection(host: host, port: port, using: .tcp)
        self.timeoutSeconds = max(0.5, timeoutSeconds)
        self.continuation = continuation
    }

    func start() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
                finish(Double(elapsed) / 1_000_000)
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeoutSeconds) { [self] in
            finish(nil)
        }
    }

    private func finish(_ latencyMilliseconds: Double?) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: latencyMilliseconds)
    }
}
