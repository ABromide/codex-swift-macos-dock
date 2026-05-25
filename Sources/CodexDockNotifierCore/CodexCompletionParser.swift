import Foundation

public enum CodexCompletionParser {
    public static func parseCompletionLine(
        _ line: String,
        filePath: String,
        lineOffset: UInt64
    ) -> CodexCompletion? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "response_item",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              payload["role"] as? String == "assistant",
              payload["phase"] as? String == "final_answer"
        else {
            return nil
        }

        let timestamp = object["timestamp"] as? String ?? ""
        let text = outputText(from: payload["content"])
        let preview = makePreview(from: text)
        let fileMentions = extractFileMentions(from: text)
        let tested = detectsVerification(in: text)
        let needsAttention = detectsNeedsAttention(in: text)
        let badges = makeBadges(
            fileMentionCount: fileMentions.count,
            tested: tested,
            needsAttention: needsAttention
        )
        let key = "\(filePath):\(lineOffset)"

        return CodexCompletion(
            key: key,
            timestamp: timestamp,
            threadID: threadID(from: filePath),
            threadName: nil,
            filePath: filePath,
            lineOffset: lineOffset,
            preview: preview,
            badges: badges,
            fileMentions: fileMentions,
            tested: tested,
            needsAttention: needsAttention
        )
    }

    public static func threadID(from filePath: String) -> String? {
        let filename = URL(fileURLWithPath: filePath).lastPathComponent
        let pattern = #"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              let idRange = Range(match.range(at: 1), in: filename)
        else {
            return nil
        }
        return String(filename[idRange]).lowercased()
    }

    public static func makePreview(from text: String, limit: Int = 180) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else {
            return "Codex has finished the latest task."
        }

        if collapsed.count <= limit {
            return collapsed
        }

        let end = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<end]) + "..."
    }

    private static func outputText(from content: Any?) -> String {
        guard let parts = content as? [[String: Any]] else {
            return ""
        }

        return parts
            .compactMap { part -> String? in
                guard part["type"] as? String == "output_text" else {
                    return nil
                }
                return part["text"] as? String
            }
            .joined(separator: "\n")
    }

    private static func makeBadges(
        fileMentionCount: Int,
        tested: Bool,
        needsAttention: Bool
    ) -> [String] {
        var badges: [String] = []
        if fileMentionCount > 0 {
            badges.append("\(fileMentionCount) 个文件")
        }
        if tested {
            badges.append("已验证")
        }
        if needsAttention {
            badges.append("需处理")
        }
        return badges
    }

    private static func detectsVerification(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let keywords = [
            "test passed",
            "tests passed",
            "smoke tests passed",
            "verified",
            "verification",
            "passed",
            "ran tests",
            "make test",
            "swift test",
            "npm test",
            "pytest",
            "验证",
            "测试通过",
            "已测试",
            "已验证",
            "构建通过"
        ]
        return keywords.contains { lowercased.contains($0.lowercased()) }
    }

    private static func detectsNeedsAttention(in text: String) -> Bool {
        let lowercased = text.lowercased()
        let keywords = [
            "failed",
            "failure",
            "unable",
            "could not",
            "not able",
            "blocked",
            "需要你",
            "需要手动",
            "未能",
            "失败",
            "报错",
            "阻塞",
            "没有运行",
            "无法"
        ]
        return keywords.contains { lowercased.contains($0.lowercased()) }
    }

    private static func extractFileMentions(from text: String) -> [String] {
        let pattern = #"(?:^|[\s`'"\(\[])([A-Za-z0-9_./~+-]+?\.(?:swift|md|json|jsonl|plist|sh|txt|yml|yaml|toml|csv|ts|tsx|js|jsx|css|html|py|rb|go|rs|java|kt|m|mm|h|hpp|cpp|c|sql))(?:$|[\s`'",\)\].:;])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen: Set<String> = []
        var matches: [String] = []

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let range = Range(match.range(at: 1), in: text)
            else {
                return
            }

            let value = String(text[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: "`'\""))
            guard !value.isEmpty, !seen.contains(value) else {
                return
            }
            seen.insert(value)
            matches.append(value)
        }

        return Array(matches.prefix(8))
    }
}
