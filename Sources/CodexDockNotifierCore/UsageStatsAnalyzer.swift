import Foundation

public final class UsageStatsAnalyzer: @unchecked Sendable {
    private struct MutableSession {
        var id: String
        var title: String?
        var model: String?
        var provider: String?
        var cwd: String = ""
        var startedAt: Date?
        var updatedAt: Date?
        var usage: TokenUsage = .zero
        var eventCount = 0
        var completionCount = 0
    }

    private struct MutableDay {
        var date: Date
        var usage: TokenUsage = .zero
        var sessions: Set<String> = []
        var completionCount = 0
    }

    private let sessionsDirectory: URL
    private let sessionIndexFile: URL
    private let stateDatabaseFile: URL
    private let calendar: Calendar

    public init(
        sessionsDirectory: URL = CodexDefaultPaths.sessionsDirectory,
        sessionIndexFile: URL = CodexDefaultPaths.sessionIndexFile,
        stateDatabaseFile: URL = CodexDefaultPaths.codexStateDatabase,
        calendar: Calendar = .current
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexFile = sessionIndexFile
        self.stateDatabaseFile = stateDatabaseFile
        self.calendar = calendar
    }

    public func buildReport(now: Date = Date()) -> UsageReport {
        let threadInfo = CodexSessionIndex.loadThreadInfo(
            indexURL: sessionIndexFile,
            stateDatabaseURL: stateDatabaseFile
        )

        var sessions: [String: MutableSession] = [:]
        var daily: [String: MutableDay] = [:]
        var modelSessions: [String: Set<String>] = [:]
        var modelUsage: [String: TokenUsage] = [:]
        var totalUsage = TokenUsage.zero

        for url in sessionFiles() {
            processSessionFile(
                at: url,
                threadInfo: threadInfo,
                sessions: &sessions,
                daily: &daily,
                modelSessions: &modelSessions,
                modelUsage: &modelUsage,
                totalUsage: &totalUsage
            )
        }

        let todayKey = dayKey(for: now)
        let sevenDayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
        let thirtyDayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)

        let dailyUsage = daily
            .map { key, value in
                DailyUsage(
                    dateKey: key,
                    date: value.date,
                    usage: value.usage,
                    sessionCount: value.sessions.count,
                    completionCount: value.completionCount
                )
            }
            .sorted { $0.date < $1.date }

        let todayUsage = daily[todayKey]?.usage ?? .zero
        let last7 = dailyUsage
            .filter { $0.date >= sevenDayStart }
            .reduce(TokenUsage.zero) { $0 + $1.usage }
        let last30 = dailyUsage
            .filter { $0.date >= thirtyDayStart }
            .reduce(TokenUsage.zero) { $0 + $1.usage }

        let modelRows = modelUsage
            .map { model, usage in
                ModelUsage(
                    model: model,
                    usage: usage,
                    sessionCount: modelSessions[model]?.count ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.usage.total == rhs.usage.total {
                    return lhs.model < rhs.model
                }
                return lhs.usage.total > rhs.usage.total
            }

        let sessionRows = sessions.values
            .map { session in
                SessionUsage(
                    id: session.id,
                    title: session.title ?? threadInfo[session.id]?.title ?? "Untitled session",
                    model: normalizedModel(session.model ?? threadInfo[session.id]?.model ?? session.provider),
                    cwd: session.cwd,
                    startedAt: session.startedAt,
                    updatedAt: session.updatedAt,
                    usage: session.usage,
                    eventCount: session.eventCount,
                    completionCount: session.completionCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.usage.total == rhs.usage.total {
                    return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
                }
                return lhs.usage.total > rhs.usage.total
            }

        let completionCount = sessionRows.reduce(0) { $0 + $1.completionCount }

        return UsageReport(
            generatedAt: now,
            totalUsage: totalUsage,
            todayUsage: todayUsage,
            last7DaysUsage: last7,
            last30DaysUsage: last30,
            dailyUsage: dailyUsage,
            modelUsage: modelRows,
            sessions: sessionRows,
            sessionCount: sessionRows.count,
            completionCount: completionCount
        )
    }

    private func processSessionFile(
        at url: URL,
        threadInfo: [String: CodexSessionIndex.ThreadInfo],
        sessions: inout [String: MutableSession],
        daily: inout [String: MutableDay],
        modelSessions: inout [String: Set<String>],
        modelUsage: inout [String: TokenUsage],
        totalUsage: inout TokenUsage
    ) {
        let fallbackID = CodexCompletionParser.threadID(from: url.path) ?? url.deletingPathExtension().lastPathComponent
        var session = sessions[fallbackID] ?? MutableSession(
            id: fallbackID,
            title: threadInfo[fallbackID]?.title,
            model: threadInfo[fallbackID]?.model
        )

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }

        defer {
            try? handle.close()
        }

        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }

            if object["type"] as? String == "session_meta",
               let payload = object["payload"] as? [String: Any] {
                if let id = payload["id"] as? String, id.lowercased() != session.id {
                    sessions[session.id] = session
                    let normalizedID = id.lowercased()
                    session = sessions[normalizedID] ?? MutableSession(
                        id: normalizedID,
                        title: threadInfo[normalizedID]?.title,
                        model: threadInfo[normalizedID]?.model
                    )
                }

                session.startedAt = parseDate(payload["timestamp"] as? String)
                    ?? parseDate(object["timestamp"] as? String)
                    ?? session.startedAt
                session.updatedAt = session.startedAt ?? session.updatedAt
                session.cwd = payload["cwd"] as? String ?? session.cwd
                session.provider = payload["model_provider"] as? String ?? session.provider
                session.model = (payload["model"] as? String) ?? session.model
                session.title = threadInfo[session.id]?.title ?? session.title
                continue
            }

            if let payload = object["payload"] as? [String: Any],
               object["type"] as? String == "response_item",
               payload["type"] as? String == "message",
               payload["role"] as? String == "assistant",
               payload["phase"] as? String == "final_answer" {
                session.completionCount += 1
                session.updatedAt = parseDate(object["timestamp"] as? String) ?? session.updatedAt
                let key = dayKey(for: session.updatedAt ?? Date())
                ensureDay(key, at: session.updatedAt ?? Date(), daily: &daily)
                daily[key]?.completionCount += 1
                daily[key]?.sessions.insert(session.id)
                continue
            }

            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usageObject = info["last_token_usage"] as? [String: Any]
            else {
                continue
            }

            let usage = tokenUsage(from: usageObject)
            guard usage.total > 0 else {
                continue
            }

            let timestamp = parseDate(object["timestamp"] as? String) ?? Date()
            let day = dayKey(for: timestamp)
            let model = normalizedModel(session.model ?? threadInfo[session.id]?.model ?? session.provider)

            session.usage.add(usage)
            session.eventCount += 1
            session.updatedAt = timestamp

            ensureDay(day, at: timestamp, daily: &daily)
            daily[day]?.usage.add(usage)
            daily[day]?.sessions.insert(session.id)

            totalUsage.add(usage)
            modelUsage[model, default: .zero].add(usage)
            modelSessions[model, default: []].insert(session.id)
        }

        sessions[session.id] = session
    }

    private func sessionFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.path < $1.path }
    }

    private func ensureDay(_ key: String, at timestamp: Date, daily: inout [String: MutableDay]) {
        if daily[key] == nil {
            daily[key] = MutableDay(date: calendar.startOfDay(for: timestamp))
        }
    }

    private func tokenUsage(from object: [String: Any]) -> TokenUsage {
        TokenUsage(
            input: intValue(object["input_tokens"]),
            cachedInput: intValue(object["cached_input_tokens"]),
            output: intValue(object["output_tokens"]),
            reasoning: intValue(object["reasoning_output_tokens"]),
            total: intValue(object["total_tokens"])
        )
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string) ?? 0
        }
        return 0
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func normalizedModel(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return "unknown"
        }
        return value
    }
}
