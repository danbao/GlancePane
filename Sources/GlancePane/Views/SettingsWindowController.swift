import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var displays: [DisplayDescriptor]
    @Published private(set) var loginStatus: LoginItemStatus
    @Published var loginError: String?

    private let onConfigChange: (AppConfig) -> Void
    private let onLoginChange: (Bool) throws -> Void
    private let onOpenLoginSettings: () -> Void
    private let onOpenConfigFolder: () -> Void
    private let onImportConfig: () -> Void
    private let onExportConfig: () -> Void
    private let onResetConfig: () -> Void
    private let onReconnectCodex: () -> Void
    private let onOpenCodexFolder: () -> Void

    init(
        config: AppConfig,
        displays: [DisplayDescriptor],
        loginStatus: LoginItemStatus,
        onConfigChange: @escaping (AppConfig) -> Void,
        onLoginChange: @escaping (Bool) throws -> Void,
        onOpenLoginSettings: @escaping () -> Void,
        onOpenConfigFolder: @escaping () -> Void,
        onImportConfig: @escaping () -> Void,
        onExportConfig: @escaping () -> Void,
        onResetConfig: @escaping () -> Void,
        onReconnectCodex: @escaping () -> Void = {},
        onOpenCodexFolder: @escaping () -> Void = {}
    ) {
        self.config = config
        self.displays = displays
        self.loginStatus = loginStatus
        self.onConfigChange = onConfigChange
        self.onLoginChange = onLoginChange
        self.onOpenLoginSettings = onOpenLoginSettings
        self.onOpenConfigFolder = onOpenConfigFolder
        self.onImportConfig = onImportConfig
        self.onExportConfig = onExportConfig
        self.onResetConfig = onResetConfig
        self.onReconnectCodex = onReconnectCodex
        self.onOpenCodexFolder = onOpenCodexFolder
    }

    func refresh(config: AppConfig, displays: [DisplayDescriptor], loginStatus: LoginItemStatus) {
        self.config = config
        self.displays = displays
        self.loginStatus = loginStatus
        loginError = nil
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { value in
                self.update { $0[keyPath: keyPath] = value }
            }
        )
    }

    var displaySelectionBinding: Binding<String> {
        Binding(
            get: {
                if let targetID = self.config.display.targetID {
                    return targetID
                }
                return self.config.display.targetName.isEmpty
                    ? ""
                    : "legacy:\(self.config.display.targetName)"
            },
            set: { selection in
                self.update { config in
                    guard !selection.isEmpty else {
                        config.display = .default
                        return
                    }
                    guard let display = self.displays.first(where: { $0.persistentID == selection }) else {
                        return
                    }
                    config.display.targetID = display.persistentID
                    config.display.targetName = display.name
                }
            }
        )
    }

    var unresolvedDisplayLabel: String? {
        guard config.display.targetID == nil, !config.display.targetName.isEmpty else { return nil }
        return "Unavailable: \(config.display.targetName)"
    }

    func pageBinding(_ page: DashboardPage) -> Binding<Bool> {
        Binding(
            get: { self.config.pages.enabled.contains(page) },
            set: { enabled in
                self.update { config in
                    if enabled {
                        config.pages.enabled.insert(page)
                    } else {
                        config.pages.enabled.remove(page)
                    }
                }
            }
        )
    }

    func groupBinding(_ group: SystemMetricGroup) -> Binding<Bool> {
        Binding(
            get: { self.config.system.enabledGroups.contains(group) },
            set: { enabled in
                self.update { config in
                    if enabled {
                        config.system.enabledGroups.insert(group)
                    } else {
                        config.system.enabledGroups.remove(group)
                    }
                }
            }
        )
    }

    func movePage(_ page: DashboardPage, offset: Int) {
        update { config in
            guard let index = config.pages.order.firstIndex(of: page) else { return }
            let destination = min(config.pages.order.count - 1, max(0, index + offset))
            guard destination != index else { return }
            config.pages.order.remove(at: index)
            config.pages.order.insert(page, at: destination)
        }
    }

    var marketSymbols: String {
        get { config.market.symbols.joined(separator: ", ") }
        set {
            update { config in
                config.market.symbols = newValue.split(separator: ",").map(String.init)
            }
        }
    }

    var codexExecutablePath: String {
        get { config.agents.codex.executablePath ?? "" }
        set { update { $0.agents.codex.executablePath = newValue.isEmpty ? nil : newValue } }
    }

    var codexHomePath: String {
        get { config.agents.codex.codexHomePath ?? "" }
        set { update { $0.agents.codex.codexHomePath = newValue.isEmpty ? nil : newValue } }
    }

    var detectedCodexExecutablePath: String? {
        CodexExecutableResolver.executableURL(configuredPath: config.agents.codex.executablePath)?.path
    }

    var effectiveCodexHomePath: String {
        CodexExecutableResolver.codexHomeURL(configuredPath: config.agents.codex.codexHomePath).path
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try onLoginChange(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }

    func updateLoginStatus(_ status: LoginItemStatus) {
        loginStatus = status
    }

    func openLoginSettings() { onOpenLoginSettings() }
    func openConfigFolder() { onOpenConfigFolder() }
    func importConfig() { onImportConfig() }
    func exportConfig() { onExportConfig() }
    func resetConfig() { onResetConfig() }
    func reconnectCodex() { onReconnectCodex() }
    func openCodexFolder() { onOpenCodexFolder() }
    func useAutomaticCodexPaths() {
        update {
            $0.agents.codex.executablePath = nil
            $0.agents.codex.codexHomePath = nil
        }
    }

    private func update(_ mutate: (inout AppConfig) -> Void) {
        var next = config
        mutate(&next)
        next = next.normalized()
        config = next
        onConfigChange(next)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    let viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        let content = SettingsView(model: viewModel)
            .frame(minWidth: 780, minHeight: 580)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GlancePane Settings"
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case monitoring = "Monitoring"
    case agents = "Agents"
    case appearance = "Appearance"
    case behavior = "Display & Behavior"
    case data = "Data & Advanced"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .monitoring: return "waveform.path.ecg"
        case .agents: return "terminal"
        case .appearance: return "paintpalette"
        case .behavior: return "display"
        case .data: return "externaldrive"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var selection: SettingsSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardSettingsView(model: model)
                case .monitoring: MonitoringSettingsView(model: model)
                case .agents: AgentsSettingsView(model: model)
                case .appearance: AppearanceSettingsView(model: model)
                case .behavior: BehaviorSettingsView(model: model)
                case .data: DataSettingsView(model: model)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct DashboardSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Pages") {
                ForEach(model.config.pages.order, id: \.self) { page in
                    HStack {
                        Toggle(page.title, isOn: model.pageBinding(page))
                        Spacer()
                        Button { model.movePage(page, offset: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(page == model.config.pages.order.first)
                            .help("Move earlier")
                        Button { model.movePage(page, offset: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(page == model.config.pages.order.last)
                            .help("Move later")
                    }
                }
            }
            Section("Rotation") {
                Toggle("Auto Page Rotation", isOn: model.binding(\.pages.rotation.enabled))
                Picker("Page Duration", selection: model.binding(\.pages.rotation.intervalSeconds)) {
                    Text("15 seconds").tag(TimeInterval(15))
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("60 seconds").tag(TimeInterval(60))
                    Text("90 seconds").tag(TimeInterval(90))
                    Text("2 minutes").tag(TimeInterval(120))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MonitoringSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Metric Groups") {
                ForEach(SystemMetricGroup.allCases, id: \.self) { group in
                    Toggle(group.title, isOn: model.groupBinding(group))
                }
            }
            Section("History & Processes") {
                Toggle("Keep Short-Term History", isOn: model.binding(\.system.history.enabled))
                Picker("History Window", selection: model.binding(\.system.history.durationSeconds)) {
                    Text("10 minutes").tag(TimeInterval(600))
                    Text("30 minutes").tag(TimeInterval(1_800))
                    Text("60 minutes").tag(TimeInterval(3_600))
                }
                Toggle("Top Processes", isOn: model.binding(\.system.processes.enabled))
                Picker("Process Refresh", selection: model.binding(\.system.processes.refreshIntervalSeconds)) {
                    Text("2 seconds").tag(TimeInterval(2))
                    Text("5 seconds").tag(TimeInterval(5))
                    Text("10 seconds").tag(TimeInterval(10))
                }
            }
            Section("Network Quality") {
                Toggle("TCP Latency Probe", isOn: model.binding(\.system.networkQuality.enabled))
                TextField("Host", text: model.binding(\.system.networkQuality.host))
                TextField("Port", value: model.binding(\.system.networkQuality.port), format: .number)
            }
            Section("Health Thresholds") {
                Stepper(value: model.binding(\.system.thresholds.cpuHighPercent), in: 50...100, step: 5) {
                    LabeledContent("High CPU", value: "\(Int(model.config.system.thresholds.cpuHighPercent))%")
                }
                Stepper(value: model.binding(\.system.thresholds.diskFreePercent), in: 2...30, step: 1) {
                    LabeledContent("Low Disk Free", value: "\(Int(model.config.system.thresholds.diskFreePercent))%")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AgentsSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Codex") {
                Toggle("Codex Usage", isOn: model.binding(\.agents.codex.enabled))
                LabeledContent(
                    "CLI Status",
                    value: model.detectedCodexExecutablePath == nil ? "Not Found" : "Ready"
                )
                if let path = model.detectedCodexExecutablePath {
                    LabeledContent("Detected CLI", value: path)
                        .lineLimit(1)
                }
                TextField(
                    "Executable Path (auto when blank)",
                    text: Binding(get: { model.codexExecutablePath }, set: { model.codexExecutablePath = $0 })
                )
                TextField(
                    "Codex Home (auto when blank)",
                    text: Binding(get: { model.codexHomePath }, set: { model.codexHomePath = $0 })
                )
                LabeledContent("Effective Home", value: model.effectiveCodexHomePath)
                    .lineLimit(1)
            }

            Section("Session Display") {
                Toggle("Show Project Names", isOn: model.binding(\.agents.codex.showProjectNames))
                Stepper(value: model.binding(\.agents.codex.recentSessionCount), in: 1...3) {
                    LabeledContent("Recent Sessions", value: "\(model.config.agents.codex.recentSessionCount)")
                }
            }

            Section("Actions") {
                HStack {
                    Button(action: model.reconnectCodex) {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    Button(action: model.openCodexFolder) {
                        Label("Open Codex Folder", systemImage: "folder")
                    }
                    Button(action: model.useAutomaticCodexPaths) {
                        Label("Use Automatic Paths", systemImage: "wand.and.stars")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: model.binding(\.appearance.theme)) {
                    ForEach(ThemeName.allCases, id: \.self) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Units") {
                Picker("Temperature", selection: model.binding(\.appearance.units.temperature)) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
                Picker("Data Rate", selection: model.binding(\.appearance.units.dataRate)) {
                    Text("Bytes per second").tag(DataRateUnit.bytes)
                    Text("Bits per second").tag(DataRateUnit.bits)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Display") {
                Picker("Target Display", selection: model.displaySelectionBinding) {
                    Text("Automatic (Smallest Secondary)").tag("")
                    if let unresolved = model.unresolvedDisplayLabel {
                        Text(unresolved).tag("legacy:\(model.config.display.targetName)")
                    }
                    ForEach(model.displays, id: \.id) { display in
                        Text(display.settingsLabel).tag(display.persistentID)
                    }
                }
                Toggle("Click Navigation", isOn: model.binding(\.interaction.clickNavigationEnabled))
            }
            Section("Startup") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { model.loginStatus.isEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .disabled(model.loginStatus == .requiresApproval || model.loginStatus == .unavailable)
                LabeledContent("System Status", value: model.loginStatus.title)
                if model.loginStatus == .requiresApproval {
                    Button("Open Login Items Settings", action: model.openLoginSettings)
                }
                if let error = model.loginError {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
            Section("Burn-in Protection") {
                Picker("Mode", selection: model.binding(\.protection.mode)) {
                    ForEach(BurnInProtectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                Toggle("Wake on Pointer", isOn: model.binding(\.protection.wakeOnPointer))
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Market") {
                Toggle("Market Data", isOn: model.binding(\.market.enabled))
                TextField("Symbols", text: Binding(get: { model.marketSymbols }, set: { model.marketSymbols = $0 }))
            }
            Section("Weather") {
                Picker("Provider", selection: model.binding(\.weather.provider)) {
                    Text("Open-Meteo (no key needed)").tag(WeatherProvider.openMeteo)
                    Text("QWeather").tag(WeatherProvider.qweather)
                }
                TextField("Location", text: model.binding(\.weather.location.name))
                TextField("Longitude", value: model.binding(\.weather.location.longitude), format: .number)
                TextField("Latitude", value: model.binding(\.weather.location.latitude), format: .number)

                if model.config.weather.provider == .qweather {
                    TextField("QWeather API Host", text: model.binding(\.weather.qweather.apiHost))
                    TextField("QWeather Key ID", text: model.binding(\.weather.qweather.keyID))
                    TextField("QWeather Project ID", text: model.binding(\.weather.qweather.projectID))
                    TextField("Private Key Path", text: model.binding(\.weather.qweather.privateKeyPath))
                }
            }
            Section("Configuration") {
                HStack {
                    Button("Import…", action: model.importConfig)
                    Button("Export…", action: model.exportConfig)
                    Button("Open Config Folder", action: model.openConfigFolder)
                    Spacer()
                    Button("Restore Defaults", role: .destructive, action: model.resetConfig)
                }
            }
        }
        .formStyle(.grouped)
    }
}
