import Foundation

public struct FileCursor: Codable, Equatable, Sendable {
    public var offset: UInt64

    public init(offset: UInt64) {
        self.offset = offset
    }
}

public struct WatchState: Codable, Equatable, Sendable {
    public var cursors: [String: FileCursor]
    public var notifiedKeys: [String]
    public var completionHistory: [CodexCompletion]

    public init(
        cursors: [String: FileCursor] = [:],
        notifiedKeys: [String] = [],
        completionHistory: [CodexCompletion] = []
    ) {
        self.cursors = cursors
        self.notifiedKeys = notifiedKeys
        self.completionHistory = completionHistory
    }

    private enum CodingKeys: String, CodingKey {
        case cursors
        case notifiedKeys
        case completionHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursors = try container.decodeIfPresent([String: FileCursor].self, forKey: .cursors) ?? [:]
        notifiedKeys = try container.decodeIfPresent([String].self, forKey: .notifiedKeys) ?? []
        completionHistory = try container.decodeIfPresent([CodexCompletion].self, forKey: .completionHistory) ?? []
    }

    public static func load(from url: URL) -> WatchState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WatchState.self, from: data)
        else {
            return WatchState()
        }
        return state
    }

    public func save(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: [.atomic])
    }
}
