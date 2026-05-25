import CodexDockNotifierCore
import SwiftUI

@MainActor
final class CompletionHistoryWindowController: NSWindowController {
    private let viewModel: CompletionHistoryViewModel

    init(history: [CodexCompletion], openHandler: @escaping (CodexCompletion) -> Void) {
        self.viewModel = CompletionHistoryViewModel(history: history, openHandler: openHandler)
        let rootView = CompletionHistoryView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex 完成历史"
        window.minSize = NSSize(width: 620, height: 420)
        window.contentView = hostingView

        super.init(window: window)

        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(history: [CodexCompletion]) {
        viewModel.history = history
    }
}

@MainActor
final class CompletionHistoryViewModel: ObservableObject {
    @Published var history: [CodexCompletion]
    private let openHandler: (CodexCompletion) -> Void

    init(history: [CodexCompletion], openHandler: @escaping (CodexCompletion) -> Void) {
        self.history = history
        self.openHandler = openHandler
    }

    func open(_ completion: CodexCompletion) {
        openHandler(completion)
    }
}

struct CompletionHistoryView: View {
    @ObservedObject var viewModel: CompletionHistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if viewModel.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("还没有完成记录")
                        .font(.headline)
                    Text("Codex 完成新任务后会出现在这里。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.history) { completion in
                            CompletionHistoryRow(completion: completion) {
                                viewModel.open(completion)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("完成历史")
                    .font(.system(size: 22, weight: .semibold))
                Text("最近 \(viewModel.history.count) 次 Codex final answer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
    }
}

private struct CompletionHistoryRow: View {
    var completion: CodexCompletion
    var open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: completion.needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(completion.needsAttention ? .orange : .green)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(completion.threadName ?? completion.threadID ?? "Codex 任务")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(formatCompletionTime(completion.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(completion.preview)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if !completion.badges.isEmpty || !completion.fileMentions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(completion.badges, id: \.self) { badge in
                            BadgeView(text: badge)
                        }

                        if let firstFile = completion.fileMentions.first {
                            BadgeView(text: firstFile)
                        }
                    }
                }
            }

            Button {
                open()
            } label: {
                Label("打开", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .help("打开 Codex，并复制该线程 ID 作为定位线索")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BadgeView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}

private func formatCompletionTime(_ timestamp: String) -> String {
    guard let date = parseCompletionDate(timestamp) else {
        return timestamp
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func parseCompletionDate(_ timestamp: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: timestamp) {
        return date
    }

    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: timestamp)
}
