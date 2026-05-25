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
        let key = "\(filePath):\(lineOffset)"

        return CodexCompletion(
            key: key,
            timestamp: timestamp,
            threadID: threadID(from: filePath),
            threadName: nil,
            filePath: filePath,
            lineOffset: lineOffset,
            preview: preview
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
}
