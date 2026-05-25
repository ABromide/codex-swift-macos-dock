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
    public var sessionCount: Int
    public var completionCount: Int

    public init(dateKey: String, date: Date, usage: TokenUsage, sessionCount: Int, completionCount: Int) {
        self.dateKey = dateKey
        self.date = date
        self.usage = usage
        self.sessionCount = sessionCount
        self.completionCount = completionCount
    }
}

public struct ModelUsage: Identifiable, Equatable, Sendable {
    public var id: String { model }
    public var model: String
    public var usage: TokenUsage
    public var sessionCount: Int

    public init(model: String, usage: TokenUsage, sessionCount: Int) {
        self.model = model
        self.usage = usage
        self.sessionCount = sessionCount
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
        self.eventCount = eventCount
        self.completionCount = completionCount
    }
}

public struct UsageReport: Equatable, Sendable {
    public var generatedAt: Date
    public var totalUsage: TokenUsage
    public var todayUsage: TokenUsage
    public var last7DaysUsage: TokenUsage
    public var last30DaysUsage: TokenUsage
    public var dailyUsage: [DailyUsage]
    public var modelUsage: [ModelUsage]
    public var sessions: [SessionUsage]
    public var sessionCount: Int
    public var completionCount: Int

    public init(
        generatedAt: Date,
        totalUsage: TokenUsage,
        todayUsage: TokenUsage,
        last7DaysUsage: TokenUsage,
        last30DaysUsage: TokenUsage,
        dailyUsage: [DailyUsage],
        modelUsage: [ModelUsage],
        sessions: [SessionUsage],
        sessionCount: Int,
        completionCount: Int
    ) {
        self.generatedAt = generatedAt
        self.totalUsage = totalUsage
        self.todayUsage = todayUsage
        self.last7DaysUsage = last7DaysUsage
        self.last30DaysUsage = last30DaysUsage
        self.dailyUsage = dailyUsage
        self.modelUsage = modelUsage
        self.sessions = sessions
        self.sessionCount = sessionCount
        self.completionCount = completionCount
    }

    public static let empty = UsageReport(
        generatedAt: Date(),
        totalUsage: .zero,
        todayUsage: .zero,
        last7DaysUsage: .zero,
        last30DaysUsage: .zero,
        dailyUsage: [],
        modelUsage: [],
        sessions: [],
        sessionCount: 0,
        completionCount: 0
    )
}
