import Foundation

public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int
    public var cachedInput: Int
    public var output: Int
    public var reasoning: Int
    public var total: Int

    public init(input: Int = 0, cachedInput: Int = 0, output: Int = 0, reasoning: Int = 0, total: Int = 0) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.reasoning = reasoning
        self.total = total
    }

    public static let zero = TokenUsage()

    public var billableApproximation: Int {
        max(0, total - cachedInput)
    }

    public mutating func add(_ other: TokenUsage) {
        input += other.input
        cachedInput += other.cachedInput
        output += other.output
        reasoning += other.reasoning
        total += other.total
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        var result = lhs
        result.add(rhs)
        return result
    }
}

public struct DailyUsage: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public var dateKey: String
    public var date: Date
    public var usage: TokenUsage
    public var estimatedCostUSD: Double
    public var sessionCount: Int
    public var completionCount: Int

    public init(
        dateKey: String,
        date: Date,
        usage: TokenUsage,
        estimatedCostUSD: Double = 0,
        sessionCount: Int,
        completionCount: Int
    ) {
        self.dateKey = dateKey
        self.date = date
        self.usage = usage
        self.estimatedCostUSD = estimatedCostUSD
        self.sessionCount = sessionCount
        self.completionCount = completionCount
    }
}

public struct ModelUsage: Identifiable, Equatable, Sendable {
    public var id: String { model }
    public var model: String
    public var usage: TokenUsage
    public var estimatedCostUSD: Double
    public var sessionCount: Int

    public init(model: String, usage: TokenUsage, estimatedCostUSD: Double = 0, sessionCount: Int) {
        self.model = model
        self.usage = usage
        self.estimatedCostUSD = estimatedCostUSD
        self.sessionCount = sessionCount
    }

    public var averageTokensPerSession: Int {
        guard sessionCount > 0 else {
            return 0
        }
        return usage.total / sessionCount
    }

    public var outputRatio: Double {
        guard usage.total > 0 else {
            return 0
        }
        return Double(usage.output + usage.reasoning) / Double(usage.total)
    }

    public var cachedRatio: Double {
        guard usage.input > 0 else {
            return 0
        }
        return Double(usage.cachedInput) / Double(usage.input)
    }
}

public struct ProjectUsage: Identifiable, Equatable, Sendable {
    public var id: String { path.isEmpty ? name : path }
    public var name: String
    public var path: String
    public var usage: TokenUsage
    public var estimatedCostUSD: Double
    public var sessionCount: Int
    public var completionCount: Int

    public init(
        name: String,
        path: String,
        usage: TokenUsage,
        estimatedCostUSD: Double = 0,
        sessionCount: Int,
        completionCount: Int
    ) {
        self.name = name
        self.path = path
        self.usage = usage
        self.estimatedCostUSD = estimatedCostUSD
        self.sessionCount = sessionCount
        self.completionCount = completionCount
    }
}

public struct SessionUsage: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var model: String
    public var cwd: String
    public var startedAt: Date?
    public var updatedAt: Date?
    public var usage: TokenUsage
    public var estimatedCostUSD: Double
    public var eventCount: Int
    public var completionCount: Int

    public init(
        id: String,
        title: String,
        model: String,
        cwd: String,
        startedAt: Date?,
        updatedAt: Date?,
        usage: TokenUsage,
        estimatedCostUSD: Double = 0,
        eventCount: Int,
        completionCount: Int
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.usage = usage
        self.estimatedCostUSD = estimatedCostUSD
        self.eventCount = eventCount
        self.completionCount = completionCount
    }
}

public struct RunningSession: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var model: String
    public var cwd: String
    public var startedAt: Date?
    public var lastActivityAt: Date
    public var runningForSeconds: TimeInterval

    public init(
        id: String,
        title: String,
        model: String,
        cwd: String,
        startedAt: Date?,
        lastActivityAt: Date,
        runningForSeconds: TimeInterval
    ) {
        self.id = id
        self.title = title
        self.model = model
        self.cwd = cwd
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.runningForSeconds = runningForSeconds
    }
}

public struct UsageReport: Equatable, Sendable {
    public var generatedAt: Date
    public var totalUsage: TokenUsage
    public var totalEstimatedCostUSD: Double
    public var todayUsage: TokenUsage
    public var todayEstimatedCostUSD: Double
    public var last7DaysUsage: TokenUsage
    public var last7DaysEstimatedCostUSD: Double
    public var last30DaysUsage: TokenUsage
    public var last30DaysEstimatedCostUSD: Double
    public var dailyUsage: [DailyUsage]
    public var modelUsage: [ModelUsage]
    public var projectUsage: [ProjectUsage]
    public var sessions: [SessionUsage]
    public var runningSessions: [RunningSession]
    public var sessionCount: Int
    public var completionCount: Int

    public init(
        generatedAt: Date,
        totalUsage: TokenUsage,
        totalEstimatedCostUSD: Double = 0,
        todayUsage: TokenUsage,
        todayEstimatedCostUSD: Double = 0,
        last7DaysUsage: TokenUsage,
        last7DaysEstimatedCostUSD: Double = 0,
        last30DaysUsage: TokenUsage,
        last30DaysEstimatedCostUSD: Double = 0,
        dailyUsage: [DailyUsage],
        modelUsage: [ModelUsage],
        projectUsage: [ProjectUsage] = [],
        sessions: [SessionUsage],
        runningSessions: [RunningSession] = [],
        sessionCount: Int,
        completionCount: Int
    ) {
        self.generatedAt = generatedAt
        self.totalUsage = totalUsage
        self.totalEstimatedCostUSD = totalEstimatedCostUSD
        self.todayUsage = todayUsage
        self.todayEstimatedCostUSD = todayEstimatedCostUSD
        self.last7DaysUsage = last7DaysUsage
        self.last7DaysEstimatedCostUSD = last7DaysEstimatedCostUSD
        self.last30DaysUsage = last30DaysUsage
        self.last30DaysEstimatedCostUSD = last30DaysEstimatedCostUSD
        self.dailyUsage = dailyUsage
        self.modelUsage = modelUsage
        self.projectUsage = projectUsage
        self.sessions = sessions
        self.runningSessions = runningSessions
        self.sessionCount = sessionCount
        self.completionCount = completionCount
    }

    public static let empty = UsageReport(
        generatedAt: Date(),
        totalUsage: .zero,
        totalEstimatedCostUSD: 0,
        todayUsage: .zero,
        todayEstimatedCostUSD: 0,
        last7DaysUsage: .zero,
        last7DaysEstimatedCostUSD: 0,
        last30DaysUsage: .zero,
        last30DaysEstimatedCostUSD: 0,
        dailyUsage: [],
        modelUsage: [],
        projectUsage: [],
        sessions: [],
        runningSessions: [],
        sessionCount: 0,
        completionCount: 0
    )
}
