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

@MainActor
protocol AppServiceControlling: AnyObject {
    var appServiceStatus: AppServiceStatus { get }
    func registerService() throws
    func unregisterService() throws
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
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LoginItemStatus { get }
    func prepareForLaunch() throws
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class LoginItemService: LoginItemManaging {
    nonisolated static let watchdogPlistName = "dev.danbao.glancepane.watchdog.plist"

    private let watchdogService: AppServiceControlling
    private let legacyMainAppService: AppServiceControlling

    init(
        watchdogService: AppServiceControlling = SMAppService.agent(plistName: watchdogPlistName),
        legacyMainAppService: AppServiceControlling = SMAppService.mainApp
    ) {
        self.watchdogService = watchdogService
        self.legacyMainAppService = legacyMainAppService
    }

    var status: LoginItemStatus {
        switch watchdogService.appServiceStatus {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        }
    }

    func prepareForLaunch() throws {
        guard legacyMainAppService.appServiceStatus == .enabled else { return }

        if watchdogService.appServiceStatus != .enabled {
            try watchdogService.registerService()
        }
        if watchdogService.appServiceStatus == .enabled {
            try legacyMainAppService.unregisterService()
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if watchdogService.appServiceStatus != .enabled {
                try watchdogService.registerService()
            }
            if watchdogService.appServiceStatus == .enabled,
               legacyMainAppService.appServiceStatus == .enabled {
                try legacyMainAppService.unregisterService()
            }
        } else {
            if watchdogService.appServiceStatus != .notRegistered {
                try watchdogService.unregisterService()
            }
            if legacyMainAppService.appServiceStatus != .notRegistered {
                try legacyMainAppService.unregisterService()
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
