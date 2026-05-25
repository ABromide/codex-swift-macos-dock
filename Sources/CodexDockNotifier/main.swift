import AppKit
import CodexDockNotifierCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: CodexMonitor?
    private var usageWindowController: UsageDashboardWindowController?
    private var historyWindowController: CompletionHistoryWindowController?
    private let usageAnalyzer = UsageStatsAnalyzer()
    private weak var usageSummaryView: UsageMenuSummaryView?
    private var pendingCount = 0
    private var lastCompletion: CodexCompletion?
    private var completionHistory: [CodexCompletion] = []
    private var runningSessions: [RunningSession] = []
    private var activityTimer: Timer?
    private var longTaskReminderKeys: Set<String> = []
    private let longTaskReminderThreshold: TimeInterval = 10 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        configureApplicationIcon()
        configureStatusItem()
        configureNotifications()

        monitor = CodexMonitor { [weak self] completion in
            DispatchQueue.main.async {
                self?.handleCompletion(completion)
            }
        }
        completionHistory = monitor?.completionHistory() ?? []
        monitor?.start()
        refreshActivityStatus()
        startActivityTimer()
        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        activityTimer?.invalidate()
        activityTimer = nil
        monitor?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openCodex()
        return false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let threadID = userInfo["threadID"] as? String
        let filePath = userInfo["filePath"] as? String
        let lineOffset = userInfo["lineOffset"] as? String

        await MainActor.run {
            self.markAllRead()
            self.openCodex(threadID: threadID, filePath: filePath, lineOffset: lineOffset)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Codex"
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "Codex Dock Notifier"
        statusItem = item
        updateStatusItem()
    }

    private func configureApplicationIcon() {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)

        image.lockFocus()
        defer {
            image.unlockFocus()
        }

        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1.0).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 24, y: 24, width: 464, height: 464),
            xRadius: 92,
            yRadius: 92
        ).fill()

        NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.58, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: NSRect(x: 350, y: 342, width: 78, height: 78)).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 248, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        NSString(string: "C").draw(
            in: NSRect(x: 0, y: 116, width: size.width, height: 280),
            withAttributes: attributes
        )

        NSApp.applicationIconImage = image
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("CodexDockNotifier notification authorization failed: \(error)")
            }
            if !granted {
                NSLog("CodexDockNotifier notification authorization was not granted.")
            }
        }
    }

    private func handleCompletion(_ completion: CodexCompletion) {
        pendingCount += 1
        lastCompletion = completion
        recordCompletionInHistory(completion)

        NSApp.requestUserAttention(.informationalRequest)
        updateDockBadge()
        refreshActivityStatus(sendReminders: false)
        updateMenu()
        postNotification(for: completion)
    }

    private func postNotification(for completion: CodexCompletion) {
        let content = UNMutableNotificationContent()
        content.title = "Codex 任务完成"
        content.subtitle = completion.threadName ?? "Codex"
        content.body = completion.notificationBody
        content.sound = .default
        content.badge = NSNumber(value: pendingCount)
        content.userInfo = [
            "threadID": completion.threadID ?? "",
            "filePath": completion.filePath,
            "lineOffset": String(completion.lineOffset)
        ]

        let request = UNNotificationRequest(
            identifier: completion.key,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("CodexDockNotifier failed to post notification: \(error)")
            }
        }
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = pendingCount > 0 ? "\(pendingCount)" : nil
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName: String
        if pendingCount > 0 {
            symbolName = "bell.badge.fill"
        } else if !runningSessions.isEmpty {
            symbolName = "play.circle.fill"
        } else {
            symbolName = "checkmark.circle"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = pendingCount > 0
            ? "Codex \(pendingCount)"
            : (runningSessions.isEmpty ? "Codex" : "Codex \(runningSessions.count)")

        if pendingCount > 0 {
            button.toolTip = "\(pendingCount) 个 Codex 任务已完成"
        } else if !runningSessions.isEmpty {
            button.toolTip = "\(runningSessions.count) 个 Codex 任务正在运行"
        } else {
            button.toolTip = "Codex 当前空闲"
        }
    }

    private func updateMenu() {
        let report = usageAnalyzer.buildReport()
        runningSessions = report.runningSessions

        let menu = NSMenu()
        menu.delegate = self

        let summary = UsageMenuSummaryView(
            report: report,
            pendingCount: pendingCount,
            lastCompletion: lastCompletion,
            runningCount: runningSessions.count
        )
        let summaryItem = NSMenuItem()
        summaryItem.view = summary
        menu.addItem(summaryItem)
        usageSummaryView = summary

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "打开 Codex",
            action: #selector(openCodexMenuItem),
            keyEquivalent: "o"
        ))

        if !runningSessions.isEmpty {
            let runningItem = NSMenuItem(
                title: "运行中：\(runningSessions.count) 个任务",
                action: nil,
                keyEquivalent: ""
            )
            runningItem.isEnabled = false
            menu.addItem(runningItem)

            for session in runningSessions.prefix(3) {
                let item = NSMenuItem(
                    title: "  \(session.title)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem(
            title: "全部标记已读",
            action: #selector(markAllReadMenuItem),
            keyEquivalent: "r"
        ))

        menu.addItem(NSMenuItem(
            title: "完成历史",
            action: #selector(showCompletionHistoryMenuItem),
            keyEquivalent: "h"
        ))

        menu.addItem(NSMenuItem(
            title: "使用量统计",
            action: #selector(showUsageDashboardMenuItem),
            keyEquivalent: "u"
        ))

        menu.addItem(NSMenuItem(
            title: "发送测试通知",
            action: #selector(sendTestNotificationMenuItem),
            keyEquivalent: "t"
        ))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
        updateStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        let report = usageAnalyzer.buildReport()
        runningSessions = report.runningSessions
        usageSummaryView?.update(
            report: report,
            pendingCount: pendingCount,
            lastCompletion: lastCompletion,
            runningCount: runningSessions.count
        )
        updateStatusItem()
    }

    @objc private func openCodexMenuItem() {
        openCodex()
    }

    @objc private func markAllReadMenuItem() {
        markAllRead()
    }

    @objc private func sendTestNotificationMenuItem() {
        let completion = CodexCompletion(
            key: "test-\(UUID().uuidString)",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            threadID: nil,
            threadName: "测试",
            filePath: "",
            lineOffset: 0,
            preview: "这是一条测试通知。"
        )
        handleCompletion(completion)
    }

    @objc private func showUsageDashboardMenuItem() {
        showUsageDashboard()
    }

    @objc private func showCompletionHistoryMenuItem() {
        showCompletionHistory()
    }

    private func markAllRead() {
        pendingCount = 0
        updateDockBadge()
        updateMenu()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func openCodex(threadID: String? = nil, filePath: String? = nil, lineOffset: String? = nil) {
        copyThreadReference(threadID: threadID, filePath: filePath, lineOffset: lineOffset)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Codex"]
        do {
            try process.run()
        } catch {
            NSLog("CodexDockNotifier failed to open Codex: \(error)")
        }
    }

    private func copyThreadReference(threadID: String?, filePath: String?, lineOffset: String?) {
        let parts = [
            threadID.flatMap { $0.isEmpty ? nil : "thread \($0)" },
            filePath.flatMap { $0.isEmpty ? nil : $0 },
            lineOffset.flatMap { $0.isEmpty ? nil : "offset \($0)" }
        ].compactMap { $0 }

        guard !parts.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: "\n"), forType: .string)
    }

    private func showUsageDashboard() {
        if usageWindowController == nil {
            usageWindowController = UsageDashboardWindowController()
        }

        usageWindowController?.showWindow(nil)
        usageWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showCompletionHistory() {
        if historyWindowController == nil {
            historyWindowController = CompletionHistoryWindowController(
                history: completionHistory,
                openHandler: { [weak self] completion in
                    self?.openCompletion(completion)
                }
            )
        }

        historyWindowController?.update(history: completionHistory)
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openCompletion(_ completion: CodexCompletion) {
        openCodex(
            threadID: completion.threadID,
            filePath: completion.filePath,
            lineOffset: String(completion.lineOffset)
        )
    }

    private func recordCompletionInHistory(_ completion: CodexCompletion) {
        completionHistory.removeAll { $0.key == completion.key }
        completionHistory.insert(completion, at: 0)
        if completionHistory.count > 200 {
            completionHistory = Array(completionHistory.prefix(200))
        }
        historyWindowController?.update(history: completionHistory)
    }

    private func startActivityTimer() {
        activityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActivityStatus()
            }
        }
    }

    private func refreshActivityStatus(sendReminders: Bool = true) {
        let report = usageAnalyzer.buildReport()
        runningSessions = report.runningSessions
        if sendReminders {
            sendLongTaskRemindersIfNeeded(for: runningSessions)
        }
        updateStatusItem()
        usageSummaryView?.update(
            report: report,
            pendingCount: pendingCount,
            lastCompletion: lastCompletion,
            runningCount: runningSessions.count
        )
    }

    private func sendLongTaskRemindersIfNeeded(for sessions: [RunningSession]) {
        for session in sessions where session.runningForSeconds >= longTaskReminderThreshold {
            let startedKey = session.startedAt.map { "\(Int($0.timeIntervalSince1970))" } ?? "unknown"
            let key = "\(session.id):\(startedKey)"
            guard !longTaskReminderKeys.contains(key) else {
                continue
            }

            longTaskReminderKeys.insert(key)
            postLongTaskNotification(for: session)
        }
    }

    private func postLongTaskNotification(for session: RunningSession) {
        let content = UNMutableNotificationContent()
        content.title = "Codex 长任务仍在运行"
        content.subtitle = session.title
        content.body = "已运行 \(formatDuration(session.runningForSeconds)) · \(session.model)"
        content.sound = .default
        content.userInfo = [
            "threadID": session.id,
            "filePath": "",
            "lineOffset": ""
        ]

        let request = UNNotificationRequest(
            identifier: "long-task-\(session.id)-\(Int(session.lastActivityAt.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("CodexDockNotifier failed to post long task notification: \(error)")
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
