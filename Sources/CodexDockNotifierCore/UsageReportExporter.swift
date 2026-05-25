import Foundation

public enum UsageReportExporter {
    public static func markdown(report: UsageReport) -> String {
        var lines: [String] = []
        lines.append("# Codex 使用量报告")
        lines.append("")
        lines.append("- 生成时间：\(formatDateTime(report.generatedAt))")
        lines.append("- 总 Token：\(report.totalUsage.total)")
        lines.append("- 估算成本：\(formatCurrency(report.totalEstimatedCostUSD))")
        lines.append("- 今天：\(report.todayUsage.total) token，\(formatCurrency(report.todayEstimatedCostUSD))")
        lines.append("- 近 7 天：\(report.last7DaysUsage.total) token，\(formatCurrency(report.last7DaysEstimatedCostUSD))")
        lines.append("- 近 30 天：\(report.last30DaysUsage.total) token，\(formatCurrency(report.last30DaysEstimatedCostUSD))")
        lines.append("- Sessions：\(report.sessionCount)")
        lines.append("- 完成次数：\(report.completionCount)")
        lines.append("")
        lines.append("> 成本为估算值。\(UsageCostEstimator.pricingSource)。")
        lines.append("")
        lines.append("## 模型用量")
        lines.append("")
        lines.append("| 模型 | Token | 成本 | Sessions | 平均 Token/Session | 输出占比 | 缓存占比 |")
        lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
        for row in report.modelUsage {
            lines.append("| \(escapeMarkdown(row.model)) | \(row.usage.total) | \(formatCurrency(row.estimatedCostUSD)) | \(row.sessionCount) | \(row.averageTokensPerSession) | \(formatPercent(row.outputRatio)) | \(formatPercent(row.cachedRatio)) |")
        }
        lines.append("")
        lines.append("## 项目用量")
        lines.append("")
        lines.append("| 项目 | 路径 | Token | 成本 | Sessions | 完成 |")
        lines.append("| --- | --- | ---: | ---: | ---: | ---: |")
        for row in report.projectUsage {
            lines.append("| \(escapeMarkdown(row.name)) | \(escapeMarkdown(row.path)) | \(row.usage.total) | \(formatCurrency(row.estimatedCostUSD)) | \(row.sessionCount) | \(row.completionCount) |")
        }
        lines.append("")
        lines.append("## Session 排行")
        lines.append("")
        lines.append("| 标题 | 模型 | 项目 | Token | 成本 | 完成 |")
        lines.append("| --- | --- | --- | ---: | ---: | ---: |")
        for row in report.sessions.prefix(50) {
            lines.append("| \(escapeMarkdown(row.title)) | \(escapeMarkdown(row.model)) | \(escapeMarkdown(row.cwd)) | \(row.usage.total) | \(formatCurrency(row.estimatedCostUSD)) | \(row.completionCount) |")
        }
        lines.append("")
        lines.append("## 每日用量")
        lines.append("")
        lines.append("| 日期 | Token | 成本 | Sessions | 完成 |")
        lines.append("| --- | ---: | ---: | ---: | ---: |")
        for row in report.dailyUsage.reversed() {
            lines.append("| \(row.dateKey) | \(row.usage.total) | \(formatCurrency(row.estimatedCostUSD)) | \(row.sessionCount) | \(row.completionCount) |")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func sessionsCSV(report: UsageReport) -> String {
        var rows = [
            [
                "id",
                "title",
                "model",
                "cwd",
                "started_at",
                "updated_at",
                "input",
                "cached_input",
                "output",
                "reasoning",
                "total",
                "estimated_cost_usd",
                "events",
                "completions"
            ]
        ]

        rows += report.sessions.map { session in
            [
                session.id,
                session.title,
                session.model,
                session.cwd,
                session.startedAt.map(formatDateTime) ?? "",
                session.updatedAt.map(formatDateTime) ?? "",
                "\(session.usage.input)",
                "\(session.usage.cachedInput)",
                "\(session.usage.output)",
                "\(session.usage.reasoning)",
                "\(session.usage.total)",
                String(format: "%.6f", session.estimatedCostUSD),
                "\(session.eventCount)",
                "\(session.completionCount)"
            ]
        }

        return csv(rows)
    }

    public static func dailyCSV(report: UsageReport) -> String {
        var rows = [
            [
                "date",
                "input",
                "cached_input",
                "output",
                "reasoning",
                "total",
                "estimated_cost_usd",
                "sessions",
                "completions"
            ]
        ]

        rows += report.dailyUsage.map { day in
            [
                day.dateKey,
                "\(day.usage.input)",
                "\(day.usage.cachedInput)",
                "\(day.usage.output)",
                "\(day.usage.reasoning)",
                "\(day.usage.total)",
                String(format: "%.6f", day.estimatedCostUSD),
                "\(day.sessionCount)",
                "\(day.completionCount)"
            ]
        }

        return csv(rows)
    }

    private static func csv(_ rows: [[String]]) -> String {
        rows
            .map { row in row.map(escapeCSV).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func escapeMarkdown(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }

    private static func formatDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func formatCurrency(_ value: Double) -> String {
        "$" + String(format: "%.4f", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
