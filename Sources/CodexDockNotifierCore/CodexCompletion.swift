import Foundation

public struct CodexCompletion: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key }

    public var key: String
    public var timestamp: String
    public var threadID: String?
    public var threadName: String?
    public var filePath: String
    public var lineOffset: UInt64
    public var preview: String
    public var badges: [String]
    public var fileMentions: [String]
    public var tested: Bool
    public var needsAttention: Bool

    public init(
        key: String,
        timestamp: String,
        threadID: String?,
        threadName: String?,
        filePath: String,
        lineOffset: UInt64,
        preview: String,
        badges: [String] = [],
        fileMentions: [String] = [],
        tested: Bool = false,
        needsAttention: Bool = false
    ) {
        self.key = key
        self.timestamp = timestamp
        self.threadID = threadID
        self.threadName = threadName
        self.filePath = filePath
        self.lineOffset = lineOffset
        self.preview = preview
        self.badges = badges
        self.fileMentions = fileMentions
        self.tested = tested
        self.needsAttention = needsAttention
    }

    public var badgeSummary: String {
        badges.joined(separator: " · ")
    }

    public var notificationBody: String {
        guard !badgeSummary.isEmpty else {
            return preview
        }
        return "\(badgeSummary)\n\(preview)"
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case timestamp
        case threadID
        case threadName
        case filePath
        case lineOffset
        case preview
        case badges
        case fileMentions
        case tested
        case needsAttention
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        threadName = try container.decodeIfPresent(String.self, forKey: .threadName)
        filePath = try container.decode(String.self, forKey: .filePath)
        lineOffset = try container.decode(UInt64.self, forKey: .lineOffset)
        preview = try container.decode(String.self, forKey: .preview)
        badges = try container.decodeIfPresent([String].self, forKey: .badges) ?? []
        fileMentions = try container.decodeIfPresent([String].self, forKey: .fileMentions) ?? []
        tested = try container.decodeIfPresent(Bool.self, forKey: .tested) ?? false
        needsAttention = try container.decodeIfPresent(Bool.self, forKey: .needsAttention) ?? false
    }
}
