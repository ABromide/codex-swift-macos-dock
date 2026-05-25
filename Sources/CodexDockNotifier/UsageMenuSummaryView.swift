import AppKit
import CodexDockNotifierCore

final class UsageMenuSummaryView: NSView {
    private var report: UsageReport
    private var pendingCount: Int
    private var lastCompletion: CodexCompletion?

    init(report: UsageReport, pendingCount: Int, lastCompletion: CodexCompletion?) {
        self.report = report
        self.pendingCount = pendingCount
        self.lastCompletion = lastCompletion
        super.init(frame: NSRect(x: 0, y: 0, width: 344, height: 196))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(report: UsageReport, pendingCount: Int, lastCompletion: CodexCompletion?) {
        self.report = report
        self.pendingCount = pendingCount
        self.lastCompletion = lastCompletion
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 344, height: 196)
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds.insetBy(dx: 10, dy: 8)
        drawBackground(in: bounds)
        drawHeader(in: bounds)
        drawMetrics(in: bounds)
        drawBars(in: bounds)
        drawFooter(in: bounds)
    }

    private func drawBackground(in rect: NSRect) {
        NSColor(calibratedRed: 0.92, green: 0.98, blue: 1.0, alpha: 1.0).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        NSColor(calibratedRed: 0.70, green: 0.86, blue: 0.91, alpha: 0.45).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()
    }

    private func drawHeader(in rect: NSRect) {
        drawText(
            "Codex 用量概览",
            in: NSRect(x: rect.minX + 12, y: rect.minY + 12, width: 160, height: 18),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .labelColor
        )

        let pending = pendingCount > 0 ? "\(pendingCount) 个未读完成" : "无未读完成"
        drawPill(
            pending,
            in: NSRect(x: rect.maxX - 112, y: rect.minY + 10, width: 98, height: 22),
            active: pendingCount > 0
        )
    }

    private func drawMetrics(in rect: NSRect) {
        let y = rect.minY + 44
        let cardWidth = (rect.width - 44) / 3
        let cards = [
            ("今日", formatCompact(report.todayUsage.total), "\(formatCompact(report.todayUsage.output)) out"),
            ("7 天", formatCompact(report.last7DaysUsage.total), "\(report.sessionCount) sessions"),
            ("30 天", formatCompact(report.last30DaysUsage.total), "\(formatCompact(report.last30DaysUsage.cachedInput)) cached")
        ]

        for (index, card) in cards.enumerated() {
            let x = rect.minX + 12 + CGFloat(index) * (cardWidth + 10)
            let cardRect = NSRect(x: x, y: y, width: cardWidth, height: 52)
            NSColor.white.withAlphaComponent(0.70).setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 6, yRadius: 6).fill()

            drawText(
                card.0,
                in: NSRect(x: cardRect.minX + 8, y: cardRect.minY + 7, width: cardRect.width - 16, height: 13),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: .secondaryLabelColor
            )
            drawText(
                card.1,
                in: NSRect(x: cardRect.minX + 8, y: cardRect.minY + 21, width: cardRect.width - 16, height: 18),
                font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                color: .labelColor
            )
            drawText(
                card.2,
                in: NSRect(x: cardRect.minX + 8, y: cardRect.minY + 39, width: cardRect.width - 16, height: 11),
                font: .systemFont(ofSize: 9),
                color: .tertiaryLabelColor
            )
        }
    }

    private func drawBars(in rect: NSRect) {
        let rows = lastSevenDays()
        let chartRect = NSRect(x: rect.minX + 12, y: rect.minY + 106, width: rect.width - 24, height: 50)
        let maxValue = max(rows.map { $0.usage.total }.max() ?? 1, 1)
        let gap: CGFloat = 5
        let plotRect = NSRect(x: chartRect.minX + 8, y: chartRect.minY + 21, width: chartRect.width - 16, height: 22)
        let barWidth = max(4, (plotRect.width - CGFloat(rows.count - 1) * gap) / CGFloat(max(rows.count, 1)))

        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 6, yRadius: 6).fill()

        for (index, day) in rows.enumerated() {
            let heightRatio = CGFloat(day.usage.total) / CGFloat(maxValue)
            let height = max(day.usage.total == 0 ? 2 : 5, plotRect.height * heightRatio)
            let x = plotRect.minX + CGFloat(index) * (barWidth + gap)
            let barRect = NSRect(x: x, y: plotRect.maxY - height, width: barWidth, height: height)

            if index == rows.count - 1 {
                NSColor(calibratedRed: 0.05, green: 0.55, blue: 0.86, alpha: 1.0).setFill()
            } else {
                NSColor(calibratedRed: 0.12, green: 0.70, blue: 0.58, alpha: 0.78).setFill()
            }
            NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3).fill()
        }

        drawText(
            "近 7 天 token",
            in: NSRect(x: chartRect.minX + 8, y: chartRect.minY + 7, width: 120, height: 12),
            font: .systemFont(ofSize: 9, weight: .medium),
            color: .secondaryLabelColor
        )
        drawText(
            "峰值 \(formatCompact(maxValue))",
            in: NSRect(x: chartRect.maxX - 88, y: chartRect.minY + 7, width: 80, height: 12),
            font: .systemFont(ofSize: 9),
            color: .tertiaryLabelColor,
            alignment: .right
        )
    }

    private func drawFooter(in rect: NSRect) {
        let model = report.modelUsage.first?.model ?? "unknown"
        let latest = lastCompletion?.threadName ?? "等待 Codex 完成任务"
        let text = "模型 \(model)  ·  最近 \(latest)"
        drawText(
            text,
            in: NSRect(x: rect.minX + 12, y: rect.maxY - 24, width: rect.width - 24, height: 14),
            font: .systemFont(ofSize: 10),
            color: .secondaryLabelColor
        )
    }

    private func drawPill(_ text: String, in rect: NSRect, active: Bool) {
        let fill = active
            ? NSColor(calibratedRed: 0.03, green: 0.46, blue: 0.76, alpha: 1.0)
            : NSColor.white.withAlphaComponent(0.72)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11).fill()

        drawText(
            text,
            in: rect.insetBy(dx: 8, dy: 4),
            font: .systemFont(ofSize: 10, weight: .medium),
            color: active ? .white : .secondaryLabelColor,
            alignment: .center
        )
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func lastSevenDays() -> [DailyUsage] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: report.generatedAt)
        let existing = Dictionary(
            uniqueKeysWithValues: report.dailyUsage.map {
                (calendar.startOfDay(for: $0.date), $0)
            }
        )

        return (0..<7).compactMap { offset -> DailyUsage? in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: end) else {
                return nil
            }
            if let row = existing[date] {
                return row
            }
            return DailyUsage(
                dateKey: "",
                date: date,
                usage: .zero,
                sessionCount: 0,
                completionCount: 0
            )
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
}
