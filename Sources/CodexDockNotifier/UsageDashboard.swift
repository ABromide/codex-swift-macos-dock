import AppKit
import Charts
import CodexDockNotifierCore
import SwiftUI

@MainActor
final class UsageDashboardWindowController: NSWindowController {
    private let viewModel = UsageDashboardViewModel()

    init() {
        let rootView = UsageDashboardView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex 使用量统计"
        window.minSize = NSSize(width: 860, height: 620)
        window.contentView = hostingView

        super.init(window: window)

        window.center()
        viewModel.refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class UsageDashboardViewModel: ObservableObject {
    @Published var report: UsageReport = .empty
    @Published var lastUpdatedText = "未刷新"
    @Published var exportStatusText = ""

    private let analyzer = UsageStatsAnalyzer()

    func refresh() {
        report = analyzer.buildReport()
        lastUpdatedText = Self.dateTimeFormatter.string(from: report.generatedAt)
    }

    func exportMarkdown() {
        saveFile(
            defaultName: "codex-usage-report.md",
            content: UsageReportExporter.markdown(report: report)
        )
    }

    func exportSessionsCSV() {
        saveFile(
            defaultName: "codex-sessions.csv",
            content: UsageReportExporter.sessionsCSV(report: report)
        )
    }

    func exportDailyCSV() {
        saveFile(
            defaultName: "codex-daily-usage.csv",
            content: UsageReportExporter.dailyCSV(report: report)
        )
    }

    private func saveFile(defaultName: String, content: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            exportStatusText = "已导出 \(url.lastPathComponent)"
        } catch {
            exportStatusText = "导出失败：\(error.localizedDescription)"
        }
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private enum UsageRange: String, CaseIterable, Identifiable {
    case days7 = "7 天"
    case days30 = "30 天"
    case all = "全部"

    var id: String { rawValue }

    var dayCount: Int? {
        switch self {
        case .days7:
            return 7
        case .days30:
            return 30
        case .all:
            return nil
        }
    }
}

struct UsageDashboardView: View {
    @ObservedObject var viewModel: UsageDashboardViewModel
    @State private var range: UsageRange = .days30

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    kpiGrid

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 440), spacing: 16),
                        GridItem(.flexible(minimum: 340), spacing: 16)
                    ], spacing: 16) {
                        chartCard(title: "按天 Token", subtitle: "输入、缓存输入、输出和 reasoning 的堆叠柱状图") {
                            DailyStackedBarChart(rows: rangedDailyRows)
                                .frame(height: 260)
                        }

                        chartCard(title: "累计趋势", subtitle: "所选时间范围内的累计 token 走势") {
                            CumulativeLineChart(rows: cumulativeRows)
                                .frame(height: 260)
                        }
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 420), spacing: 16),
                        GridItem(.flexible(minimum: 420), spacing: 16)
                    ], spacing: 16) {
                        chartCard(title: "模型用量", subtitle: "按总 token 排序") {
                            ModelUsageBarChart(rows: Array(viewModel.report.modelUsage.prefix(8)))
                                .frame(height: 260)
                        }

                        sessionTable
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 420), spacing: 16),
                        GridItem(.flexible(minimum: 420), spacing: 16)
                    ], spacing: 16) {
                        chartCard(title: "项目用量", subtitle: "按 cwd 聚合，方便定位最耗 token 的项目") {
                            ProjectUsageBarChart(rows: Array(viewModel.report.projectUsage.prefix(8)))
                                .frame(height: 260)
                        }

                        modelAnalysisTable
                    }
                }
                .padding(18)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex 使用量统计")
                    .font(.system(size: 22, weight: .semibold))
                Text("更新于 \(viewModel.lastUpdatedText)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("范围", selection: $range) {
                ForEach(UsageRange.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Menu {
                Button {
                    viewModel.exportMarkdown()
                } label: {
                    Label("Markdown 报告", systemImage: "doc.text")
                }

                Button {
                    viewModel.exportSessionsCSV()
                } label: {
                    Label("Session CSV", systemImage: "tablecells")
                }

                Button {
                    viewModel.exportDailyCSV()
                } label: {
                    Label("Daily CSV", systemImage: "calendar")
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.down")
            }

            Button("刷新") {
                viewModel.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(18)
    }

    private var kpiGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 12)
            ], spacing: 12) {
            KPIBox(title: "全部 Token", value: formatCompact(viewModel.report.totalUsage.total), caption: "近似计费 \(formatCompact(viewModel.report.totalUsage.billableApproximation))")
            KPIBox(title: "今天", value: formatCompact(viewModel.report.todayUsage.total), caption: "\(formatCompact(viewModel.report.todayUsage.output)) output")
            KPIBox(title: "7 天", value: formatCompact(viewModel.report.last7DaysUsage.total), caption: "\(formatCompact(viewModel.report.last7DaysUsage.reasoning)) reasoning")
            KPIBox(title: "30 天", value: formatCompact(viewModel.report.last30DaysUsage.total), caption: "\(formatCompact(viewModel.report.last30DaysUsage.cachedInput)) cached")
                KPIBox(title: "成本估算", value: formatCurrency(viewModel.report.totalEstimatedCostUSD), caption: "30 天 \(formatCurrency(viewModel.report.last30DaysEstimatedCostUSD))")
            KPIBox(title: "Sessions", value: "\(viewModel.report.sessionCount)", caption: "\(viewModel.report.completionCount) 次完成")
            }

            if !viewModel.exportStatusText.isEmpty {
                Text(viewModel.exportStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionTable: some View {
        chartCard(title: "Session 排行", subtitle: "按 token 总量排序") {
            VStack(spacing: 0) {
                HStack {
                    Text("标题").frame(maxWidth: .infinity, alignment: .leading)
                    Text("模型").frame(width: 120, alignment: .leading)
                    Text("成本").frame(width: 74, alignment: .trailing)
                    Text("Token").frame(width: 92, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

                ForEach(Array(viewModel.report.sessions.prefix(8))) { session in
                    Divider()
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(session.cwd)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(session.model)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(formatCurrency(session.estimatedCostUSD))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .trailing)

                        Text(formatCompact(session.usage.total))
                            .monospacedDigit()
                            .frame(width: 92, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(height: 260, alignment: .top)
        }
    }

    private var modelAnalysisTable: some View {
        chartCard(title: "模型切换分析", subtitle: "看不同模型的平均消耗、输出占比和缓存命中") {
            VStack(spacing: 0) {
                HStack {
                    Text("模型").frame(maxWidth: .infinity, alignment: .leading)
                    Text("均值").frame(width: 72, alignment: .trailing)
                    Text("输出").frame(width: 56, alignment: .trailing)
                    Text("缓存").frame(width: 56, alignment: .trailing)
                    Text("成本").frame(width: 74, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

                ForEach(Array(viewModel.report.modelUsage.prefix(8))) { model in
                    Divider()
                    HStack(spacing: 10) {
                        Text(model.model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatCompact(model.averageTokensPerSession))
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)

                        Text(formatPercent(model.outputRatio))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)

                        Text(formatPercent(model.cachedRatio))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)

                        Text(formatCurrency(model.estimatedCostUSD))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 74, alignment: .trailing)
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(height: 260, alignment: .top)
        }
    }

    private var rangedDailyRows: [DailyUsage] {
        guard let dayCount = range.dayCount else {
            return viewModel.report.dailyUsage
        }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: viewModel.report.generatedAt)
        let existing = Dictionary(
            uniqueKeysWithValues: viewModel.report.dailyUsage.map {
                (calendar.startOfDay(for: $0.date), $0)
            }
        )

        return (0..<dayCount).compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: offset - dayCount + 1, to: end) else {
                return nil
            }
            if let row = existing[date] {
                return row
            }
            return DailyUsage(
                dateKey: Self.dayKey(for: date, calendar: calendar),
                date: date,
                usage: .zero,
                sessionCount: 0,
                completionCount: 0
            )
        }
    }

    private var cumulativeRows: [CumulativePoint] {
        var running = 0
        return rangedDailyRows.map { day in
            running += day.usage.total
            return CumulativePoint(date: day.date, total: running)
        }
    }

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct KPIBox: View {
    var title: String
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DailyTokenSegment: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(category)" }
    var date: Date
    var category: String
    var value: Int
}

private struct CumulativePoint: Identifiable {
    var id: Date { date }
    var date: Date
    var total: Int
}

private struct DailyStackedBarChart: View {
    var rows: [DailyUsage]

    var segments: [DailyTokenSegment] {
        rows.flatMap { row in
            [
                DailyTokenSegment(date: row.date, category: "input", value: max(0, row.usage.input - row.usage.cachedInput)),
                DailyTokenSegment(date: row.date, category: "cached", value: row.usage.cachedInput),
                DailyTokenSegment(date: row.date, category: "output", value: row.usage.output),
                DailyTokenSegment(date: row.date, category: "reasoning", value: row.usage.reasoning)
            ]
        }
    }

    var body: some View {
        if rows.isEmpty {
            EmptyStateView(text: "还没有 usage 数据")
        } else {
            Chart(segments) { segment in
                BarMark(
                    x: .value("日期", segment.date, unit: .day),
                    y: .value("Token", segment.value)
                )
                .foregroundStyle(by: .value("类型", segment.category))
            }
            .chartForegroundStyleScale([
                "input": Color.blue,
                "cached": Color.teal,
                "output": Color.green,
                "reasoning": Color.orange
            ])
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let int = value.as(Int.self) {
                            Text(formatCompact(int))
                        }
                    }
                }
            }
        }
    }
}

private struct CumulativeLineChart: View {
    var rows: [CumulativePoint]

    var body: some View {
        if rows.isEmpty {
            EmptyStateView(text: "还没有趋势数据")
        } else {
            Chart(rows) { row in
                LineMark(
                    x: .value("日期", row.date, unit: .day),
                    y: .value("Token", row.total)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.indigo)

                AreaMark(
                    x: .value("日期", row.date, unit: .day),
                    y: .value("Token", row.total)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.indigo.opacity(0.16))
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let int = value.as(Int.self) {
                            Text(formatCompact(int))
                        }
                    }
                }
            }
        }
    }
}

private struct ModelUsageBarChart: View {
    var rows: [ModelUsage]

    var body: some View {
        if rows.isEmpty {
            EmptyStateView(text: "还没有模型用量数据")
        } else {
            Chart(rows) { row in
                BarMark(
                    x: .value("Token", row.usage.total),
                    y: .value("模型", row.model)
                )
                .foregroundStyle(Color.cyan)
                .annotation(position: .trailing) {
                    Text(formatCompact(row.usage.total))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let int = value.as(Int.self) {
                            Text(formatCompact(int))
                        }
                    }
                }
            }
        }
    }
}

private struct ProjectUsageBarChart: View {
    var rows: [ProjectUsage]

    var body: some View {
        if rows.isEmpty {
            EmptyStateView(text: "还没有项目用量数据")
        } else {
            Chart(rows) { row in
                BarMark(
                    x: .value("Token", row.usage.total),
                    y: .value("项目", row.name)
                )
                .foregroundStyle(Color.green)
                .annotation(position: .trailing) {
                    Text(formatCompact(row.usage.total))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let int = value.as(Int.self) {
                            Text(formatCompact(int))
                        }
                    }
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    var text: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

private func formatCompact(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fK", Double(value) / 1_000)
    }
    return "\(value)"
}

private func formatCurrency(_ value: Double) -> String {
    if value >= 1_000 {
        return "$" + String(format: "%.1fK", value / 1_000)
    }
    if value >= 10 {
        return "$" + String(format: "%.2f", value)
    }
    return "$" + String(format: "%.4f", value)
}

private func formatPercent(_ value: Double) -> String {
    String(format: "%.0f%%", value * 100)
}
