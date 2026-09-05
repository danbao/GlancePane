import SwiftUI

struct DashboardPresentationState {
    var config: AppConfig
    var page: DashboardPage
    var snapshot: SystemSnapshot = .empty
    var history: SystemHistory = .empty
    var quotes: [StockQuote] = []
    var weatherSnapshot: WeatherSnapshot = .empty
    var codexUsage: CodexUsageSnapshot = .empty
    var currentDate = Date()
    var stockStatus: FeedStatus = .loading
    var weatherStatus: FeedStatus = .setup
    var contentOffset: CGSize = .zero
    var dimOpacity = 0.0
    var isResting = false
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        DashboardPresentationView(
            state: DashboardPresentationState(
                config: model.config,
                page: model.page,
                snapshot: model.snapshot,
                history: model.history,
                quotes: model.quotes,
                weatherSnapshot: model.weatherSnapshot,
                codexUsage: model.codexUsage,
                currentDate: model.currentDate,
                stockStatus: model.stockStatus,
                weatherStatus: model.weatherStatus,
                contentOffset: model.contentOffset,
                dimOpacity: model.dimOpacity,
                isResting: model.isResting
            )
        )
    }
}

struct DashboardPresentationView: View {
    let state: DashboardPresentationState

    var body: some View {
        GeometryReader { proxy in
            let theme = ScreenTheme(themeName: state.config.appearance.theme)
            let widthScale = proxy.size.width / DashboardLayout.referenceSize.width
            let heightScale = proxy.size.height / DashboardLayout.referenceSize.height
            let scale = max(0.55, min(widthScale, heightScale))
            ZStack {
                if state.page == .clock {
                    Color.black.ignoresSafeArea()
                } else {
                    theme.background.ignoresSafeArea()
                }

                Group {
                    switch state.page {
                    case .clock:
                        ClockPageView(date: state.currentDate, theme: theme, scale: scale)
                    case .system:
                        SystemPageView(
                            snapshot: state.snapshot,
                            history: state.history,
                            units: state.config.appearance.units,
                            theme: theme,
                            scale: scale
                        )
                    case .performance:
                        PerformancePageView(
                            snapshot: state.snapshot,
                            history: state.history,
                            units: state.config.appearance.units,
                            theme: theme,
                            scale: scale
                        )
                    case .agents:
                        AgentsPageView(
                            snapshot: state.codexUsage,
                            theme: theme,
                            scale: scale
                        )
                    case .market:
                        MarketPageView(
                            quotes: state.quotes,
                            configuredSymbolCount: state.config.market.symbols.count,
                            status: state.stockStatus,
                            theme: theme,
                            scale: scale
                        )
                    case .weather:
                        WeatherPageView(
                            snapshot: state.weatherSnapshot,
                            status: state.weatherStatus,
                            config: state.config,
                            theme: theme,
                            scale: scale
                        )
                    }
                }
                .id(state.page)
                .transition(.opacity)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(state.page == .clock ? 0 : DashboardLayout.pagePadding * scale)
                .offset(x: state.contentOffset.width, y: state.contentOffset.height)
                .animation(.easeInOut(duration: 0.8), value: state.contentOffset)

                if state.dimOpacity > 0 {
                    Color.black
                        .opacity(state.dimOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if state.isResting {
                    Color.black
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.18), value: state.page)
            .animation(.easeInOut(duration: 0.25), value: state.dimOpacity)
            .animation(.easeInOut(duration: 0.3), value: state.isResting)
        }
    }
}
