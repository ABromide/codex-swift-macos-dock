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

    public init(cursors: [String: FileCursor] = [:], notifiedKeys: [String] = []) {
        self.cursors = cursors
        self.notifiedKeys = notifiedKeys
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
