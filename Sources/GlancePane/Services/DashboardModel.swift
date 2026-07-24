import AppKit
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published var config: AppConfig
    @Published private(set) var page: DashboardPage = .clock
    @Published private(set) var snapshot: SystemSnapshot = .empty
    @Published private(set) var history: SystemHistory = .empty
    @Published private(set) var quotes: [StockQuote]
    @Published private(set) var weatherSnapshot: WeatherSnapshot
    @Published private(set) var codexUsage: CodexUsageSnapshot = .empty
    @Published private(set) var currentDate = Date()
    @Published private(set) var displaySummary = "Display pending"
    @Published private(set) var stockStatus: FeedStatus = .loading
    @Published private(set) var weatherStatus: FeedStatus = .setup
    @Published private(set) var contentOffset: CGSize = .zero
    @Published private(set) var dimOpacity = 0.0
    @Published private(set) var isResting = false

    private let configStore: ConfigStore
    private let displayManager: DisplayManager
    private let metricsService: SystemMetricsService
    private let stockService: StockService
    private let weatherService: WeatherService
    private let networkProbeService: NetworkProbing
    private let makeCodexUsageService: () -> CodexUsageService
    private let historyStore = MetricHistoryStore()
    private let healthEvaluator = HealthEvaluator()
    private var timer: Timer?
    private var stockTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
    private var networkProbeTask: Task<Void, Never>?
    private var codexTask: Task<Void, Never>?
    private var codexUsageService: CodexUsageService?
    private var stockRequestGeneration = 0
    private var weatherRequestGeneration = 0
    private var networkProbeGeneration = 0
    private var codexRequestGeneration = 0
    private var lastStockRefresh: Date?
    private var lastWeatherRefresh: Date?
    private var lastNetworkProbe: Date?
    private var isFetchingStocks = false
    private var isFetchingWeather = false
    private var isProbingNetwork = false
    private var latestNetworkLatency: Double?
    private var lastActivityDate = Date()
    private var displayCycleStartDate = Date()
    private var lastPixelShiftDate = Date.distantPast
    private var lastAutoPageRotationDate = Date()
    private var restStartedAt: Date?
    private var pixelShiftStep = 0

    init(
        config: AppConfig,
        configStore: ConfigStore,
        displayManager: DisplayManager,
        metricsService: SystemMetricsService = SystemMetricsService(),
        stockService: StockService? = nil,
        weatherService: WeatherService? = nil,
        networkProbeService: NetworkProbing = NetworkProbeService(),
        codexUsageServiceFactory: (() -> CodexUsageService)? = nil
    ) {
        self.config = config
        self.configStore = configStore
        self.displayManager = displayManager
        self.metricsService = metricsService
        self.stockService = stockService ?? StockService(cacheURL: configStore.stockCacheURL)
        self.weatherService = weatherService ?? WeatherService(cacheURL: configStore.weatherCacheURL)
        self.networkProbeService = networkProbeService
        makeCodexUsageService = codexUsageServiceFactory
            ?? { CodexUsageService(cacheURL: configStore.codexUsageCacheURL) }
        quotes = self.stockService.loadCached(symbols: config.market.symbols)
        weatherSnapshot = self.weatherService.loadCached() ?? .empty
        if !quotes.isEmpty {
            stockStatus = .cached
        }
        if weatherSnapshot.current != nil || !weatherSnapshot.hourly.isEmpty || !weatherSnapshot.minutely.isEmpty {
            weatherStatus = weatherSnapshot.isCached ? .cached : .live
        }
        page = visiblePages.first ?? .clock
    }

    var visiblePages: [DashboardPage] {
        let pages = config.pages.order.filter { config.pages.enabled.contains($0) }
        return pages.isEmpty ? [.clock] : pages
    }

    var pageDisplayTitle: String {
        let pages = visiblePages
        let index = pages.firstIndex(of: page) ?? 0
        return "\(page.title.uppercased()) \(index + 1)/\(pages.count)"
    }

    var canMoveCurrentPageEarlier: Bool {
        guard let index = visiblePages.firstIndex(of: page) else { return false }
        return index > 0
    }

    var canMoveCurrentPageLater: Bool {
        let pages = visiblePages
        guard let index = pages.firstIndex(of: page) else { return false }
        return index < pages.count - 1
    }

    func start() {
        stop()
        resetBurnInProtectionDates()
        tick()
        refreshStocks(force: true)
        refreshWeather(force: true)
        refreshNetworkQuality(force: true)
        startCodexUsageIfNeeded()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                self?.refreshStocks(force: false)
                self?.refreshWeather(force: false)
                self?.refreshNetworkQuality(force: false)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stockTask?.cancel()
        weatherTask?.cancel()
        networkProbeTask?.cancel()
        codexTask?.cancel()
        stockTask = nil
        weatherTask = nil
        networkProbeTask = nil
        codexTask = nil
        stockRequestGeneration &+= 1
        weatherRequestGeneration &+= 1
        networkProbeGeneration &+= 1
        codexRequestGeneration &+= 1
        isFetchingStocks = false
        isFetchingWeather = false
        isProbingNetwork = false
        if let codexUsageService {
            Task { await codexUsageService.stop() }
        }
        codexUsageService = nil
    }

    func apply(config newConfig: AppConfig) {
        stop()
        config = newConfig.normalized()
        healthEvaluator.reset()
        ensureCurrentPageIsVisible()
        recordActivity()
        quotes = stockService.loadCached(symbols: config.market.symbols)
        weatherSnapshot = weatherService.loadCached() ?? .empty
        if !config.market.enabled {
            stockStatus = .disabled
        }
        if !config.pages.enabled.contains(.weather) {
            weatherStatus = .hidden
        }
        if !config.system.networkQuality.enabled {
            latestNetworkLatency = nil
        }
        start()
    }

    func updateDisplay(screen: NSScreen, fellBack: Bool) {
        let descriptor = displayManager.descriptor(for: screen)
        displaySummary = fellBack
            ? "Fallback: \(descriptor.summary)"
            : "Display: \(descriptor.summary)"
    }

    func updateDisplayUnavailable() {
        displaySummary = "No display available"
    }

    func handleSystemWake() {
        metricsService.handleSystemWake()
        tick()
    }

    func showNextPage() {
        showAdjacentPage(offset: 1, recordsActivity: true)
    }

    func showPreviousPage() {
        showAdjacentPage(offset: -1, recordsActivity: true)
    }

    func showPage(_ newPage: DashboardPage) {
        showPage(newPage, recordsActivity: true)
    }

    private func showPage(_ newPage: DashboardPage, recordsActivity: Bool) {
        if recordsActivity {
            recordActivity()
        }

        if visiblePages.contains(newPage) {
            page = newPage
            if newPage == .weather {
                refreshWeather(force: true)
            }
        } else {
            ensureCurrentPageIsVisible()
        }
    }

    func setPage(_ targetPage: DashboardPage, enabled: Bool) {
        recordActivity()
        if enabled {
            config.pages.enabled.insert(targetPage)
        } else {
            config.pages.enabled.remove(targetPage)
        }
        normalizePageSettings()
        ensureCurrentPageIsVisible()
        configStore.save(config)
        if targetPage == .weather {
            refreshWeather(force: enabled)
        }
        if targetPage == .agents {
            restartCodexUsage()
        }
    }

    func reconnectCodexUsage() {
        restartCodexUsage()
    }

    func moveCurrentPageEarlier() {
        guard canMoveCurrentPageEarlier else { return }
        guard let previousVisiblePage = previousVisiblePage else { return }

        recordActivity()
        config.pages.order.removeAll { $0 == page }
        if let targetIndex = config.pages.order.firstIndex(of: previousVisiblePage) {
            config.pages.order.insert(page, at: targetIndex)
        } else {
            config.pages.order.insert(page, at: 0)
        }
        normalizePageSettings()
        configStore.save(config)
    }

    func moveCurrentPageLater() {
        guard canMoveCurrentPageLater else { return }
        guard let nextVisiblePage = nextVisiblePage else { return }

        recordActivity()
        config.pages.order.removeAll { $0 == page }
        if let targetIndex = config.pages.order.firstIndex(of: nextVisiblePage) {
            config.pages.order.insert(page, at: min(config.pages.order.count, targetIndex + 1))
        } else {
            config.pages.order.append(page)
        }
        normalizePageSettings()
        configStore.save(config)
    }

    func resetPageOrder() {
        recordActivity()
        config.pages.order = DashboardPage.defaultOrder
        normalizePageSettings()
        ensureCurrentPageIsVisible()
        configStore.save(config)
    }

    func recordActivity(at now: Date = Date()) {
        lastActivityDate = now
        displayCycleStartDate = now
        restStartedAt = nil
        isResting = false
        dimOpacity = 0
    }

    private func tick() {
        currentDate = Date()
        var nextSnapshot = metricsService.sample(config: config)
        nextSnapshot.network.latencyMilliseconds = config.system.networkQuality.enabled ? latestNetworkLatency : nil
        nextSnapshot.health = healthEvaluator.evaluate(
            snapshot: nextSnapshot,
            thresholds: config.system.thresholds,
            at: currentDate
        )
        snapshot = nextSnapshot
        history = historyStore.record(snapshot: nextSnapshot, config: config.system.history, at: currentDate)
        updateBurnInProtection(now: currentDate)
        updateAutoPageRotation(now: currentDate)
    }

    private func refreshNetworkQuality(force: Bool) {
        let request = config.system.networkQuality
        guard request.enabled,
              config.system.enabledGroups.contains(.network) else {
            networkProbeTask?.cancel()
            networkProbeTask = nil
            isProbingNetwork = false
            latestNetworkLatency = nil
            return
        }

        guard !isProbingNetwork else { return }
        if !force,
           let lastNetworkProbe,
           Date().timeIntervalSince(lastNetworkProbe) < request.intervalSeconds {
            return
        }

        isProbingNetwork = true
        networkProbeGeneration &+= 1
        let generation = networkProbeGeneration
        networkProbeTask = Task { [weak self] in
            guard let self else { return }
            let latency = await networkProbeService.measureLatency(
                host: request.host,
                port: request.port,
                timeoutSeconds: request.timeoutSeconds
            )
            guard !Task.isCancelled,
                  generation == networkProbeGeneration,
                  config.system.networkQuality == request else { return }

            latestNetworkLatency = latency
            lastNetworkProbe = Date()
            isProbingNetwork = false
            networkProbeTask = nil
            snapshot.network.latencyMilliseconds = latency
        }
    }

    private func refreshStocks(force: Bool) {
        guard config.market.enabled else {
            stockStatus = .disabled
            quotes = []
            return
        }

        if isFetchingStocks {
            return
        }

        if !force,
           let lastStockRefresh,
           Date().timeIntervalSince(lastStockRefresh) < stockRefreshInterval {
            return
        }

        isFetchingStocks = true
        stockStatus = quotes.isEmpty ? .loading : .refreshing

        let symbols = config.market.symbols
        stockRequestGeneration &+= 1
        let requestGeneration = stockRequestGeneration
        stockTask = Task { [weak self] in
            guard let self else { return }
            let result = await stockService.fetch(symbols: symbols)
            guard !Task.isCancelled,
                  requestGeneration == stockRequestGeneration,
                  config.market.enabled,
                  config.market.symbols == symbols else { return }

            lastStockRefresh = Date()
            isFetchingStocks = false
            stockTask = nil

            switch result {
            case .success(let quotes):
                self.quotes = quotes
                stockStatus = quotes.contains(where: \.isCached) || quotes.count < symbols.count ? .partial : .live
            case .failure(.usingCache(let quotes, _)):
                self.quotes = quotes
                stockStatus = .cached
            case .failure(.network):
                stockStatus = .offline
            }
        }
    }

    private var stockRefreshInterval: TimeInterval {
        config.market.refreshIntervalSeconds
    }

    private func refreshWeather(force: Bool) {
        guard visiblePages.contains(.weather) else {
            weatherStatus = .hidden
            return
        }

        if isFetchingWeather {
            return
        }

        if !force,
           let lastWeatherRefresh,
           Date().timeIntervalSince(lastWeatherRefresh) < config.weather.refreshIntervalSeconds {
            return
        }

        isFetchingWeather = true
        weatherStatus = weatherSnapshot.current == nil && weatherSnapshot.hourly.isEmpty && weatherSnapshot.minutely.isEmpty
            ? .loading
            : .refreshing

        let requestConfig = config
        weatherRequestGeneration &+= 1
        let requestGeneration = weatherRequestGeneration
        weatherTask = Task { [weak self] in
            guard let self else { return }
            let result = await weatherService.fetch(config: requestConfig)
            guard !Task.isCancelled,
                  requestGeneration == weatherRequestGeneration,
                  config.weather == requestConfig.weather,
                  visiblePages.contains(.weather) else { return }

            lastWeatherRefresh = Date()
            isFetchingWeather = false
            weatherTask = nil

            switch result {
            case .success(let snapshot):
                weatherSnapshot = snapshot
                weatherStatus = snapshot.errorMessage == nil ? .live : .partial
            case .failure(.setupRequired(let message)):
                var snapshot = weatherSnapshot
                snapshot.errorMessage = message
                weatherSnapshot = snapshot
                weatherStatus = .setup
            case .failure(.usingCache(let snapshot, _)):
                weatherSnapshot = snapshot
                weatherStatus = .cached
            case .failure(.network(let message)):
                var snapshot = weatherSnapshot
                snapshot.errorMessage = message
                weatherSnapshot = snapshot
                weatherStatus = .offline
            }
        }
    }

    private func startCodexUsageIfNeeded() {
        guard config.agents.codex.enabled, visiblePages.contains(.agents) else {
            codexUsage = CodexUsageSnapshot(
                account: nil,
                rateLimits: nil,
                sessions: [],
                status: .disabled,
                message: nil,
                updatedAt: nil
            )
            return
        }

        codexRequestGeneration &+= 1
        let generation = codexRequestGeneration
        let request = config.agents.codex
        let service = makeCodexUsageService()
        codexUsageService = service
        codexUsage.status = codexUsage.account == nil ? .loading : .cached

        codexTask = Task { [weak self] in
            await service.run(config: request) { [weak self] snapshot in
                guard let self,
                      generation == self.codexRequestGeneration,
                      self.config.agents.codex == request,
                      self.visiblePages.contains(.agents) else { return }
                self.codexUsage = snapshot
            }
        }
    }

    private func restartCodexUsage() {
        codexTask?.cancel()
        codexTask = nil
        codexRequestGeneration &+= 1
        if let codexUsageService {
            Task { await codexUsageService.stop() }
        }
        codexUsageService = nil
        startCodexUsageIfNeeded()
    }

    private func showAdjacentPage(offset: Int, recordsActivity: Bool) {
        let pages = visiblePages
        guard !pages.isEmpty else {
            showPage(.clock, recordsActivity: recordsActivity)
            return
        }

        guard pages.count > 1 else {
            showPage(pages[0], recordsActivity: recordsActivity)
            return
        }

        let currentIndex = pages.firstIndex(of: page) ?? 0
        let nextIndex = (currentIndex + offset + pages.count) % pages.count
        showPage(pages[nextIndex], recordsActivity: recordsActivity)
    }

    private func updateAutoPageRotation(now: Date) {
        guard config.pages.rotation.enabled else {
            lastAutoPageRotationDate = now
            return
        }

        guard visiblePages.count > 1, !isResting else {
            lastAutoPageRotationDate = now
            return
        }

        let interval = max(5, config.pages.rotation.intervalSeconds)
        let latestHoldDate = max(lastAutoPageRotationDate, lastActivityDate)
        guard now.timeIntervalSince(latestHoldDate) >= interval else {
            return
        }

        lastAutoPageRotationDate = now
        showAdjacentPage(offset: 1, recordsActivity: false)
    }

    private func ensureCurrentPageIsVisible() {
        if !visiblePages.contains(page) {
            page = visiblePages.first ?? .clock
        }
    }

    private func normalizePageSettings() {
        config.pages.order = DashboardPage.normalizedOrder(config.pages.order)
        let enabledPagesInOrder = config.pages.order.filter { config.pages.enabled.contains($0) }
        config.pages.enabled = Set(enabledPagesInOrder.isEmpty ? [.clock] : enabledPagesInOrder)
    }

    private var previousVisiblePage: DashboardPage? {
        let pages = visiblePages
        guard let index = pages.firstIndex(of: page), index > 0 else { return nil }
        return pages[index - 1]
    }

    private var nextVisiblePage: DashboardPage? {
        let pages = visiblePages
        guard let index = pages.firstIndex(of: page), index < pages.count - 1 else { return nil }
        return pages[index + 1]
    }

    private func resetBurnInProtectionDates() {
        let now = Date()
        lastActivityDate = now
        displayCycleStartDate = now
        lastPixelShiftDate = .distantPast
        lastAutoPageRotationDate = now
        restStartedAt = nil
        pixelShiftStep = 0
        isResting = false
        dimOpacity = 0
        contentOffset = .zero
    }

    private func updateBurnInProtection(now: Date) {
        let protection = config.protection
        guard protection.mode != .off else {
            isResting = false
            restStartedAt = nil
            dimOpacity = 0
            contentOffset = .zero
            return
        }

        if isResting {
            guard let restStartedAt else {
                finishRest(at: now)
                return
            }

            if now.timeIntervalSince(restStartedAt) >= protection.rest.durationSeconds {
                finishRest(at: now)
            } else {
                dimOpacity = 1
                return
            }
        }

        if protection.mode == .strong,
           now.timeIntervalSince(displayCycleStartDate) >= protection.rest.afterSeconds {
            enterRest(at: now)
            return
        }

        updatePixelShiftIfNeeded(now: now, protection: protection)

        if now.timeIntervalSince(lastActivityDate) >= protection.dim.afterSeconds {
            dimOpacity = targetDimOpacity(for: protection)
        } else {
            dimOpacity = 0
        }
    }

    private func enterRest(at now: Date) {
        isResting = true
        restStartedAt = now
        dimOpacity = 1
        NSLog("GlancePane burn-in protection entered rest")
    }

    private func finishRest(at now: Date) {
        lastActivityDate = now
        displayCycleStartDate = now
        restStartedAt = nil
        isResting = false
        dimOpacity = 0
        lastPixelShiftDate = .distantPast
        NSLog("GlancePane burn-in protection exited rest")
    }

    private func updatePixelShiftIfNeeded(now: Date, protection: ProtectionConfig) {
        let radius = pixelShiftRadius(for: protection)
        guard radius > 0 else {
            contentOffset = .zero
            return
        }

        guard now.timeIntervalSince(lastPixelShiftDate) >= protection.pixelShift.intervalSeconds else {
            return
        }

        pixelShiftStep += 1
        lastPixelShiftDate = now
        contentOffset = Self.pixelShiftOffset(step: pixelShiftStep, radius: radius)
    }

    private func pixelShiftRadius(for protection: ProtectionConfig) -> Double {
        switch protection.mode {
        case .off:
            return 0
        case .subtle:
            return min(protection.pixelShift.pixels, 6)
        case .strong:
            return protection.pixelShift.pixels
        }
    }

    private func targetDimOpacity(for protection: ProtectionConfig) -> Double {
        switch protection.mode {
        case .off:
            return 0
        case .subtle:
            return min(protection.dim.opacity, 0.25)
        case .strong:
            return protection.dim.opacity
        }
    }

    private static func pixelShiftOffset(step: Int, radius: Double) -> CGSize {
        let sequence: [(Double, Double)] = [
            (-1.0, -0.6),
            (0.5, -1.0),
            (1.0, 0.4),
            (-0.3, 1.0),
            (-0.8, 0.2),
            (0.9, -0.3),
            (0.2, 0.8),
            (0.0, 0.0)
        ]
        let point = sequence[step % sequence.count]
        return CGSize(
            width: CGFloat(point.0 * radius),
            height: CGFloat(point.1 * radius)
        )
    }
}
