import CoreWLAN
import Darwin
import Foundation
import Network
import SystemConfiguration

final class NetworkCollector {
    private var previousSample: NetworkByteSample?
    private let pathMonitor: NWPathMonitor
    private let pathQueue = DispatchQueue(label: "dev.danbao.glancepane.network-path")
    private let pathLock = NSLock()
    private var pathIsSatisfied: Bool?
    private var pathInterfaceName: String?
    private var pathInterfaceKind: String?

    init(pathMonitor: NWPathMonitor = NWPathMonitor()) {
        self.pathMonitor = pathMonitor
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.updatePath(path)
        }
        pathMonitor.start(queue: pathQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    func sample() -> NetworkStats {
        let path = pathSnapshot()
        let primary = dynamicPrimaryInterface() ?? path.interfaceName
        let ip = primary.flatMap { ipAddress(for: $0) }
        let bytes = sampleSpeed(interface: primary)
        let wifi = wifiDetails(for: primary)

        return NetworkStats(
            primaryInterface: primary,
            privateIPAddress: ip,
            ssid: wifi.ssid,
            isConnected: path.isSatisfied ?? (primary != nil && ip != nil),
            downBytesPerSecond: bytes.down,
            upBytesPerSecond: bytes.up,
            interfaceKind: path.interfaceKind ?? (wifi.isWiFi ? "WI-FI" : primary == nil ? nil : "ETHERNET"),
            wifiRSSI: wifi.rssi,
            transmitRateMbps: wifi.transmitRate
        )
    }

    private func updatePath(_ path: NWPath) {
        let activeInterfaces = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }
        let preferred = activeInterfaces.sorted { interfacePriority($0.type) < interfacePriority($1.type) }.first

        pathLock.lock()
        pathIsSatisfied = path.status == .satisfied
        pathInterfaceName = preferred?.name
        pathInterfaceKind = preferred.map { interfaceKind($0.type) }
        pathLock.unlock()
    }

    private func pathSnapshot() -> (isSatisfied: Bool?, interfaceName: String?, interfaceKind: String?) {
        pathLock.lock()
        defer { pathLock.unlock() }
        return (pathIsSatisfied, pathInterfaceName, pathInterfaceKind)
    }

    private func interfacePriority(_ type: NWInterface.InterfaceType) -> Int {
        switch type {
        case .wiredEthernet: return 0
        case .wifi: return 1
        case .cellular: return 2
        case .other: return 3
        case .loopback: return 4
        @unknown default: return 5
        }
    }

    private func interfaceKind(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wiredEthernet: return "ETHERNET"
        case .wifi: return "WI-FI"
        case .cellular: return "CELLULAR"
        case .loopback: return "LOOPBACK"
        case .other: return "OTHER"
        @unknown default: return "OTHER"
        }
    }

    private func dynamicPrimaryInterface() -> String? {
        guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return nil
        }
        return global["PrimaryInterface"] as? String
    }

    private func wifiDetails(for interface: String?) -> (ssid: String?, rssi: Int?, transmitRate: Double?, isWiFi: Bool) {
        let client = CWWiFiClient.shared()
        let wifiInterface = interface.flatMap { client.interface(withName: $0) } ?? client.interface()
        guard let wifiInterface, wifiInterface.powerOn() else {
            return (nil, nil, nil, false)
        }
        let matchesPrimary = interface == nil || wifiInterface.interfaceName == interface
        guard matchesPrimary else {
            return (nil, nil, nil, false)
        }
        let rssi = wifiInterface.rssiValue()
        let transmitRate = wifiInterface.transmitRate()
        return (
            wifiInterface.ssid(),
            rssi == 0 ? nil : rssi,
            transmitRate > 0 ? transmitRate : nil,
            true
        )
    }

    private func ipAddress(for interface: String) -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let addresses else {
            return nil
        }
        defer { freeifaddrs(addresses) }

        var ipv4Addresses: [String] = []
        var ipv6Addresses: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = addresses
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let item = current.pointee
            guard let name = item.ifa_name,
                  String(cString: name) == interface,
                  let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6)
            else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let value = String(cString: host)
                if address.pointee.sa_family == UInt8(AF_INET) {
                    if !value.hasPrefix("169.254.") {
                        ipv4Addresses.append(value)
                    }
                } else if !value.hasPrefix("fe80:") && value != "::1" {
                    ipv6Addresses.append(value)
                }
            }
        }

        return ipv4Addresses.first ?? ipv6Addresses.first
    }

    private func sampleSpeed(interface: String?) -> (down: Double, up: Double) {
        let current = sampleBytes(interface: interface)
        defer { previousSample = current }

        guard let previousSample,
              previousSample.interface == current.interface
        else {
            return (0, 0)
        }

        let elapsed = current.capturedAt.timeIntervalSince(previousSample.capturedAt)
        guard elapsed > 0 else {
            return (0, 0)
        }

        let downDelta = current.received >= previousSample.received ? current.received - previousSample.received : 0
        let upDelta = current.sent >= previousSample.sent ? current.sent - previousSample.sent : 0

        return (Double(downDelta) / elapsed, Double(upDelta) / elapsed)
    }

    private func sampleBytes(interface: String?) -> NetworkByteSample {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0
        var sent: UInt64 = 0

        guard getifaddrs(&addresses) == 0, let addresses else {
            return NetworkByteSample(interface: interface, received: 0, sent: 0, capturedAt: Date())
        }

        defer { freeifaddrs(addresses) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = addresses
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let item = current.pointee
            guard let name = item.ifa_name,
                  let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = item.ifa_data
            else {
                continue
            }

            let interfaceName = String(cString: name)
            if let interface, interfaceName != interface {
                continue
            }

            let flags = Int32(item.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else {
                continue
            }

            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(networkData.ifi_ibytes)
            sent += UInt64(networkData.ifi_obytes)
        }

        return NetworkByteSample(interface: interface, received: received, sent: sent, capturedAt: Date())
    }
}

private struct NetworkByteSample {
    let interface: String?
    let received: UInt64
    let sent: UInt64
    let capturedAt: Date
}
