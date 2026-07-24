import SwiftUI

struct MarketPageView: View {
    let quotes: [StockQuote]
    let configuredSymbolCount: Int
    let status: FeedStatus
    let theme: ScreenTheme
    let scale: CGFloat

    private var visibleQuotes: [StockQuote] {
        Array(quotes.prefix(8))
    }

    var body: some View {
        SectionPanel(title: "Market", theme: theme, scale: scale) {
            VStack(alignment: .leading, spacing: DashboardLayout.gap * scale) {
                HStack(spacing: 12 * scale) {
                    StatusPill(title: status.title.uppercased(), color: statusColor, scale: scale)

                    if let updatedAt = quotes.map(\.updatedAt).max() {
                        Text("UPDATED \(DateFormatter.cached(format: "HH:mm:ss").string(from: updatedAt))")
                            .font(.system(size: DashboardTypography.status * scale, weight: .black, design: .monospaced))
                            .foregroundStyle(theme.secondaryText)
                    }

                    Spacer()

                    Text("\(visibleQuotes.count)/\(max(configuredSymbolCount, quotes.count)) SYMBOLS")
                        .font(.system(size: DashboardTypography.label * scale, weight: .black, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                }

                if quotes.isEmpty {
                    Text(status == .disabled ? "MARKET DISABLED" : "WAITING FOR QUOTES")
                        .font(.system(size: 28 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 440 * scale)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12 * scale) {
                        ForEach(visibleQuotes) { quote in
                            MarketQuoteCard(quote: quote, theme: theme, scale: scale)
                        }
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .live: return theme.green
        case .partial, .cached: return theme.amber
        case .offline: return theme.red
        default: return theme.blue
        }
    }
}

private struct MarketQuoteCard: View {
    let quote: StockQuote
    let theme: ScreenTheme
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 12 * scale) {
            VStack(alignment: .leading, spacing: 7 * scale) {
                HStack(spacing: 7 * scale) {
                    Text(quote.symbol)
                        .font(.system(size: 36 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if quote.marketState.uppercased() != "UNKNOWN" {
                        MarketBadge(title: quote.marketState.uppercased(), color: theme.secondaryText, scale: scale)
                    }

                    if quote.isCached {
                        MarketBadge(title: "CACHED", color: theme.amber, scale: scale)
                    }
                }

                Text(quote.name.isEmpty ? quote.marketState : quote.name)
                    .font(.system(size: 19 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12 * scale)

            VStack(alignment: .trailing, spacing: 8 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 9 * scale) {
                    Text(quote.currency)
                        .font(.system(size: DashboardTypography.status * scale, weight: .black, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                    Text(quote.price.formattedPrice())
                        .font(.system(size: 46 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()
                }

                Text("\(quote.isUp ? "+" : "")\(quote.change.formattedPrice())  \(quote.isUp ? "+" : "")\(quote.changePercent.formattedPercent())")
                    .font(.system(size: 26 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(quote.isUp ? theme.green : theme.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 12 * scale)
        .frame(maxWidth: .infinity, minHeight: 135 * scale, alignment: .center)
        .background(theme.tileBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale)
                .stroke(quote.isUp ? theme.green.opacity(0.34) : theme.red.opacity(0.34), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.panelCornerRadius * scale))
    }
}

private struct MarketBadge: View {
    let title: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: DashboardTypography.status * scale, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 4 * scale)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
