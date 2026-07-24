import Foundation

final class CodexSessionCollector {
    private struct FileState {
        var offset: UInt64
        var buffer: Data
        var droppingOversizedLine: Bool
        var usage: CodexSessionUsage
    }

    private let fileManager: FileManager
    private let sessionsURL: URL
    private let discoveryIntervalSeconds: TimeInterval
    private let initialTailByteLimit: UInt64
    private var trackedURLs: [URL] = []
    private var states: [URL: FileState] = [:]
    private var lastDiscoveryDate = Date.distantPast
    private let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let standardDateFormatter = ISO8601DateFormatter()

    init(
        codexHomeURL: URL,
        fileManager: FileManager = .default,
        discoveryIntervalSeconds: TimeInterval = 10,
        initialTailByteLimit: UInt64 = 2_000_000
    ) {
        self.fileManager = fileManager
        sessionsURL = codexHomeURL.appendingPathComponent("sessions", isDirectory: true)
        self.discoveryIntervalSeconds = discoveryIntervalSeconds
        self.initialTailByteLimit = initialTailByteLimit
    }

    func collect(
        limit: Int,
        showProjectNames: Bool,
        now: Date = Date()
    ) -> [CodexSessionUsage] {
        if trackedURLs.isEmpty || now.timeIntervalSince(lastDiscoveryDate) >= discoveryIntervalSeconds {
            discoverRecentFiles(now: now)
        }

        for url in trackedURLs {
            update(url: url)
        }

        let cutoff = now.addingTimeInterval(-86_400)
        let activeCutoff = now.addingTimeInterval(-900)
        var sessions = states.values
            .map(\.usage)
            .filter { $0.updatedAt >= cutoff && ($0.contextWindow > 0 || $0.sessionTotalTokens > 0) }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt { return lhs.id < rhs.id }
                return lhs.updatedAt > rhs.updatedAt
            }

        let maximum = min(3, max(1, limit))
        if sessions.count > maximum {
            sessions = Array(sessions.prefix(maximum))
        }

        for index in sessions.indices {
            sessions[index].isActive = sessions[index].updatedAt >= activeCutoff
            if !showProjectNames {
                sessions[index].projectName = "SESSION \(index + 1)"
            }
        }
        return sessions
    }

    private func discoverRecentFiles(now: Date) {
        lastDiscoveryDate = now
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            trackedURLs = []
            return
        }

        let cutoff = now.addingTimeInterval(-86_400)
        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if modifiedAt >= cutoff {
                candidates.append((url, modifiedAt))
            }
        }

        trackedURLs = candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(12)
            .map(\.url)

        let retained = Set(trackedURLs)
        states = states.filter { retained.contains($0.key) }
    }

    private func update(url: URL) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber else { return }
        let size = number.uint64Value

        if states[url] == nil || size < (states[url]?.offset ?? 0) {
            states[url] = initialState(for: url, size: size)
            return
        }

        guard var state = states[url], size > state.offset else { return }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            let data = try handle.readToEnd() ?? Data()
            state.offset = size
            process(data: data, state: &state)
            states[url] = state
        } catch {
            return
        }
    }

    private func initialState(for url: URL, size: UInt64) -> FileState {
        let fallbackID = url.deletingPathExtension().lastPathComponent
        var state = FileState(
            offset: 0,
            buffer: Data(),
            droppingOversizedLine: false,
            usage: CodexSessionUsage(
                id: fallbackID,
                projectName: "CODEX",
                model: "Codex",
                updatedAt: .distantPast,
                contextTokens: 0,
                contextWindow: 0,
                inputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                reasoningOutputTokens: 0,
                sessionTotalTokens: 0,
                isActive: false
            )
        )

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            state.usage.updatedAt = modificationDate(for: url) ?? .distantPast
            return state
        }
        defer { try? handle.close() }

        do {
            let head = try handle.read(upToCount: 65_536) ?? Data()
            parseCompleteLines(in: head, state: &state, retainTrailingPartial: false)

            let startOffset = size > initialTailByteLimit ? size - initialTailByteLimit : 0
            try handle.seek(toOffset: startOffset)
            var tail = try handle.readToEnd() ?? Data()
            if startOffset > 0, let newline = tail.firstIndex(of: 0x0A) {
                tail.removeSubrange(...newline)
            }
            state.offset = size
            process(data: tail, state: &state)
        } catch {
            state.offset = size
        }
        if state.usage.updatedAt == .distantPast {
            state.usage.updatedAt = modificationDate(for: url) ?? .distantPast
        }
        return state
    }

    private func process(data: Data, state: inout FileState) {
        guard !data.isEmpty else { return }
        var incoming = data

        if state.droppingOversizedLine {
            guard let newline = incoming.firstIndex(of: 0x0A) else { return }
            incoming.removeSubrange(...newline)
            state.droppingOversizedLine = false
        }

        state.buffer.append(incoming)
        parseCompleteLines(in: state.buffer, state: &state, retainTrailingPartial: true)
        if state.buffer.count > 1_000_000 {
            state.buffer.removeAll(keepingCapacity: false)
            state.droppingOversizedLine = true
        }
    }

    private func parseCompleteLines(in data: Data, state: inout FileState, retainTrailingPartial: Bool) {
        var working = data
        while let newline = working.firstIndex(of: 0x0A) {
            var line = Data(working[..<newline])
            working.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            parse(line: line, usage: &state.usage)
        }
        state.buffer = retainTrailingPartial ? working : Data()
    }

    private func parse(line: Data, usage: inout CodexSessionUsage) {
        guard line.count <= 512_000,
              hasSupportedEnvelope(line),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return }

        let eventDate = (object["timestamp"] as? String).flatMap(parseDate)

        switch type {
        case "session_meta":
            if let id = payload["id"] as? String { usage.id = id }
            if let cwd = payload["cwd"] as? String { usage.projectName = projectName(from: cwd) }
            updateTimestamp(eventDate, usage: &usage)
        case "turn_context":
            if let model = payload["model"] as? String, !model.isEmpty { usage.model = model }
            if let cwd = payload["cwd"] as? String { usage.projectName = projectName(from: cwd) }
            updateTimestamp(eventDate, usage: &usage)
        case "event_msg":
            guard payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any] else { return }
            let last = info["last_token_usage"] as? [String: Any] ?? [:]
            let total = info["total_token_usage"] as? [String: Any] ?? [:]
            usage.contextTokens = int64(last["total_tokens"])
            usage.contextWindow = int64(info["model_context_window"])
            usage.inputTokens = int64(last["input_tokens"])
            usage.cachedInputTokens = int64(last["cached_input_tokens"])
            usage.outputTokens = int64(last["output_tokens"])
            usage.reasoningOutputTokens = int64(last["reasoning_output_tokens"])
            usage.sessionTotalTokens = int64(total["total_tokens"])
            updateTimestamp(eventDate, usage: &usage)
        default:
            return
        }
    }

    private func hasSupportedEnvelope(_ line: Data) -> Bool {
        let prefix = Data(line.prefix(1_024))
        if containsType("session_meta", in: prefix) || containsType("turn_context", in: prefix) {
            return true
        }
        return containsType("event_msg", in: prefix) && containsType("token_count", in: prefix)
    }

    private func containsType(_ type: String, in data: Data) -> Bool {
        let compact = Data("\"type\":\"\(type)\"".utf8)
        let spaced = Data("\"type\": \"\(type)\"".utf8)
        return data.range(of: compact) != nil || data.range(of: spaced) != nil
    }

    private func updateTimestamp(_ date: Date?, usage: inout CodexSessionUsage) {
        guard let date else { return }
        usage.updatedAt = max(usage.updatedAt, date)
    }

    private func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? String, let parsed = Int64(value) { return parsed }
        return 0
    }

    private func parseDate(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? standardDateFormatter.date(from: value)
    }

    private func projectName(from path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "CODEX" : name
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
