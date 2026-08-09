import AppKit
import Foundation

private let appBundleIdentifier = "dev.danbao.glancepane"

struct WatchdogRelaunchController {
    let relaunchPolicy: RelaunchPolicy
    let isAppRunning: () -> Bool
    let applicationURL: () -> URL?
    let openApplication: (URL) -> Void

    func ensureAppIsRunning() {
        guard !relaunchPolicy.isSuppressed else { return }
        guard !isAppRunning() else { return }
        guard let appURL = applicationURL() else { return }
        openApplication(appURL)
    }
}

private func containingAppURL() -> URL? {
    var url = Bundle.main.bundleURL
    while url.pathExtension != "app" && url.pathComponents.count > 1 {
        url.deleteLastPathComponent()
    }
    return url.pathExtension == "app" ? url : nil
}

private func makeRelaunchController() -> WatchdogRelaunchController {
    WatchdogRelaunchController(
        relaunchPolicy: RelaunchPolicy(
            configDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".glancepane", isDirectory: true)
        ),
        isAppRunning: {
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: appBundleIdentifier
            ).isEmpty
        },
        applicationURL: containingAppURL,
        openApplication: { appURL in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: configuration
            ) { _, _ in }
        }
    )
}

func runWatchdog() {
    let relaunchController = makeRelaunchController()
    relaunchController.ensureAppIsRunning()
    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
        relaunchController.ensureAppIsRunning()
    }
    RunLoop.main.run()
}
