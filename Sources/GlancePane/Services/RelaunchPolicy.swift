import Foundation
import Darwin

struct RelaunchPolicy {
    static let markerFileName = "suppress-relaunch"

    let markerURL: URL
    let sessionIdentifier: String

    init(
        configDirectoryURL: URL,
        sessionIdentifier: String = String(audit_session_self())
    ) {
        markerURL = configDirectoryURL.appendingPathComponent(Self.markerFileName)
        self.sessionIdentifier = sessionIdentifier
    }

    var isSuppressed: Bool {
        guard let data = try? Data(contentsOf: markerURL),
              let storedSession = String(data: data, encoding: .utf8) else {
            return false
        }
        return storedSession == sessionIdentifier
    }

    func suppress() throws {
        try SecureFileStore.write(Data(sessionIdentifier.utf8), to: markerURL)
    }

    func resume() {
        try? FileManager.default.removeItem(at: markerURL)
    }
}
