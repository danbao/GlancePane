import Foundation

protocol CodexAccountFetching: AnyObject {
    func start() async throws
    func fetchUsage() async throws -> CodexAccountUsage
    func fetchRateLimits() async throws -> CodexRateLimits
    func stop() async
}

enum CodexAppServerError: LocalizedError {
    case executableUnavailable
    case launchFailed(String)
    case notRunning
    case invalidResponse
    case requestFailed(String)
    case timedOut(String)
    case processExited(Int32)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "Codex CLI was not found"
        case .launchFailed(let message):
            return "Could not start Codex app-server: \(message)"
        case .notRunning:
            return "Codex app-server is not running"
        case .invalidResponse:
            return "Codex app-server returned an invalid response"
        case .requestFailed(let message):
            return message
        case .timedOut(let method):
            return "Codex app-server request timed out: \(method)"
        case .processExited(let status):
            return "Codex app-server exited with status \(status)"
        }
    }
}

actor CodexAppServerClient: CodexAccountFetching {
    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let executableURL: URL
    private let requestTimeoutSeconds: TimeInterval
    private let initializationTimeoutSeconds: TimeInterval
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var readerGeneration: UUID?
    private var readBuffer = Data()
    private var pending: [Int: PendingRequest] = [:]
    private var nextRequestID = 0

    init(
        executableURL: URL,
        requestTimeoutSeconds: TimeInterval = 10,
        initializationTimeoutSeconds: TimeInterval = 10
    ) {
        self.executableURL = executableURL
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.initializationTimeoutSeconds = initializationTimeoutSeconds
    }

    func start() async throws {
        if process?.isRunning == true { return }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] process in
            Task { await self?.processDidTerminate(status: process.terminationStatus) }
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        outputHandle = outputPipe.fileHandleForReading
        readBuffer.removeAll(keepingCapacity: true)

        do {
            try process.run()
            startReader(handle: outputPipe.fileHandleForReading)
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "glancepane",
                        "title": "GlancePane",
                        "version": "0.1.0"
                    ]
                ],
                timeoutSeconds: initializationTimeoutSeconds
            )
            try sendNotification(method: "initialized", params: [:])
        } catch {
            await stop()
            if let appServerError = error as? CodexAppServerError {
                throw appServerError
            }
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }
    }

    func fetchUsage() async throws -> CodexAccountUsage {
        let data = try await request(method: "account/usage/read", params: nil)
        let response = try JSONDecoder().decode(AccountUsageResponse.self, from: data)
        return CodexAccountUsage(
            lifetimeTokens: response.summary.lifetimeTokens,
            peakDailyTokens: response.summary.peakDailyTokens,
            longestRunningTurnSeconds: response.summary.longestRunningTurnSec,
            currentStreakDays: response.summary.currentStreakDays,
            longestStreakDays: response.summary.longestStreakDays,
            dailyUsage: (response.dailyUsageBuckets ?? []).map {
                CodexDailyUsage(date: $0.startDate, tokens: $0.tokens)
            }
        )
    }

    func fetchRateLimits() async throws -> CodexRateLimits {
        let data = try await request(method: "account/rateLimits/read", params: nil)
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        let limits = response.rateLimits
        return CodexRateLimits(
            planType: limits.planType,
            isUnlimited: limits.credits?.unlimited ?? false,
            hasCredits: limits.credits?.hasCredits ?? false,
            creditBalance: limits.credits?.balance,
            primary: limits.primary?.model,
            secondary: limits.secondary?.model
        )
    }

    func stop() async {
        let task = readerTask
        readerTask = nil
        readerGeneration = nil
        task?.cancel()
        try? inputHandle?.close()
        try? outputHandle?.close()
        inputHandle = nil
        outputHandle = nil
        readBuffer.removeAll(keepingCapacity: false)

        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
        failPending(with: CodexAppServerError.notRunning)
    }

    private func startReader(handle: FileHandle) {
        readerTask?.cancel()
        let generation = UUID()
        readerGeneration = generation
        readerTask = Task.detached(priority: .utility) { [weak self] in
            do {
                var chunk = Data()
                for try await byte in handle.bytes {
                    guard !Task.isCancelled else { return }
                    chunk.append(byte)
                    if byte == 0x0A || chunk.count >= 4_096 {
                        await self?.consume(chunk, readerGeneration: generation)
                        chunk.removeAll(keepingCapacity: true)
                    }
                }
                if !chunk.isEmpty {
                    await self?.consume(chunk, readerGeneration: generation)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await self?.readerDidFail(error, generation: generation)
            }
        }
    }

    private func request(
        method: String,
        params: [String: Any]?,
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> Data {
        guard process?.isRunning == true, let inputHandle else {
            throw CodexAppServerError.notRunning
        }

        nextRequestID += 1
        let requestID = nextRequestID
        var object: [String: Any] = ["method": method, "id": requestID]
        if let params { object["params"] = params }
        let payload = try framedJSON(object)

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                let timeout = timeoutSeconds ?? self?.requestTimeoutSeconds ?? 10
                let nanoseconds = UInt64(max(0.1, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self?.timeOut(requestID)
            }
            pending[requestID] = PendingRequest(method: method, continuation: continuation, timeoutTask: timeoutTask)

            do {
                try inputHandle.write(contentsOf: payload)
            } catch {
                if let request = pending.removeValue(forKey: requestID) {
                    request.timeoutTask.cancel()
                    request.continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        guard process?.isRunning == true, let inputHandle else {
            throw CodexAppServerError.notRunning
        }
        try inputHandle.write(contentsOf: framedJSON(["method": method, "params": params]))
    }

    private func framedJSON(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    private func consume(_ data: Data, readerGeneration generation: UUID) {
        guard readerGeneration == generation else { return }
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            var line = Data(readBuffer[..<newline])
            readBuffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty else { continue }
            consumeLine(line)
        }
    }

    private func consumeLine(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = (object["id"] as? NSNumber)?.intValue,
              let request = pending.removeValue(forKey: id) else {
            return
        }

        request.timeoutTask.cancel()
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex app-server request failed"
            request.continuation.resume(throwing: CodexAppServerError.requestFailed(message))
            return
        }

        guard let result = object["result"],
              let data = try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]) else {
            request.continuation.resume(throwing: CodexAppServerError.invalidResponse)
            return
        }
        request.continuation.resume(returning: data)
    }

    private func timeOut(_ id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(throwing: CodexAppServerError.timedOut(request.method))
    }

    private func processDidTerminate(status: Int32) {
        let task = readerTask
        readerTask = nil
        readerGeneration = nil
        task?.cancel()
        try? outputHandle?.close()
        inputHandle = nil
        outputHandle = nil
        process = nil
        failPending(with: CodexAppServerError.processExited(status))
    }

    private func readerDidFail(_ error: Error, generation: UUID) {
        guard readerGeneration == generation else { return }
        readerTask = nil
        readerGeneration = nil
        try? outputHandle?.close()
        outputHandle = nil
        failPending(
            with: CodexAppServerError.requestFailed(
                "Codex app-server output failed: \(error.localizedDescription)"
            )
        )
        if process?.isRunning == true {
            process?.terminate()
        }
    }

    private func failPending(with error: Error) {
        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}

private struct AccountUsageResponse: Decodable {
    let summary: AccountUsageSummary
    let dailyUsageBuckets: [AccountUsageBucket]?
}

private struct AccountUsageSummary: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

private struct AccountUsageBucket: Decodable {
    let startDate: String
    let tokens: Int64
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
}

private struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindowResponse?
    let secondary: RateLimitWindowResponse?
    let credits: CreditsResponse?
    let planType: String?
}

private struct RateLimitWindowResponse: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int64?
    let resetsAt: Int64?

    var model: CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: usedPercent,
            durationMinutes: windowDurationMins,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct CreditsResponse: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}
