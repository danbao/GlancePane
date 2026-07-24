import Foundation

final class StockService {
    private let cacheURL: URL
    private let client: HTTPClient

    init(cacheURL: URL, client: HTTPClient? = nil) {
        self.cacheURL = cacheURL

        if let client {
            self.client = client
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 12
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) GlancePane/0.1"
            ]
            self.client = URLSessionHTTPClient(configuration: config)
        }
    }

    func loadCached(symbols: [String]) -> [StockQuote] {
        guard let snapshot = readCache() else { return [] }
        let wanted = Set(symbols)
        return snapshot.quotes
            .filter { wanted.contains($0.symbol) }
            .map { quote in
                var cached = quote
                cached.isCached = true
                return cached
            }
    }

    func fetch(symbols: [String]) async -> Result<[StockQuote], StockFetchError> {
        let normalized = normalizedSymbols(symbols)

        guard !normalized.isEmpty else {
            return .success([])
        }

        let cached = loadCached(symbols: normalized)
        var liveBySymbol: [String: StockQuote] = [:]
        var errors: [String] = []

        do {
            for quote in try await fetchYahooBatchQuotes(symbols: normalized) {
                liveBySymbol[quote.symbol] = quote
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        let missingSymbols = normalized.filter { liveBySymbol[$0] == nil }
        let fallbackResults = await fetchYahooChartQuotesIndividually(symbols: missingSymbols)
        for result in fallbackResults {
            if let quote = result.quote {
                liveBySymbol[result.symbol] = quote
            } else if let message = result.errorMessage {
                errors.append("\(result.symbol): \(message)")
            }
        }

        let cachedBySymbol = Dictionary(uniqueKeysWithValues: cached.map { ($0.symbol, $0) })
        let quotes = normalized.compactMap { liveBySymbol[$0] ?? cachedBySymbol[$0] }
        let liveCount = quotes.filter { !$0.isCached }.count

        guard !quotes.isEmpty else {
            return .failure(.network(errors.first ?? "No stock data returned"))
        }

        if liveCount == 0 {
            return .failure(.usingCache(quotes, errors.first ?? "Live stock data unavailable"))
        }

        writeCache(StockSnapshot(quotes: quotes, fetchedAt: Date()))
        return .success(quotes)
    }

    private func normalizedSymbols(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func fetchYahooBatchQuotes(symbols: [String]) async throws -> [StockQuote] {
        let joined = symbols
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
            .joined(separator: ",")
        guard let url = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(joined)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await client.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(YahooQuoteResponse.self, from: data)
        let now = Date()

        return decoded.quoteResponse.result.map { item in
            let price = item.regularMarketPrice ?? item.postMarketPrice ?? item.preMarketPrice ?? 0
            let previousClose = item.regularMarketPreviousClose ?? price
            let change = item.regularMarketChange ?? (price - previousClose)
            let percent = item.regularMarketChangePercent
                ?? (previousClose == 0 ? 0 : change / previousClose * 100)

            return StockQuote(
                symbol: item.symbol.uppercased(),
                name: item.longName ?? item.shortName ?? item.symbol.uppercased(),
                price: price,
                change: change,
                changePercent: percent,
                currency: item.currency ?? "USD",
                marketState: item.marketState ?? "UNKNOWN",
                updatedAt: now,
                isCached: false
            )
        }
        .sorted { left, right in
            guard let leftIndex = symbols.firstIndex(of: left.symbol),
                  let rightIndex = symbols.firstIndex(of: right.symbol)
            else {
                return left.symbol < right.symbol
            }
            return leftIndex < rightIndex
        }
    }

    private func fetchYahooChartQuotesIndividually(symbols: [String]) async -> [StockChartFetchResult] {
        await withTaskGroup(of: StockChartFetchResult.self) { group in
            for symbol in symbols {
                group.addTask { [weak self] in
                    guard let self else {
                        return StockChartFetchResult(symbol: symbol, quote: nil, errorMessage: "Service unavailable")
                    }
                    do {
                        let quote = try await self.fetchYahooChartQuote(symbol: symbol)
                        return StockChartFetchResult(symbol: symbol, quote: quote, errorMessage: nil)
                    } catch {
                        return StockChartFetchResult(symbol: symbol, quote: nil, errorMessage: error.localizedDescription)
                    }
                }
            }

            var results: [StockChartFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func fetchYahooChartQuote(symbol: String) async throws -> StockQuote {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: allowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encodedSymbol)?interval=1d&range=1d") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await client.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)
        guard let meta = decoded.chart.result?.first?.meta else {
            throw URLError(.cannotParseResponse)
        }

        let price = meta.regularMarketPrice ?? 0
        let previousClose = meta.chartPreviousClose ?? meta.previousClose ?? price
        let change = price - previousClose
        let percent = previousClose == 0 ? 0 : change / previousClose * 100

        return StockQuote(
            symbol: meta.symbol.uppercased(),
            name: meta.longName ?? meta.shortName ?? meta.symbol.uppercased(),
            price: price,
            change: change,
            changePercent: percent,
            currency: meta.currency ?? "USD",
            marketState: meta.marketState ?? "UNKNOWN",
            updatedAt: Date(),
            isCached: false
        )
    }

    private func readCache() -> StockSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(StockSnapshot.self, from: data)
    }

    private func writeCache(_ snapshot: StockSnapshot) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try SecureFileStore.write(encoder.encode(snapshot), to: cacheURL)
        } catch {
            NSLog("GlancePane failed to write stock cache: \(error)")
        }
    }
}

private struct StockChartFetchResult: Sendable {
    let symbol: String
    let quote: StockQuote?
    let errorMessage: String?
}

enum StockFetchError: Error, Equatable {
    case network(String)
    case usingCache([StockQuote], String)
}

private struct YahooQuoteResponse: Decodable {
    let quoteResponse: YahooQuoteResult
}

private struct YahooQuoteResult: Decodable {
    let result: [YahooQuote]
}

private struct YahooQuote: Decodable {
    let symbol: String
    let shortName: String?
    let longName: String?
    let regularMarketPrice: Double?
    let regularMarketPreviousClose: Double?
    let regularMarketChange: Double?
    let regularMarketChangePercent: Double?
    let preMarketPrice: Double?
    let postMarketPrice: Double?
    let currency: String?
    let marketState: String?
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChartContainer
}

private struct YahooChartContainer: Decodable {
    let result: [YahooChartResult]?
}

private struct YahooChartResult: Decodable {
    let meta: YahooChartMeta
}

private struct YahooChartMeta: Decodable {
    let currency: String?
    let symbol: String
    let longName: String?
    let shortName: String?
    let regularMarketPrice: Double?
    let chartPreviousClose: Double?
    let previousClose: Double?
    let marketState: String?
}
