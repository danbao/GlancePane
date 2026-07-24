import Foundation

struct StockQuote: Codable, Identifiable, Equatable, Sendable {
    var id: String { symbol }

    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let currency: String
    let marketState: String
    let updatedAt: Date
    var isCached: Bool

    var isUp: Bool {
        change >= 0
    }
}

struct StockSnapshot: Codable, Equatable {
    let quotes: [StockQuote]
    let fetchedAt: Date
}
