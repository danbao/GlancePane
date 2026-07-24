import Foundation

enum CodexExecutableResolver {
    static func executableURL(configuredPath: String?, fileManager: FileManager = .default) -> URL? {
        var candidates: [String] = []
        if let configuredPath, !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(configuredPath)
        }
        candidates += [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "~/.local/bin/codex"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/codex" }
        }

        var seen = Set<String>()
        for path in candidates {
            let expanded = NSString(string: path).expandingTildeInPath
            guard seen.insert(expanded).inserted,
                  fileManager.isExecutableFile(atPath: expanded) else { continue }
            return URL(fileURLWithPath: expanded)
        }
        return nil
    }

    static func codexHomeURL(configuredPath: String?) -> URL {
        let configured = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let path = [configured, environment]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? "~/.codex"
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }
}

actor CodexUsageService {
    typealias ClientFactory = (URL) -> CodexAccountFetching
    typealias ExecutableResolver = (String?, FileManager) -> URL?

    private struct AccountCache: Codable {
        let account: CodexAccountUsage?
        let rateLimits: CodexRateLimits?
        let updatedAt: Date
    }

    private let cacheURL: URL
    private let fileManager: FileManager
    private let makeClient: ClientFactory
    private let resolveExecutable: ExecutableResolver
    private var activeClient: CodexAccountFetching?
    private var stopRequested = false

    init(
        cacheURL: URL,
        fileManager: FileManager = .default,
        makeClient: @escaping ClientFactory = { CodexAppServerClient(executableURL: $0) },
        resolveExecutable: @escaping ExecutableResolver = CodexExecutableResolver.executableURL
    ) {
        self.cacheURL = cacheURL
        self.fileManager = fileManager
        self.makeClient = makeClient
        self.resolveExecutable = resolveExecutable
    }

    func run(
        config: CodexAgentConfig,
        onUpdate: @escaping @MainActor (CodexUsageSnapshot) -> Void
    ) async {
        stopRequested = false
        var snapshot = loadCachedSnapshot() ?? .empty

        guard config.enabled else {
            snapshot.status = .disabled
            snapshot.message = nil
            await onUpdate(snapshot)
            return
        }

        let codexHomeURL = CodexExecutableResolver.codexHomeURL(configuredPath: config.codexHomePath)
        let collector = CodexSessionCollector(codexHomeURL: codexHomeURL, fileManager: fileManager)
        guard let executableURL = resolveExecutable(config.executablePath, fileManager) else {
            while !Task.isCancelled && !stopRequested {
                snapshot.sessions = collector.collect(
                    limit: config.recentSessionCount,
                    showProjectNames: config.showProjectNames
                )
                snapshot.status = snapshot.account == nil ? .setup : .cached
                snapshot.message = "Codex CLI not found"
                await onUpdate(snapshot)
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }
            }
            return
        }

        var client: CodexAccountFetching?
        var lastUsageRefresh = Date.distantPast
        var lastLimitsRefresh = Date.distantPast
        var nextConnectionAttempt = Date.distantPast
        var failureCount = 0

        while !Task.isCancelled && !stopRequested {
            let now = Date()
            snapshot.sessions = collector.collect(
                limit: config.recentSessionCount,
                showProjectNames: config.showProjectNames,
                now: now
            )

            let usageDue = now.timeIntervalSince(lastUsageRefresh) >= 300
            let limitsDue = now.timeIntervalSince(lastLimitsRefresh) >= 60
            if (usageDue || limitsDue), now >= nextConnectionAttempt {
                do {
                    if client == nil {
                        let created = makeClient(executableURL)
                        client = created
                        activeClient = created
                        try await created.start()
                    }

                    var successfulRequests = 0
                    var errors: [Error] = []
                    var usageFailed = false
                    var limitsFailed = false
                    if usageDue, let client {
                        do {
                            snapshot.account = try await client.fetchUsage()
                            lastUsageRefresh = now
                            successfulRequests += 1
                        } catch {
                            errors.append(error)
                            usageFailed = true
                        }
                    }
                    if limitsDue, let client {
                        do {
                            snapshot.rateLimits = try await client.fetchRateLimits()
                            lastLimitsRefresh = now
                            successfulRequests += 1
                        } catch {
                            errors.append(error)
                            limitsFailed = true
                        }
                    }

                    if successfulRequests > 0 {
                        if usageFailed { lastUsageRefresh = now }
                        if limitsFailed { lastLimitsRefresh = now }
                        snapshot.status = .live
                        snapshot.message = errors.first.map { "Partial: \($0.localizedDescription)" }
                        snapshot.updatedAt = now
                        failureCount = 0
                        nextConnectionAttempt = .distantPast
                        saveCache(snapshot)
                    } else if let error = errors.first {
                        throw error
                    }
                } catch {
                    if let client { await client.stop() }
                    client = nil
                    activeClient = nil
                    failureCount += 1
                    let delays: [TimeInterval] = [5, 15, 60]
                    let delay = delays[min(failureCount - 1, delays.count - 1)]
                    nextConnectionAttempt = now.addingTimeInterval(delay)
                    snapshot.status = snapshot.account == nil && snapshot.rateLimits == nil ? .error : .cached
                    snapshot.message = error.localizedDescription
                }
            }

            await onUpdate(snapshot)
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                break
            }
        }

        if let client { await client.stop() }
        activeClient = nil
    }

    func stop() async {
        stopRequested = true
        if let activeClient { await activeClient.stop() }
        activeClient = nil
    }

    private func loadCachedSnapshot() -> CodexUsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(AccountCache.self, from: data) else { return nil }
        return CodexUsageSnapshot(
            account: cache.account,
            rateLimits: cache.rateLimits,
            sessions: [],
            status: .cached,
            message: nil,
            updatedAt: cache.updatedAt
        )
    }

    private func saveCache(_ snapshot: CodexUsageSnapshot) {
        let cache = AccountCache(
            account: snapshot.account,
            rateLimits: snapshot.rateLimits,
            updatedAt: snapshot.updatedAt ?? Date()
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try SecureFileStore.write(
                encoder.encode(cache),
                to: cacheURL,
                fileManager: fileManager
            )
        } catch {
            NSLog("GlancePane failed to cache Codex usage: \(error)")
        }
    }
}
