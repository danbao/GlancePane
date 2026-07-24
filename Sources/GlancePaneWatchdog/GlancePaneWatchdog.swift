import AppKit
import Darwin
import Foundation

private let appBundleIdentifier = "dev.danbao.glancepane"
private let markerURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".glancepane", isDirectory: true)
    .appendingPathComponent("suppress-relaunch")
private let sessionIdentifier = String(audit_session_self())

private func relaunchIsSuppressed() -> Bool {
    guard let data = try? Data(contentsOf: markerURL),
          let storedSession = String(data: data, encoding: .utf8) else {
        return false
    }
    return storedSession == sessionIdentifier
}

private func containingAppURL() -> URL? {
    var url = Bundle.main.bundleURL
    while url.pathExtension != "app" && url.pathComponents.count > 1 {
        url.deleteLastPathComponent()
    }
    return url.pathExtension == "app" ? url : nil
}

private func ensureAppIsRunning() {
    guard !relaunchIsSuppressed() else { return }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: appBundleIdentifier).isEmpty else { return }
    guard let appURL = containingAppURL() else { return }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
}

ensureAppIsRunning()
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    ensureAppIsRunning()
}
RunLoop.main.run()
