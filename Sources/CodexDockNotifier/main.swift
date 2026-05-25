import AppKit
import CodexDockNotifierCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: CodexMonitor?
    private var usageWindowController: UsageDashboardWindowController?
    private let usageAnalyzer = UsageStatsAnalyzer()
    private weak var usageSummaryView: UsageMenuSummaryView?
    private var pendingCount = 0
    private var lastCompletion: CodexCompletion?

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
        monitor?.start()
        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        await MainActor.run {
            self.markAllRead()
            self.openCodex()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Codex"
        item.button?.toolTip = "Codex Dock Notifier"
        statusItem = item
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

        NSApp.requestUserAttention(.informationalRequest)
        updateDockBadge()
        updateMenu()
        postNotification(for: completion)
    }

    private func postNotification(for completion: CodexCompletion) {
        let content = UNMutableNotificationContent()
        content.title = "Codex 任务完成"
        content.subtitle = completion.threadName ?? "Codex"
        content.body = completion.preview
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

    private func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let summary = UsageMenuSummaryView(
            report: usageAnalyzer.buildReport(),
            pendingCount: pendingCount,
            lastCompletion: lastCompletion
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

        menu.addItem(NSMenuItem(
            title: "全部标记已读",
            action: #selector(markAllReadMenuItem),
            keyEquivalent: "r"
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
        statusItem?.button?.title = pendingCount > 0 ? "Codex \(pendingCount)" : "Codex"
    }

    func menuWillOpen(_ menu: NSMenu) {
        usageSummaryView?.update(
            report: usageAnalyzer.buildReport(),
            pendingCount: pendingCount,
            lastCompletion: lastCompletion
        )
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

    private func markAllRead() {
        pendingCount = 0
        updateDockBadge()
        updateMenu()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func openCodex() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Codex"]
        do {
            try process.run()
        } catch {
            NSLog("CodexDockNotifier failed to open Codex: \(error)")
        }
    }

    private func showUsageDashboard() {
        if usageWindowController == nil {
            usageWindowController = UsageDashboardWindowController()
        }

        usageWindowController?.showWindow(nil)
        usageWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
