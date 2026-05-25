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
        var estimatedCostUSD: Double = 0
        var eventCount = 0
        var completionCount = 0
        var lastUserMessageAt: Date?
        var lastTokenAt: Date?
        var lastFinalAnswerAt: Date?
        var latestEventAt: Date?
    }

    private struct MutableDay {
        var date: Date
        var usage: TokenUsage = .zero
        var estimatedCostUSD: Double = 0
        var sessions: Set<String> = []
        var completionCount = 0
    }

    private struct MutableProject {
        var name: String
        var path: String
        var usage: TokenUsage = .zero
        var estimatedCostUSD: Double = 0
        var sessions: Set<String> = []
        var completionCount = 0
    }

    private let sessionsDirectory: URL
    private let sessionIndexFile: URL
    private let stateDatabaseFile: URL
    private let calendar: Calendar
    private let activeSessionMaxIdle: TimeInterval = 5 * 60

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
        var modelCosts: [String: Double] = [:]
        var projectUsage: [String: MutableProject] = [:]
        var totalUsage = TokenUsage.zero
        var totalEstimatedCostUSD: Double = 0

        for url in sessionFiles() {
            processSessionFile(
                at: url,
                threadInfo: threadInfo,
                sessions: &sessions,
                daily: &daily,
                modelSessions: &modelSessions,
                modelUsage: &modelUsage,
                modelCosts: &modelCosts,
                projectUsage: &projectUsage,
                totalUsage: &totalUsage,
                totalEstimatedCostUSD: &totalEstimatedCostUSD
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
                    estimatedCostUSD: value.estimatedCostUSD,
                    sessionCount: value.sessions.count,
                    completionCount: value.completionCount
                )
            }
            .sorted { $0.date < $1.date }

        let todayUsage = daily[todayKey]?.usage ?? .zero
        let last7 = dailyUsage
            .filter { $0.date >= sevenDayStart }
            .reduce(TokenUsage.zero) { $0 + $1.usage }
        let last7Cost = dailyUsage
            .filter { $0.date >= sevenDayStart }
            .reduce(0.0) { $0 + $1.estimatedCostUSD }
        let last30 = dailyUsage
            .filter { $0.date >= thirtyDayStart }
            .reduce(TokenUsage.zero) { $0 + $1.usage }
        let last30Cost = dailyUsage
            .filter { $0.date >= thirtyDayStart }
            .reduce(0.0) { $0 + $1.estimatedCostUSD }

        let modelRows = modelUsage
            .map { model, usage in
                ModelUsage(
                    model: model,
                    usage: usage,
                    estimatedCostUSD: modelCosts[model] ?? 0,
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
                    estimatedCostUSD: session.estimatedCostUSD,
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
        let projectRows = projectUsage.values
            .map { project in
                ProjectUsage(
                    name: project.name,
                    path: project.path,
                    usage: project.usage,
                    estimatedCostUSD: project.estimatedCostUSD,
                    sessionCount: project.sessions.count,
                    completionCount: project.completionCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.usage.total == rhs.usage.total {
                    return lhs.name < rhs.name
                }
                return lhs.usage.total > rhs.usage.total
            }

        let runningRows = sessions.values
            .compactMap { runningSession(from: $0, threadInfo: threadInfo, now: now) }
            .sorted { lhs, rhs in
                lhs.lastActivityAt > rhs.lastActivityAt
            }

        return UsageReport(
            generatedAt: now,
            totalUsage: totalUsage,
            totalEstimatedCostUSD: totalEstimatedCostUSD,
            todayUsage: todayUsage,
            todayEstimatedCostUSD: daily[todayKey]?.estimatedCostUSD ?? 0,
            last7DaysUsage: last7,
            last7DaysEstimatedCostUSD: last7Cost,
            last30DaysUsage: last30,
            last30DaysEstimatedCostUSD: last30Cost,
            dailyUsage: dailyUsage,
            modelUsage: modelRows,
            projectUsage: projectRows,
            sessions: sessionRows,
            runningSessions: runningRows,
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
        modelCosts: inout [String: Double],
        projectUsage: inout [String: MutableProject],
        totalUsage: inout TokenUsage,
        totalEstimatedCostUSD: inout Double
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

            let eventTimestamp = parseDate(object["timestamp"] as? String)
            if let eventTimestamp {
                session.latestEventAt = latestDate(session.latestEventAt, eventTimestamp)
                session.updatedAt = latestDate(session.updatedAt, eventTimestamp)
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
                session.latestEventAt = latestDate(session.latestEventAt, session.startedAt)
                session.cwd = payload["cwd"] as? String ?? session.cwd
                session.provider = payload["model_provider"] as? String ?? session.provider
                session.model = (payload["model"] as? String) ?? session.model
                session.title = threadInfo[session.id]?.title ?? session.title
                continue
            }

            if let payload = object["payload"] as? [String: Any],
               object["type"] as? String == "response_item",
               payload["type"] as? String == "message",
               payload["role"] as? String == "user" {
                session.lastUserMessageAt = eventTimestamp ?? session.updatedAt ?? session.lastUserMessageAt
                continue
            }

            if let payload = object["payload"] as? [String: Any],
               object["type"] as? String == "response_item",
               payload["type"] as? String == "message",
               payload["role"] as? String == "assistant",
               payload["phase"] as? String == "final_answer" {
                session.completionCount += 1
                session.updatedAt = eventTimestamp ?? session.updatedAt
                session.lastFinalAnswerAt = eventTimestamp ?? session.updatedAt ?? session.lastFinalAnswerAt
                let key = dayKey(for: session.updatedAt ?? Date())
                ensureDay(key, at: session.updatedAt ?? Date(), daily: &daily)
                daily[key]?.completionCount += 1
                daily[key]?.sessions.insert(session.id)
                let projectKey = normalizedProjectPath(session.cwd)
                ensureProject(projectKey, projects: &projectUsage)
                projectUsage[projectKey]?.completionCount += 1
                projectUsage[projectKey]?.sessions.insert(session.id)
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

            let timestamp = eventTimestamp ?? Date()
            let day = dayKey(for: timestamp)
            let model = normalizedModel(session.model ?? threadInfo[session.id]?.model ?? session.provider)
            let cost = UsageCostEstimator.estimateUSD(for: usage, model: model)

            session.usage.add(usage)
            session.estimatedCostUSD += cost
            session.eventCount += 1
            session.updatedAt = timestamp
            session.lastTokenAt = timestamp

            ensureDay(day, at: timestamp, daily: &daily)
            daily[day]?.usage.add(usage)
            daily[day]?.estimatedCostUSD += cost
            daily[day]?.sessions.insert(session.id)

            totalUsage.add(usage)
            totalEstimatedCostUSD += cost
            modelUsage[model, default: .zero].add(usage)
            modelCosts[model, default: 0] += cost
            modelSessions[model, default: []].insert(session.id)

            let projectKey = normalizedProjectPath(session.cwd)
            ensureProject(projectKey, projects: &projectUsage)
            projectUsage[projectKey]?.usage.add(usage)
            projectUsage[projectKey]?.estimatedCostUSD += cost
            projectUsage[projectKey]?.sessions.insert(session.id)
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

    private func ensureProject(_ path: String, projects: inout [String: MutableProject]) {
        guard projects[path] == nil else {
            return
        }

        projects[path] = MutableProject(
            name: projectName(for: path),
            path: path
        )
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

    private func runningSession(
        from session: MutableSession,
        threadInfo: [String: CodexSessionIndex.ThreadInfo],
        now: Date
    ) -> RunningSession? {
        let startMarker = latestDate(session.lastUserMessageAt, session.lastTokenAt)
        let lastFinal = session.lastFinalAnswerAt ?? .distantPast
        guard let marker = startMarker,
              marker > lastFinal
        else {
            return nil
        }

        let lastActivityAt = session.latestEventAt ?? marker
        guard now.timeIntervalSince(lastActivityAt) <= activeSessionMaxIdle else {
            return nil
        }

        return RunningSession(
            id: session.id,
            title: session.title ?? threadInfo[session.id]?.title ?? "Untitled session",
            model: normalizedModel(session.model ?? threadInfo[session.id]?.model ?? session.provider),
            cwd: session.cwd,
            startedAt: session.lastUserMessageAt ?? session.startedAt,
            lastActivityAt: lastActivityAt,
            runningForSeconds: max(0, now.timeIntervalSince(session.lastUserMessageAt ?? marker))
        )
    }

    private func latestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func normalizedProjectPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private func projectName(for path: String) -> String {
        guard path != "unknown" else {
            return "未知项目"
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
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
