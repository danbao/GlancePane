import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let logger = Logger(subsystem: "dev.danbao.glancepane", category: "window-lifecycle")

    private let configStore = ConfigStore()
    private let displayManager = DisplayManager()
    private let loginItemService: LoginItemManaging = LoginItemService()
    private let screenLockMonitor = ScreenLockMonitor()
    private var dashboardModel: DashboardModel?
    private var window: GlancePaneWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private weak var launchAtLoginMenuItem: NSMenuItem?
    private weak var openLoginSettingsMenuItem: NSMenuItem?
    private var startupDisplayRetryTasks: [Task<Void, Never>] = []
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var clickShield: MouseClickShield?
    private var clickShieldUsesWindowFallback = false
    private var pageObservation: AnyCancellable?
    private var dragStartLocation: CGPoint?
    private var leftClickStartLocation: CGPoint?
    private var rightClickStartLocation: CGPoint?
    private var dragDidSwitchPage = false
    private var pointerWasInsideStatusWindow = false
    private var lastPointerActivityDate = Date.distantPast
    private var windowLifecycle = DashboardWindowLifecycleState()

    private let pageDragThreshold: CGFloat = 120
    private let pageClickMovementThreshold: CGFloat = 8
    private let pointerActivityThrottle: TimeInterval = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()

        RelaunchPolicy(configDirectoryURL: configStore.configDirectoryURL).resume()
        do {
            try loginItemService.prepareForLaunch()
        } catch {
            Self.logger.error("Could not migrate login item: \(error.localizedDescription, privacy: .public)")
        }

        let config = configStore.load()
        let model = DashboardModel(
            config: config,
            configStore: configStore,
            displayManager: displayManager
        )
        dashboardModel = model
        pageObservation = model.$page.dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusMenu()
            }
        }

        createStatusItem()
        createWindow(with: model)
        registerWorkspaceObservers()
        registerScreenLockMonitor()
        installPageDragMonitors()
        installClickShield()
        requestWindowReposition(reason: "initial launch")
        model.start()
        scheduleStartupDisplayRetries()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dashboardModel?.stop()
        pageObservation = nil
        screenLockMonitor.stop()
        clickShield?.stop()
        startupDisplayRetryTasks.forEach { $0.cancel() }
        startupDisplayRetryTasks.removeAll()
        removePageDragMonitors()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func createWindow(with model: DashboardModel) {
        let screen = displayManager.preferredScreen(named: model.config.display.targetName)
        let content = DashboardView(model: model)
            .frame(minWidth: 640, minHeight: 360)
            .environment(\.colorScheme, .dark)

        let window = GlancePaneWindow(
            contentRect: screen?.frame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        hostingView.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        window.contentView = hostingView
        window.configureForStatusScreen()
        self.window = window
    }

    private func positionAndShowWindow() {
        guard let window, let model = dashboardModel else { return }
        let screen = displayManager.preferredScreen(named: model.config.display.targetName)
        let target = screen ?? NSScreen.main

        if let target {
            model.updateDisplay(screen: target, fellBack: screen == nil)
            window.setFrame(target.frame, display: true)
            window.contentView?.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
            window.contentView?.needsLayout = true
            updateClickShieldFrame()
            window.orderFront(nil)
            Self.logger.notice("Dashboard window positioned and shown")
        } else {
            model.updateDisplayUnavailable()
            Self.logger.error("No display is available for the dashboard window")
        }

        updateStatusMenu()
    }

    @objc private func systemDidWake() {
        dashboardModel?.handleSystemWake()
    }

    private func registerWorkspaceObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    private func registerScreenLockMonitor() {
        do {
            let initialState = try screenLockMonitor.start { [weak self] isLocked in
                Task { @MainActor in
                    self?.screenLockDidChange(isLocked, reason: isLocked ? "screen locked" : "screen unlocked")
                }
            }
            Self.logger.notice("Initial screen lock state: \(initialState ? "locked" : "unlocked", privacy: .public)")
            screenLockDidChange(initialState, reason: "initial screen lock state")
        } catch {
            Self.logger.error("Screen lock monitoring unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestWindowReposition(reason: String) {
        applyWindowLifecycle(
            event: .repositionRequested,
            reason: reason
        )
    }

    private func applyWindowLifecycle(event: DashboardWindowLifecycleEvent, reason: String) {
        let actions = windowLifecycle.handle(event)

        if actions.isEmpty {
            Self.logger.debug("Deferred dashboard window update: \(reason, privacy: .public)")
            return
        }

        for action in actions {
            switch action {
            case .hide:
                suspendDashboardPresentation(reason: reason)
            case .reposition:
                positionAndShowWindow()
            case .repositionAndShow:
                resumeClickShield()
                positionAndShowWindow()
            }
        }
    }

    private func suspendDashboardPresentation(reason: String) {
        cancelStartupDisplayRetries()
        resetPageGestureState()
        clickShield?.stop()
        clickShieldUsesWindowFallback = false
        window?.ignoresMouseEvents = true
        window?.orderOut(nil)
        Self.logger.notice("Dashboard window hidden: \(reason, privacy: .public)")
    }

    private func resetPageGestureState() {
        dragStartLocation = nil
        leftClickStartLocation = nil
        rightClickStartLocation = nil
        dragDidSwitchPage = false
        pointerWasInsideStatusWindow = false
    }

    @objc private func sessionDidResignActive() {
        applyWindowLifecycle(event: .sessionResigned, reason: "session resigned")
    }

    @objc private func sessionDidBecomeActive() {
        applyWindowLifecycle(event: .sessionBecameActive, reason: "session became active")
        if windowLifecycle.canPresentWindow {
            scheduleStartupDisplayRetries()
        }
    }

    @objc private func screensDidSleep() {
        applyWindowLifecycle(event: .screensSlept, reason: "screens slept")
    }

    @objc private func screensDidWake() {
        if windowLifecycle.isScreenLocked {
            Self.logger.notice("Screens woke while screen is locked")
        }
        applyWindowLifecycle(event: .screensWoke, reason: "screens woke")
        if windowLifecycle.canPresentWindow {
            scheduleStartupDisplayRetries()
        }
    }

    private func screenLockDidChange(_ isLocked: Bool, reason: String) {
        let stateChanged = windowLifecycle.isScreenLocked != isLocked
        if stateChanged {
            Self.logger.notice("Screen lock state changed: \(isLocked ? "locked" : "unlocked", privacy: .public)")
        }

        applyWindowLifecycle(event: .screenLockChanged(isLocked), reason: reason)

        if stateChanged, !isLocked, windowLifecycle.canPresentWindow {
            scheduleStartupDisplayRetries()
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusButton(item.button)
        statusItem = item
        updateStatusMenu()
    }

    private func configureStatusButton(_ button: NSStatusBarButton?) {
        guard let button else { return }

        if let image = NSImage(systemSymbolName: "rectangle.grid.2x2.fill", accessibilityDescription: "GlancePane")
            ?? NSImage(systemSymbolName: "display", accessibilityDescription: "GlancePane") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "GlancePane"
            return
        }

        button.title = "GD"
        button.toolTip = "GlancePane"
    }

    private func updateStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let displayTitle = dashboardModel?.displaySummary ?? "Display unknown"
        let clickNavigationEnabled = dashboardModel?.config.interaction.clickNavigationEnabled ?? true
        let autoPageRotation = dashboardModel?.config.pages.rotation.enabled ?? true

        menu.addItem(menuItem(title: displayTitle, symbolName: "display", isEnabled: false))
        menu.addItem(menuItem(title: "Page: \(dashboardModel?.pageDisplayTitle ?? "Unknown")", symbolName: "rectangle.on.rectangle", isEnabled: false))
        menu.addItem(menuItem(title: "Config: \(configStore.configURL.path)", symbolName: "doc.text", isEnabled: false))

        menu.addItem(NSMenuItem.separator())
        addSectionTitle("Dashboard", to: menu)
        menu.addItem(menuItem(title: "Previous Page", symbolName: "chevron.left", action: #selector(previousPage), keyEquivalent: "["))
        menu.addItem(menuItem(title: "Next Page", symbolName: "chevron.right", action: #selector(nextPage), keyEquivalent: "]"))
        menu.addItem(menuItem(
            title: "Auto Page Rotation",
            symbolName: "play.rectangle",
            action: #selector(toggleAutoPageRotation),
            state: autoPageRotation ? .on : .off
        ))

        let pagesItem = menuItem(title: "Pages", symbolName: "rectangle.grid.2x2", action: nil)
        pagesItem.submenu = createPagesMenu()
        menu.addItem(pagesItem)

        menu.addItem(NSMenuItem.separator())
        addSectionTitle("Display & Interaction", to: menu)
        menu.addItem(menuItem(
            title: "Click Navigation",
            symbolName: "cursorarrow.click",
            action: #selector(toggleClickNavigation),
            state: clickNavigationEnabled ? .on : .off
        ))
        menu.addItem(menuItem(title: "Reposition Window", symbolName: "display", action: #selector(repositionWindow)))

        menu.addItem(NSMenuItem.separator())
        addSectionTitle("Configuration", to: menu)
        menu.addItem(menuItem(title: "Settings…", symbolName: "gearshape", action: #selector(showSettings), keyEquivalent: ","))

        let loginStatus = loginItemService.status
        let loginItem = menuItem(
            title: "Launch at Login",
            symbolName: "arrow.clockwise.circle",
            action: #selector(toggleLaunchAtLogin),
            state: loginStatus == .requiresApproval ? .mixed : loginStatus.isEnabled ? .on : .off,
            isEnabled: loginStatus != .unavailable
        )
        menu.addItem(loginItem)
        launchAtLoginMenuItem = loginItem

        let approvalItem = menuItem(
            title: "Open Login Items Settings",
            symbolName: "gear",
            action: #selector(openLoginItemsSettings)
        )
        approvalItem.isHidden = loginStatus != .requiresApproval
        menu.addItem(approvalItem)
        openLoginSettingsMenuItem = approvalItem

        menu.addItem(menuItem(title: "Reload Config", symbolName: "arrow.clockwise", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(menuItem(title: "Open Config Folder", symbolName: "folder", action: #selector(openConfigFolder)))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Quit GlancePane", symbolName: "power", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let status = loginItemService.status
        launchAtLoginMenuItem?.state = status == .requiresApproval ? .mixed : status.isEnabled ? .on : .off
        launchAtLoginMenuItem?.isEnabled = status != .unavailable
        openLoginSettingsMenuItem?.isHidden = status != .requiresApproval
        settingsWindowController?.viewModel.updateLoginStatus(status)
    }

    private func createPagesMenu() -> NSMenu {
        let menu = NSMenu()
        guard let model = dashboardModel else {
            return menu
        }

        for page in model.config.pages.order {
            let item = menuItem(
                title: page.title,
                symbolName: page.symbolName,
                action: #selector(togglePageVisibility(_:)),
                state: model.config.pages.enabled.contains(page) ? .on : .off
            )
            item.representedObject = page.rawValue
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem(
            title: "Move Current Page Earlier",
            symbolName: "arrow.up",
            action: #selector(moveCurrentPageEarlier),
            isEnabled: model.canMoveCurrentPageEarlier
        ))
        menu.addItem(menuItem(
            title: "Move Current Page Later",
            symbolName: "arrow.down",
            action: #selector(moveCurrentPageLater),
            isEnabled: model.canMoveCurrentPageLater
        ))
        menu.addItem(menuItem(title: "Reset Page Order", symbolName: "arrow.counterclockwise", action: #selector(resetPageOrder)))

        return menu
    }

    private func addSectionTitle(_ title: String, to menu: NSMenu) {
        let item = menuItem(title: title.uppercased(), symbolName: nil, isEnabled: false)
        menu.addItem(item)
    }

    private func menuItem(
        title: String,
        symbolName: String?,
        action: Selector? = nil,
        keyEquivalent: String = "",
        state: NSControl.StateValue = .off,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action == nil ? nil : self
        item.state = state
        item.isEnabled = isEnabled
        item.image = templateImage(named: symbolName)
        return item
    }

    private func templateImage(named symbolName: String?) -> NSImage? {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }

        image.isTemplate = true
        return image
    }

    @objc private func toggleClickNavigation() {
        guard let model = dashboardModel else { return }
        model.recordActivity()
        model.config.interaction.clickNavigationEnabled.toggle()
        configStore.save(model.config)
        applyWindowInteraction()
        updateClickShieldFrame()
        updateStatusMenu()
    }

    @objc private func toggleAutoPageRotation() {
        guard let model = dashboardModel else { return }
        model.recordActivity()
        model.config.pages.rotation.enabled.toggle()
        configStore.save(model.config)
        updateStatusMenu()
    }

    @objc private func reloadConfig() {
        let config = configStore.load()
        dashboardModel?.apply(config: config)
        applyWindowInteraction()
        updateClickShieldFrame()
        requestWindowReposition(reason: "config reloaded")
        refreshSettingsWindow()
    }

    @objc private func showSettings() {
        guard let model = dashboardModel else { return }

        if settingsWindowController == nil {
            let viewModel = SettingsViewModel(
                config: model.config,
                displays: displayManager.displays(),
                loginStatus: loginItemService.status,
                onConfigChange: { [weak self] config in self?.applySettingsConfig(config) },
                onLoginChange: { [weak self] enabled in
                    guard let self else { return }
                    try self.loginItemService.setEnabled(enabled)
                    self.settingsWindowController?.viewModel.updateLoginStatus(self.loginItemService.status)
                    self.updateStatusMenu()
                },
                onOpenLoginSettings: { [weak self] in self?.loginItemService.openSystemSettings() },
                onOpenConfigFolder: { [weak self] in self?.openConfigFolder() },
                onImportConfig: { [weak self] in self?.importConfig() },
                onExportConfig: { [weak self] in self?.exportConfig() },
                onResetConfig: { [weak self] in self?.resetConfig() },
                onReconnectCodex: { [weak self] in self?.dashboardModel?.reconnectCodexUsage() },
                onOpenCodexFolder: { [weak self] in self?.openCodexFolder() }
            )
            settingsWindowController = SettingsWindowController(viewModel: viewModel)
        } else {
            refreshSettingsWindow()
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLogin() {
        if loginItemService.status == .requiresApproval {
            loginItemService.openSystemSettings()
            return
        }
        let shouldEnable = !loginItemService.status.isEnabled
        do {
            try loginItemService.setEnabled(shouldEnable)
        } catch {
            presentError(title: "Could Not Update Login Item", message: error.localizedDescription)
        }
        let status = loginItemService.status
        settingsWindowController?.viewModel.updateLoginStatus(status)
        updateStatusMenu()
    }

    @objc private func openLoginItemsSettings() {
        loginItemService.openSystemSettings()
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(configStore.configDirectoryURL)
    }

    private func openCodexFolder() {
        let configuredPath = dashboardModel?.config.agents.codex.codexHomePath
        NSWorkspace.shared.open(CodexExecutableResolver.codexHomeURL(configuredPath: configuredPath))
    }

    private func applySettingsConfig(_ config: AppConfig) {
        let normalized = config.normalized()
        configStore.save(normalized)
        dashboardModel?.apply(config: normalized)
        applyWindowInteraction()
        updateClickShieldFrame()
        requestWindowReposition(reason: "settings changed")
    }

    private func refreshSettingsWindow() {
        guard let model = dashboardModel else { return }
        settingsWindowController?.viewModel.refresh(
            config: model.config,
            displays: displayManager.displays(),
            loginStatus: loginItemService.status
        )
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let config = try configStore.importConfig(from: url)
            applySettingsConfig(config)
            refreshSettingsWindow()
        } catch {
            presentError(title: "Could Not Import Config", message: error.localizedDescription)
        }
    }

    private func exportConfig() {
        guard let config = dashboardModel?.config else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "GlancePane-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try configStore.export(config, to: url)
        } catch {
            presentError(title: "Could Not Export Config", message: error.localizedDescription)
        }
    }

    private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "Restore GlancePane Defaults?"
        alert.informativeText = "This replaces the current dashboard, monitoring, market, and weather settings."
        alert.addButton(withTitle: "Restore Defaults")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        applySettingsConfig(.default)
        refreshSettingsWindow()
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func scheduleStartupDisplayRetries() {
        cancelStartupDisplayRetries()
        startupDisplayRetryTasks = [2, 5, 10].map { delay in
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.requestWindowReposition(reason: "startup display retry \(delay)s")
            }
        }
    }

    private func cancelStartupDisplayRetries() {
        startupDisplayRetryTasks.forEach { $0.cancel() }
        startupDisplayRetryTasks.removeAll()
    }

    @objc private func repositionWindow() {
        dashboardModel?.recordActivity()
        requestWindowReposition(reason: "manual reposition")
    }

    @objc private func previousPage() {
        dashboardModel?.showPreviousPage()
        updateStatusMenu()
    }

    @objc private func nextPage() {
        dashboardModel?.showNextPage()
        updateStatusMenu()
    }

    @objc private func togglePageVisibility(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let page = DashboardPage(rawValue: rawValue),
              let model = dashboardModel
        else { return }

        model.setPage(page, enabled: !model.config.pages.enabled.contains(page))
        updateStatusMenu()
    }

    @objc private func moveCurrentPageEarlier() {
        dashboardModel?.moveCurrentPageEarlier()
        updateStatusMenu()
    }

    @objc private func moveCurrentPageLater() {
        dashboardModel?.moveCurrentPageLater()
        updateStatusMenu()
    }

    @objc private func resetPageOrder() {
        dashboardModel?.resetPageOrder()
        updateStatusMenu()
    }

    @objc private func screenParametersDidChange() {
        requestWindowReposition(reason: "screen parameters changed")
    }

    @objc private func quit() {
        do {
            try RelaunchPolicy(configDirectoryURL: configStore.configDirectoryURL).suppress()
        } catch {
            Self.logger.error("Could not suppress watchdog relaunch: \(error.localizedDescription, privacy: .public)")
        }
        NSApp.terminate(nil)
    }

    private func installPageDragMonitors() {
        removePageDragMonitors()

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp
        ]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePageDragEvent(type: type, location: location)
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePageDragEvent(type: type, location: location)
            }
        }
    }

    private func installClickShield() {
        let shield = MouseClickShield { [weak self] type, location in
            self?.handlePageDragEvent(type: type, location: location)
        }
        clickShield = shield
        updateClickShieldFrame()
        window?.ignoresMouseEvents = true
    }

    private func resumeClickShield() {
        guard let clickShield else { return }
        updateClickShieldFrame()
        clickShieldUsesWindowFallback = !clickShield.start()
        applyWindowInteraction()
    }

    private func updateClickShieldFrame() {
        clickShield?.update(
            windowFrame: window?.frame ?? .zero,
            screenMappings: screenMappings(),
            enabled: dashboardModel?.config.interaction.clickNavigationEnabled ?? true
        )
    }

    private func applyWindowInteraction() {
        guard let model = dashboardModel else { return }
        guard windowLifecycle.canPresentWindow else {
            window?.ignoresMouseEvents = true
            return
        }
        window?.ignoresMouseEvents = !(clickShieldUsesWindowFallback && model.config.interaction.clickNavigationEnabled)
    }

    private func screenMappings() -> [MouseClickShield.ScreenMapping] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            return MouseClickShield.ScreenMapping(
                quartzBounds: CGDisplayBounds(number),
                appKitFrame: screen.frame
            )
        }
    }

    private func removePageDragMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handlePageDragEvent(type: NSEvent.EventType, location: CGPoint) {
        if type != .mouseMoved,
           dashboardModel?.config.interaction.clickNavigationEnabled != true {
            dragStartLocation = nil
            leftClickStartLocation = nil
            rightClickStartLocation = nil
            dragDidSwitchPage = false
            return
        }

        switch type {
        case .mouseMoved:
            handlePointerActivity(location: location)

        case .leftMouseDown:
            guard isPointInsideStatusWindow(location) else {
                dragStartLocation = nil
                leftClickStartLocation = nil
                dragDidSwitchPage = false
                return
            }

            dashboardModel?.recordActivity()
            dragStartLocation = location
            leftClickStartLocation = location
            dragDidSwitchPage = false

        case .leftMouseDragged:
            guard let start = dragStartLocation,
                  isPointInsideStatusWindow(start),
                  !dragDidSwitchPage else { return }

            let deltaX = location.x - start.x
            let deltaY = location.y - start.y
            guard abs(deltaX) >= pageDragThreshold, abs(deltaX) > abs(deltaY) * 1.3 else {
                return
            }

            if deltaX < 0 {
                dashboardModel?.showNextPage()
            } else {
                dashboardModel?.showPreviousPage()
            }

            dragDidSwitchPage = true
            leftClickStartLocation = nil
            updateStatusMenu()

        case .leftMouseUp:
            if let start = leftClickStartLocation,
               !dragDidSwitchPage,
               isClick(start: start, end: location),
               isPointInsideStatusWindow(start),
               isPointInsideStatusWindow(location) {
                dashboardModel?.showPreviousPage()
                updateStatusMenu()
            }

            dragStartLocation = nil
            leftClickStartLocation = nil
            dragDidSwitchPage = false

        case .rightMouseDown:
            guard isPointInsideStatusWindow(location) else {
                rightClickStartLocation = nil
                return
            }

            dashboardModel?.recordActivity()
            rightClickStartLocation = location

        case .rightMouseUp:
            if let start = rightClickStartLocation,
               isClick(start: start, end: location),
               isPointInsideStatusWindow(start),
               isPointInsideStatusWindow(location) {
                dashboardModel?.showNextPage()
                updateStatusMenu()
            }

            rightClickStartLocation = nil

        default:
            break
        }
    }

    private func isClick(start: CGPoint, end: CGPoint) -> Bool {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        return hypot(deltaX, deltaY) <= pageClickMovementThreshold
    }

    private func handlePointerActivity(location: CGPoint) {
        guard let model = dashboardModel else { return }
        guard model.config.protection.wakeOnPointer else { return }

        let isInside = isPointInsideStatusWindow(location)
        guard isInside else {
            pointerWasInsideStatusWindow = false
            return
        }

        let now = Date()
        let shouldRecord = !pointerWasInsideStatusWindow
            || model.isResting
            || now.timeIntervalSince(lastPointerActivityDate) >= pointerActivityThrottle

        pointerWasInsideStatusWindow = true

        guard shouldRecord else { return }
        lastPointerActivityDate = now
        model.recordActivity(at: now)
    }

    private func isPointInsideStatusWindow(_ point: CGPoint) -> Bool {
        guard let window else {
            return false
        }

        return window.frame.contains(point)
    }
}
