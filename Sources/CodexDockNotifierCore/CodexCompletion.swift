import Foundation

public struct CodexCompletion: Codable, Equatable, Sendable {
    public var key: String
    public var timestamp: String
    public var threadID: String?
    public var threadName: String?
    public var filePath: String
    public var lineOffset: UInt64
    public var preview: String

    public init(
        key: String,
        timestamp: String,
        threadID: String?,
        threadName: String?,
        filePath: String,
        lineOffset: UInt64,
        preview: String
    ) {
        self.key = key
        self.timestamp = timestamp
        self.threadID = threadID
        self.threadName = threadName
        self.filePath = filePath
        self.lineOffset = lineOffset
        self.preview = preview
    }
}
