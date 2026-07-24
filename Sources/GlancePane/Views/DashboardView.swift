import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        GeometryReader { proxy in
            let theme = ScreenTheme(themeName: model.config.appearance.theme)
            let widthScale = proxy.size.width / DashboardLayout.referenceSize.width
            let heightScale = proxy.size.height / DashboardLayout.referenceSize.height
            let scale = max(0.55, min(widthScale, heightScale))
            ZStack {
                if model.page == .clock {
                    Color.black.ignoresSafeArea()
                } else {
                    theme.background.ignoresSafeArea()
                }

                Group {
                    switch model.page {
                    case .clock:
                        ClockPageView(date: model.currentDate, theme: theme, scale: scale)
                    case .system:
                        SystemPageView(
                            snapshot: model.snapshot,
                            history: model.history,
                            units: model.config.appearance.units,
                            theme: theme,
                            scale: scale
                        )
                    case .performance:
                        PerformancePageView(
                            snapshot: model.snapshot,
                            history: model.history,
                            units: model.config.appearance.units,
                            theme: theme,
                            scale: scale
                        )
                    case .agents:
                        AgentsPageView(
                            snapshot: model.codexUsage,
                            theme: theme,
                            scale: scale
                        )
                    case .market:
                        MarketPageView(
                            quotes: model.quotes,
                            configuredSymbolCount: model.config.market.symbols.count,
                            status: model.stockStatus,
                            theme: theme,
                            scale: scale
                        )
                    case .weather:
                        WeatherPageView(
                            snapshot: model.weatherSnapshot,
                            status: model.weatherStatus,
                            config: model.config,
                            theme: theme,
                            scale: scale
                        )
                    }
                }
                .id(model.page)
                .transition(.opacity)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(model.page == .clock ? 0 : DashboardLayout.pagePadding * scale)
                .offset(x: model.contentOffset.width, y: model.contentOffset.height)
                .animation(.easeInOut(duration: 0.8), value: model.contentOffset)

                if model.dimOpacity > 0 {
                    Color.black
                        .opacity(model.dimOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if model.isResting {
                    Color.black
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.18), value: model.page)
            .animation(.easeInOut(duration: 0.25), value: model.dimOpacity)
            .animation(.easeInOut(duration: 0.3), value: model.isResting)
        }
    }
}
