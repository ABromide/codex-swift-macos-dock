import CodexDockNotifierCore
import Foundation

let line = """
{"timestamp":"2026-05-25T12:31:57.956Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done.\\nEverything passed."}],"phase":"final_answer"}}
"""

let path = "/Users/example/.codex/sessions/rollout-2026-05-25T20-43-42-019e5f29-9925-7ae3-8bec-09fb28852531.jsonl"
let completion = CodexCompletionParser.parseCompletionLine(line, filePath: path, lineOffset: 42)

precondition(completion?.threadID == "019e5f29-9925-7ae3-8bec-09fb28852531")
precondition(completion?.key == "\(path):42")
precondition(completion?.preview == "Done. Everything passed.")
precondition(completion?.tested == true)

let commentary = """
{"timestamp":"2026-05-25T12:31:57.956Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Still working."}],"phase":"commentary"}}
"""

precondition(CodexCompletionParser.parseCompletionLine(commentary, filePath: "/tmp/x.jsonl", lineOffset: 0) == nil)

let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexDockNotifierSmokeTest-\(UUID().uuidString)", isDirectory: true)
let sessionsDirectory = temporaryRoot
    .appendingPathComponent("sessions", isDirectory: true)
    .appendingPathComponent("2026", isDirectory: true)
    .appendingPathComponent("05", isDirectory: true)
    .appendingPathComponent("25", isDirectory: true)
let indexFile = temporaryRoot.appendingPathComponent("session_index.jsonl")
let sessionFile = sessionsDirectory.appendingPathComponent("rollout-2026-05-25T20-43-42-019e5f29-9925-7ae3-8bec-09fb28852531.jsonl")
let runningSessionFile = sessionsDirectory.appendingPathComponent("rollout-2026-05-25T20-50-42-119e5f29-9925-7ae3-8bec-09fb28852531.jsonl")

try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
try """
{"id":"019e5f29-9925-7ae3-8bec-09fb28852531","thread_name":"Test Thread","updated_at":"2026-05-25T12:43:50.46958Z"}
""".write(to: indexFile, atomically: true, encoding: .utf8)
try """
{"timestamp":"2026-05-25T12:43:42.340Z","type":"session_meta","payload":{"id":"019e5f29-9925-7ae3-8bec-09fb28852531","timestamp":"2026-05-25T12:43:42.245Z","cwd":"/tmp/project","model":"gpt-5","model_provider":"openai_http"}}
{"timestamp":"2026-05-25T12:44:15.471Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":70,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":100}}}}
{"timestamp":"2026-05-25T12:45:15.471Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Finished."}],"phase":"final_answer"}}
""".write(to: sessionFile, atomically: true, encoding: .utf8)
try """
{"timestamp":"2026-05-25T12:50:42.340Z","type":"session_meta","payload":{"id":"119e5f29-9925-7ae3-8bec-09fb28852531","timestamp":"2026-05-25T12:50:42.245Z","cwd":"/tmp/project","model":"gpt-5","model_provider":"openai_http"}}
{"timestamp":"2026-05-25T12:51:00.471Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Run a task."}]}}
{"timestamp":"2026-05-25T12:52:15.471Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":30,"cached_input_tokens":10,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":40}}}}
""".write(to: runningSessionFile, atomically: true, encoding: .utf8)

let analyzer = UsageStatsAnalyzer(
    sessionsDirectory: temporaryRoot.appendingPathComponent("sessions", isDirectory: true),
    sessionIndexFile: indexFile,
    stateDatabaseFile: temporaryRoot.appendingPathComponent("missing.sqlite")
)
let report = analyzer.buildReport(now: ISO8601DateFormatter().date(from: "2026-05-25T12:55:00Z")!)
precondition(report.totalUsage.total == 140)
precondition(report.todayUsage.cachedInput == 30)
precondition(report.last7DaysUsage.output == 30)
precondition(report.sessionCount == 2)
precondition(report.completionCount == 1)
precondition(report.sessions.first?.title == "Test Thread")
precondition(report.projectUsage.first?.path == "/tmp/project")
precondition(report.projectUsage.first?.usage.total == 140)
precondition(report.totalEstimatedCostUSD > 0)
precondition(report.modelUsage.first?.averageTokensPerSession == 70)
precondition(report.runningSessions.count == 1)
precondition(report.runningSessions.first?.id == "119e5f29-9925-7ae3-8bec-09fb28852531")

let markdown = UsageReportExporter.markdown(report: report)
precondition(markdown.contains("Codex 使用量报告"))
precondition(UsageReportExporter.sessionsCSV(report: report).contains("estimated_cost_usd"))

try? FileManager.default.removeItem(at: temporaryRoot)

print("Smoke tests passed")
