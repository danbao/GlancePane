import Foundation
import Darwin

struct RelaunchPolicy {
    static let markerFileName = "suppress-relaunch"
    private static let markerVersion = 1

    private struct Marker: Codable {
        let version: Int
        let sessionIdentifier: Int32
    }

    private enum PolicyError: Error {
        case auditSessionUnavailable
    }

    let markerURL: URL
    let sessionIdentifier: Int32?

    init(
        configDirectoryURL: URL,
        sessionIdentifier: Int32? = RelaunchPolicy.currentAuditSessionIdentifier()
    ) {
        markerURL = configDirectoryURL.appendingPathComponent(Self.markerFileName)
        self.sessionIdentifier = sessionIdentifier
    }

    var isSuppressed: Bool {
        guard let sessionIdentifier,
              let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data),
              marker.version == Self.markerVersion else {
            return false
        }
        return marker.sessionIdentifier == sessionIdentifier
    }

    func suppress() throws {
        guard let sessionIdentifier else {
            throw PolicyError.auditSessionUnavailable
        }
        let marker = Marker(version: Self.markerVersion, sessionIdentifier: sessionIdentifier)
        try SecureFileStore.write(try JSONEncoder().encode(marker), to: markerURL)
    }

    func resume() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    private static func currentAuditSessionIdentifier() -> Int32? {
        var auditInfo = auditinfo_addr()
        let result = getaudit_addr(
            &auditInfo,
            Int32(MemoryLayout<auditinfo_addr>.size)
        )
        return result == 0 ? auditInfo.ai_asid : nil
    }
}
