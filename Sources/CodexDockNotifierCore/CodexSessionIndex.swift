import Foundation

public enum CodexSessionIndex {
    public struct ThreadInfo: Equatable, Sendable {
        public var id: String
        public var title: String?
        public var model: String?
        public var tokensUsed: Int

        public init(id: String, title: String?, model: String?, tokensUsed: Int = 0) {
            self.id = id.lowercased()
            self.title = title
            self.model = model
            self.tokensUsed = tokensUsed
        }
    }

    public static func loadThreadNames(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return [:]
        }

        var names: [String: String] = [:]

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = object["id"] as? String
            else {
                continue
            }

            if let name = object["thread_name"] as? String, !name.isEmpty {
                names[id.lowercased()] = name
            } else if let title = object["title"] as? String, !title.isEmpty {
                names[id.lowercased()] = title
            }
        }

        return names
    }

    public static func loadThreadInfo(indexURL: URL, stateDatabaseURL: URL) -> [String: ThreadInfo] {
        var info: [String: ThreadInfo] = [:]

        for (id, name) in loadThreadNames(from: indexURL) {
            info[id] = ThreadInfo(id: id, title: name, model: nil)
        }

        for item in loadThreadInfoFromSQLite(at: stateDatabaseURL) {
            let id = item.id.lowercased()
            var existing = info[id] ?? ThreadInfo(id: id, title: nil, model: nil)
            if let title = item.title, !title.isEmpty {
                existing.title = title
            }
            if let model = item.model, !model.isEmpty {
                existing.model = model
            }
            existing.tokensUsed = item.tokensUsed
            info[id] = existing
        }

        return info
    }

    private static func loadThreadInfoFromSQLite(at url: URL) -> [ThreadInfo] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-separator",
            "\t",
            url.path,
            "select id, title, coalesce(model, ''), tokens_used from threads;"
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> ThreadInfo? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 4 else {
                    return nil
                }

                return ThreadInfo(
                    id: parts[0],
                    title: parts[1].isEmpty ? nil : parts[1],
                    model: parts[2].isEmpty ? nil : parts[2],
                    tokensUsed: Int(parts[3]) ?? 0
                )
            }
    }
}
