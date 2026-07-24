import Dispatch
import Foundation
import OSLog
import notify

enum ScreenLockMonitorError: LocalizedError {
    case registrationFailed(UInt32)
    case stateReadFailed(UInt32)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "Could not register screen lock notifications (status \(status))."
        case .stateReadFailed(let status):
            return "Could not read the screen lock state (status \(status))."
        }
    }
}

final class ScreenLockMonitor {
    static let defaultNotificationName = "com.apple.sessionagent.screenIsLocked"
    static let defaultEdgeNotificationNames = [
        "com.apple.sessionagent.screenIsUnlocked",
    ]

    private static let logger = Logger(subsystem: "dev.danbao.glancepane", category: "screen-lock")
    private static let invalidToken: Int32 = -1
    private static let success: UInt32 = 0

    private let notificationName: String
    private let edgeNotificationNames: [String]
    private let callbackQueue: DispatchQueue
    private var stateToken = invalidToken
    private var edgeTokens: [Int32] = []
    private var onChange: ((Bool) -> Void)?

    init(
        notificationName: String = ScreenLockMonitor.defaultNotificationName,
        edgeNotificationNames: [String] = ScreenLockMonitor.defaultEdgeNotificationNames,
        callbackQueue: DispatchQueue = .main
    ) {
        self.notificationName = notificationName
        self.edgeNotificationNames = edgeNotificationNames
        self.callbackQueue = callbackQueue
    }

    deinit {
        stop()
    }

    func start(onChange: @escaping (Bool) -> Void) throws -> Bool {
        stop()
        self.onChange = onChange

        var registeredToken = Self.invalidToken
        let status = notificationName.withCString { name in
            notify_register_dispatch(name, &registeredToken, callbackQueue) { [weak self] _ in
                self?.publishState()
            }
        }

        guard status == Self.success else {
            self.onChange = nil
            throw ScreenLockMonitorError.registrationFailed(status)
        }

        stateToken = registeredToken

        for edgeNotificationName in edgeNotificationNames {
            var edgeToken = Self.invalidToken
            let edgeStatus = edgeNotificationName.withCString { name in
                notify_register_dispatch(name, &edgeToken, callbackQueue) { [weak self] _ in
                    self?.publishState()
                }
            }
            guard edgeStatus == Self.success else {
                stop()
                throw ScreenLockMonitorError.registrationFailed(edgeStatus)
            }
            edgeTokens.append(edgeToken)
        }

        do {
            return try readState()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if stateToken != Self.invalidToken {
            _ = notify_cancel(stateToken)
            stateToken = Self.invalidToken
        }

        for token in edgeTokens {
            _ = notify_cancel(token)
        }
        edgeTokens.removeAll()
        onChange = nil
    }

    static func isLocked(stateValue: UInt64) -> Bool {
        stateValue != 0
    }

    private func publishState() {
        guard stateToken != Self.invalidToken else { return }
        do {
            onChange?(try readState())
        } catch {
            Self.logger.error("Screen lock notification could not be read: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readState() throws -> Bool {
        guard stateToken != Self.invalidToken else {
            throw ScreenLockMonitorError.stateReadFailed(UInt32.max)
        }
        var state: UInt64 = 0
        let status = notify_get_state(stateToken, &state)
        guard status == Self.success else {
            throw ScreenLockMonitorError.stateReadFailed(status)
        }
        return Self.isLocked(stateValue: state)
    }
}
