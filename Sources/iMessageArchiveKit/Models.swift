import Foundation

public enum ServiceType: String, Sendable, Codable, CaseIterable {
    case iMessage = "iMessage"
    case sms = "SMS"
    case rcs = "RCS"
    case unknown = "Unknown"

    public static func from(raw: String?) -> ServiceType {
        guard let raw = raw?.lowercased() else { return .unknown }
        if raw.contains("imessage") { return .iMessage }
        if raw.contains("sms") { return .sms }
        if raw.contains("rcs") { return .rcs }
        return .unknown
    }
}

public enum TapbackType: Int, Sendable, Codable, CaseIterable {
    case love = 2000
    case like = 2001
    case dislike = 2002
    case laugh = 2003
    case emphasize = 2004
    case question = 2005
    case customEmoji = 2006
    case removed = 3000

    public var emoji: String {
        switch self {
        case .love: return "❤️"
        case .like: return "👍"
        case .dislike: return "👎"
        case .laugh: return "😆"
        case .emphasize: return "‼️"
        case .question: return "❓"
        case .customEmoji, .removed: return ""
        }
    }

    public var symbolName: String {
        switch self {
        case .love: return "heart.fill"
        case .like: return "hand.thumbsup.fill"
        case .dislike: return "hand.thumbsdown.fill"
        case .laugh: return "face.smiling.inverse"
        case .emphasize: return "exclamationmark.2"
        case .question: return "questionmark"
        case .customEmoji, .removed: return "bubble.left.and.bubble.right.fill"
        }
    }
}

public struct Tapback: Sendable, Codable, Identifiable {
    public var id: String { "\(type.rawValue)-\(senderAddress)-\(emojiReaction)" }
    public let type: TapbackType
    public let emojiReaction: String
    public let senderAddress: String
    public let isFromMe: Bool

    public init(type: TapbackType, emojiReaction: String = "", senderAddress: String, isFromMe: Bool) {
        self.type = type
        self.emojiReaction = emojiReaction
        self.senderAddress = senderAddress
        self.isFromMe = isFromMe
    }

    public var displayEmoji: String {
        if !emojiReaction.isEmpty {
            return emojiReaction
        }
        return type.emoji
    }
}

public struct Handle: Sendable, Codable, Identifiable, Hashable {
    public let id: Int64
    public let address: String
    public let service: ServiceType
    public var contactName: String?

    public init(id: Int64, address: String, service: ServiceType, contactName: String? = nil) {
        self.id = id
        self.address = address
        self.service = service
        self.contactName = contactName
    }

    public var displayName: String {
        if let name = contactName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return address
    }
}

public struct ChatAttachment: Sendable, Codable, Identifiable {
    public let id: Int64
    public let guid: String
    public let filename: String
    public let mimeType: String?
    public let fileSize: Int64
    public let transferName: String?
    public let isSticker: Bool

    public init(
        id: Int64,
        guid: String,
        filename: String,
        mimeType: String? = nil,
        fileSize: Int64 = 0,
        transferName: String? = nil,
        isSticker: Bool = false
    ) {
        self.id = id
        self.guid = guid
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.transferName = transferName
        self.isSticker = isSticker
    }

    public var resolvedURL: URL? {
        if filename.isEmpty { return nil }
        let expanded = NSString(string: filename).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public var isImage: Bool {
        if let mime = mimeType?.lowercased(), mime.starts(with: "image/") { return true }
        let ext = (transferName ?? filename).lowercased()
        return ext.hasSuffix(".jpg") || ext.hasSuffix(".jpeg") || ext.hasSuffix(".png") ||
               ext.hasSuffix(".heic") || ext.hasSuffix(".gif") || ext.hasSuffix(".webp")
    }

    public var isAudio: Bool {
        if let mime = mimeType?.lowercased(), mime.starts(with: "audio/") { return true }
        let ext = (transferName ?? filename).lowercased()
        return ext.hasSuffix(".caf") || ext.hasSuffix(".m4a") || ext.hasSuffix(".mp3")
    }

    public var isVideo: Bool {
        if let mime = mimeType?.lowercased(), mime.starts(with: "video/") { return true }
        let ext = (transferName ?? filename).lowercased()
        return ext.hasSuffix(".mov") || ext.hasSuffix(".mp4")
    }
}

public struct ChatMessage: Sendable, Codable, Identifiable {
    public let id: Int64
    public let guid: String
    public let text: String
    public let isFromMe: Bool
    public let date: Date
    public let service: ServiceType
    public let handleId: Int64
    public var senderAddress: String
    public var senderName: String?
    public var tapbacks: [Tapback]
    public var attachments: [ChatAttachment]

    public init(
        id: Int64,
        guid: String,
        text: String,
        isFromMe: Bool,
        date: Date,
        service: ServiceType,
        handleId: Int64 = 0,
        senderAddress: String = "",
        senderName: String? = nil,
        tapbacks: [Tapback] = [],
        attachments: [ChatAttachment] = []
    ) {
        self.id = id
        self.guid = guid
        self.text = text
        self.isFromMe = isFromMe
        self.date = date
        self.service = service
        self.handleId = handleId
        self.senderAddress = senderAddress
        self.senderName = senderName
        self.tapbacks = tapbacks
        self.attachments = attachments
    }

    public var cleanText: String {
        // Strip Apple object replacement character \u{FFFC}
        let stripped = text.replacingOccurrences(of: "\u{FFFC}", with: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Conversation: Sendable, Codable, Identifiable, Hashable {
    public let id: Int64
    public let guid: String
    public let chatIdentifier: String
    public let displayName: String?
    public let service: ServiceType
    public var participants: [Handle]
    public var messageCount: Int
    public var lastMessageDate: Date?
    public var lastMessageSnippet: String?

    public init(
        id: Int64,
        guid: String,
        chatIdentifier: String,
        displayName: String? = nil,
        service: ServiceType = .iMessage,
        participants: [Handle] = [],
        messageCount: Int = 0,
        lastMessageDate: Date? = nil,
        lastMessageSnippet: String? = nil
    ) {
        self.id = id
        self.guid = guid
        self.chatIdentifier = chatIdentifier
        self.displayName = displayName
        self.service = service
        self.participants = participants
        self.messageCount = messageCount
        self.lastMessageDate = lastMessageDate
        self.lastMessageSnippet = lastMessageSnippet
    }

    public var isGroup: Bool {
        participants.count > 1 || (displayName != nil && !displayName!.isEmpty)
    }

    public var resolvedTitle: String {
        if let name = displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        let participantNames = participants.map(\.displayName).filter { !$0.isEmpty }
        if !participantNames.isEmpty {
            return participantNames.joined(separator: ", ")
        }
        return ContactResolver.shared.resolve(address: chatIdentifier)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(guid)
    }

    public static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id && lhs.guid == rhs.guid
    }
}

public struct ArchivePlan: Sendable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var archiveAll: Bool
    public var selectedChatGuids: Set<String>
    public var destinationPath: String
    public var lastArchivedDate: Date?
    public var includeAttachments: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Complete Messages Archive",
        archiveAll: Bool = true,
        selectedChatGuids: Set<String> = [],
        destinationPath: String = "~/Documents/iMessageArchive",
        lastArchivedDate: Date? = nil,
        includeAttachments: Bool = true
    ) {
        self.id = id
        self.name = name
        self.archiveAll = archiveAll
        self.selectedChatGuids = selectedChatGuids
        self.destinationPath = destinationPath
        self.lastArchivedDate = lastArchivedDate
        self.includeAttachments = includeAttachments
    }
}

public enum ScheduleFrequency: String, Sendable, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case manual = "Manual"
}

public struct ArchiveSchedule: Sendable, Codable, Identifiable {
    public let id: UUID
    public var planId: UUID
    public var frequency: ScheduleFrequency
    public var hour: Int
    public var minute: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        planId: UUID,
        frequency: ScheduleFrequency = .daily,
        hour: Int = 2,
        minute: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.planId = planId
        self.frequency = frequency
        self.hour = hour
        self.minute = minute
        self.isEnabled = enabledOrDefault(isEnabled)
    }
}

private func enabledOrDefault(_ value: Bool) -> Bool { value }
