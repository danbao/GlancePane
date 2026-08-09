import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool { self == .enabled }

    var title: String {
        switch self {
        case .disabled: return "Off"
        case .enabled: return "On"
        case .requiresApproval: return "Approval Required"
        case .unavailable: return "Unavailable"
        }
    }
}

enum AppServiceStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum LoginItemServiceError: LocalizedError {
    case watchdogRegistrationUnavailable

    var errorDescription: String? {
        switch self {
        case .watchdogRegistrationUnavailable:
            return "The watchdog login item registration is unavailable."
        }
    }
}

@MainActor
protocol AppServiceControlling: AnyObject {
    var appServiceStatus: AppServiceStatus { get }
    func registerService() throws
    func unregisterService() throws
    func unregisterServiceAndWait() async throws
}

extension SMAppService: AppServiceControlling {
    var appServiceStatus: AppServiceStatus {
        switch status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func registerService() throws { try register() }
    func unregisterService() throws { try unregister() }
    func unregisterServiceAndWait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LoginItemStatus { get }
    func prepareForLaunch() async throws
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class LoginItemService: LoginItemManaging {
    nonisolated static let watchdogPlistName = "dev.danbao.glancepane.watchdog.plist"
    nonisolated static let registrationVersionFileName = "watchdog-registration-version"
    nonisolated static let refreshPendingFileName = "watchdog-registration-refresh-pending"

    private let watchdogService: AppServiceControlling
    private let legacyMainAppService: AppServiceControlling
    private let registrationVersionURL: URL
    private let refreshPendingURL: URL
    private let currentBuildIdentifier: String
    private let registrationRetryDelaysNanoseconds: [UInt64]
    private let retrySleep: (UInt64) async throws -> Void
    private var operationGeneration = 0
    private var latestExplicitEnabled: Bool?

    init(
        watchdogService: AppServiceControlling = SMAppService.agent(plistName: watchdogPlistName),
        legacyMainAppService: AppServiceControlling = SMAppService.mainApp,
        registrationVersionURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".glancepane", isDirectory: true)
            .appendingPathComponent(LoginItemService.registrationVersionFileName),
        refreshPendingURL: URL? = nil,
        currentBuildIdentifier: String = LoginItemService.bundleBuildIdentifier(),
        registrationRetryDelaysNanoseconds: [UInt64] = [250_000_000, 1_000_000_000, 2_000_000_000],
        retrySleep: @escaping (UInt64) async throws -> Void = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.watchdogService = watchdogService
        self.legacyMainAppService = legacyMainAppService
        self.registrationVersionURL = registrationVersionURL
        self.refreshPendingURL = refreshPendingURL
            ?? registrationVersionURL.deletingLastPathComponent()
                .appendingPathComponent(LoginItemService.refreshPendingFileName)
        self.currentBuildIdentifier = currentBuildIdentifier
        self.registrationRetryDelaysNanoseconds = registrationRetryDelaysNanoseconds
        self.retrySleep = retrySleep
    }

    var status: LoginItemStatus {
        switch watchdogService.appServiceStatus {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        }
    }

    func prepareForLaunch() async throws {
        let legacyEnabled = legacyMainAppService.appServiceStatus == .enabled
        var registeredCurrentBuild = false

        if legacyEnabled && !watchdogIsRegistered {
            try registerCurrentBuild()
            registeredCurrentBuild = true
        }
        if !registeredCurrentBuild {
            try await prepareCurrentRegistration()
        }
        if watchdogService.appServiceStatus == .enabled,
           legacyMainAppService.appServiceStatus == .enabled {
            try legacyMainAppService.unregisterService()
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        operationGeneration &+= 1
        latestExplicitEnabled = enabled
        if enabled {
            if !watchdogIsRegistered {
                try registerCurrentBuild()
            }
            if watchdogService.appServiceStatus == .enabled,
               legacyMainAppService.appServiceStatus == .enabled {
                try legacyMainAppService.unregisterService()
            }
        } else {
            try clearRegistrationFiles()
            if legacyMainAppService.appServiceStatus != .notRegistered {
                try legacyMainAppService.unregisterService()
            }
            if watchdogService.appServiceStatus != .notRegistered {
                try watchdogService.unregisterService()
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private var watchdogIsRegistered: Bool {
        switch watchdogService.appServiceStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        }
    }

    private func prepareCurrentRegistration() async throws {
        switch watchdogService.appServiceStatus {
        case .enabled:
            try await refreshRegistrationIfNeeded()
        case .requiresApproval:
            return
        case .notRegistered, .notFound:
            if refreshPendingBuild != nil {
                try await ensureCurrentBuildRegisteredWithRetry()
            }
        }
    }

    private func refreshRegistrationIfNeeded() async throws {
        guard storedRegistrationVersion != currentBuildIdentifier else {
            try clearRefreshPending()
            return
        }
        let refreshGeneration = operationGeneration
        try SecureFileStore.write(Data(currentBuildIdentifier.utf8), to: refreshPendingURL)
        try await watchdogService.unregisterServiceAndWait()
        guard !Task.isCancelled else { return }
        guard refreshGeneration == operationGeneration else {
            if latestExplicitEnabled == true {
                try await ensureCurrentBuildRegisteredWithRetry()
            }
            return
        }
        guard refreshPendingBuild == currentBuildIdentifier else {
            return
        }
        try await ensureCurrentBuildRegisteredWithRetry()
    }

    private func ensureCurrentBuildRegisteredWithRetry() async throws {
        var remainingDelays = registrationRetryDelaysNanoseconds.makeIterator()
        while true {
            if watchdogIsRegistered {
                try recordCurrentBuild()
                return
            }
            do {
                try registerCurrentBuild()
                return
            } catch {
                guard let delay = remainingDelays.next() else { throw error }
                try await retrySleep(delay)
                guard !Task.isCancelled else { return }
                if latestExplicitEnabled == false {
                    return
                }
            }
        }
    }

    private func registerCurrentBuild() throws {
        try watchdogService.registerService()
        guard watchdogIsRegistered else {
            throw LoginItemServiceError.watchdogRegistrationUnavailable
        }
        try recordCurrentBuild()
    }

    private func recordCurrentBuild() throws {
        try SecureFileStore.write(Data(currentBuildIdentifier.utf8), to: registrationVersionURL)
        try clearRefreshPending()
    }

    private var storedRegistrationVersion: String? {
        guard let data = try? Data(contentsOf: registrationVersionURL),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private var refreshPendingBuild: String? {
        guard let data = try? Data(contentsOf: refreshPendingURL),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func clearRegistrationFiles() throws {
        try clearFile(at: registrationVersionURL)
        try clearRefreshPending()
    }

    private func clearRefreshPending() throws {
        try clearFile(at: refreshPendingURL)
    }

    private func clearFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    nonisolated private static func bundleBuildIdentifier(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "development"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
        return "\(version)+\(build)"
    }
}
