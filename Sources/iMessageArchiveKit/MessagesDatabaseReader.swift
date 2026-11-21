import Foundation
import SQLite3
import AppKit

public enum DatabaseAccessStatus: Sendable, Equatable {
    case accessible
    case fileNotFound
    case permissionDenied(String)
}

public final class MessagesDatabaseReader: @unchecked Sendable {
    public static let defaultDatabaseURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Messages/chat.db")
    }()

    private let databaseURL: URL
    private var db: OpaquePointer?

    public init(databaseURL: URL = MessagesDatabaseReader.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    deinit {
        close()
    }

    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    public static func checkAccess(at url: URL = MessagesDatabaseReader.defaultDatabaseURL) -> DatabaseAccessStatus {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .fileNotFound
        }

        var testDb: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let status = sqlite3_open_v2(url.path, &testDb, flags, nil)
        if status == SQLITE_OK {
            sqlite3_close(testDb)
            return .accessible
        } else {
            let msg = testDb != nil ? String(cString: sqlite3_errmsg(testDb)) : "Failed to open sqlite database"
            if let testDb = testDb { sqlite3_close(testDb) }
            return .permissionDenied(msg)
        }
    }

    public func open() throws {
        guard db == nil else { return }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let status = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard status == SQLITE_OK else {
            let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "Could not open \(databaseURL.path)"
            close()
            throw NSError(domain: "iMessageArchive.DatabaseReader", code: Int(status), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    public func fetchConversations() throws -> [Conversation] {
        try open()
        guard let db = db else { return [] }

        let query = """
        SELECT 
            c.ROWID, 
            c.guid, 
            c.chat_identifier, 
            c.display_name, 
            c.service_name, 
            COUNT(cmj.message_id) as msg_count, 
            MAX(m.date) as last_date
        FROM chat c
        LEFT JOIN chat_message_join cmj ON c.ROWID = cmj.chat_id
        LEFT JOIN message m ON cmj.message_id = m.ROWID
        GROUP BY c.ROWID
        ORDER BY last_date DESC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "iMessageArchive.DatabaseReader", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        var conversations: [Conversation] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let guid = String(cString: sqlite3_column_text(stmt, 1))
            let chatIdentifier = String(cString: sqlite3_column_text(stmt, 2))
            
            var displayName: String? = nil
            if let namePtr = sqlite3_column_text(stmt, 3) {
                let name = String(cString: namePtr)
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = name
                }
            }

            var serviceStr: String? = nil
            if let svcPtr = sqlite3_column_text(stmt, 4) {
                serviceStr = String(cString: svcPtr)
            }
            let service = ServiceType.from(raw: serviceStr)

            let msgCount = Int(sqlite3_column_int(stmt, 5))
            let lastDateRaw = sqlite3_column_int64(stmt, 6)
            let lastDate = lastDateRaw > 0 ? Self.convertDate(lastDateRaw) : nil

            let conv = Conversation(
                id: id,
                guid: guid,
                chatIdentifier: chatIdentifier,
                displayName: displayName,
                service: service,
                participants: [],
                messageCount: msgCount,
                lastMessageDate: lastDate,
                lastMessageSnippet: nil
            )
            conversations.append(conv)
        }

        // Fetch handles and last snippets for each conversation
        for i in 0..<conversations.count {
            conversations[i].participants = try fetchHandles(forChatId: conversations[i].id, defaultIdentifier: conversations[i].chatIdentifier)
            conversations[i].lastMessageSnippet = try fetchLatestSnippet(forChatId: conversations[i].id)
        }

        return conversations
    }

    private func fetchHandles(forChatId chatId: Int64, defaultIdentifier: String) throws -> [Handle] {
        guard let db = db else { return [] }
        let query = """
        SELECT h.ROWID, h.id, h.service 
        FROM chat_handle_join chj 
        JOIN handle h ON chj.handle_id = h.ROWID 
        WHERE chj.chat_id = ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatId)

        var handles: [Handle] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            let address = String(cString: sqlite3_column_text(stmt, 1))
            let svc = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : ""
            handles.append(Handle(id: rowid, address: address, service: ServiceType.from(raw: svc)))
        }

        // Fallback for 1-on-1 SMS chats where chat_handle_join row might be absent
        if handles.isEmpty && !defaultIdentifier.isEmpty && !defaultIdentifier.hasPrefix("chat") {
            handles.append(Handle(id: 0, address: defaultIdentifier, service: .unknown))
        }

        return handles
    }

    private func fetchLatestSnippet(forChatId chatId: Int64) throws -> String? {
        guard let db = db else { return nil }
        let query = """
        SELECT m.text, m.attributedBody 
        FROM chat_message_join cmj 
        JOIN message m ON cmj.message_id = m.ROWID 
        WHERE cmj.chat_id = ? AND (m.associated_message_type IS NULL OR m.associated_message_type = 0)
        ORDER BY m.date DESC LIMIT 1;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatId)

        if sqlite3_step(stmt) == SQLITE_ROW {
            if let textPtr = sqlite3_column_text(stmt, 0) {
                let text = String(cString: textPtr)
                let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }

            if let blobBytes = sqlite3_column_blob(stmt, 1) {
                let blobLen = sqlite3_column_bytes(stmt, 1)
                if blobLen > 0 {
                    let data = Data(bytes: blobBytes, count: Int(blobLen))
                    if let text = Self.extractAttributedText(from: data) {
                        let cleaned = text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty { return cleaned }
                    }
                }
            }
        }
        return nil
    }

    public func fetchMessages(chatId: Int64, limit: Int = 1000, offset: Int = 0) throws -> [ChatMessage] {
        try open()
        guard let db = db else { return [] }

        let query = """
        SELECT 
            m.ROWID, 
            m.guid, 
            m.text, 
            m.attributedBody, 
            m.is_from_me, 
            m.date, 
            m.service, 
            m.handle_id, 
            h.id AS handle_address,
            m.cache_has_attachments
        FROM chat_message_join cmj 
        JOIN message m ON cmj.message_id = m.ROWID 
        LEFT JOIN handle h ON m.handle_id = h.ROWID 
        WHERE cmj.chat_id = ? AND (m.associated_message_type IS NULL OR m.associated_message_type = 0)
        ORDER BY m.date ASC 
        LIMIT ? OFFSET ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "iMessageArchive.DatabaseReader", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chatId)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        sqlite3_bind_int(stmt, 3, Int32(offset))

        var messages: [ChatMessage] = []
        var messageGuids: [String] = []
        var messageIds: [Int64] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let guid = String(cString: sqlite3_column_text(stmt, 1))

            var text = ""
            if let textPtr = sqlite3_column_text(stmt, 2) {
                text = String(cString: textPtr)
            } else if let blobBytes = sqlite3_column_blob(stmt, 3) {
                let blobLen = sqlite3_column_bytes(stmt, 3)
                if blobLen > 0 {
                    let data = Data(bytes: blobBytes, count: Int(blobLen))
                    text = Self.extractAttributedText(from: data) ?? ""
                }
            }

            let isFromMe = sqlite3_column_int(stmt, 4) == 1
            let rawDate = sqlite3_column_int64(stmt, 5)
            let date = Self.convertDate(rawDate)

            let serviceStr = sqlite3_column_text(stmt, 6) != nil ? String(cString: sqlite3_column_text(stmt, 6)) : ""
            let service = ServiceType.from(raw: serviceStr)

            let handleId = sqlite3_column_int64(stmt, 7)
            let handleAddress = sqlite3_column_text(stmt, 8) != nil ? String(cString: sqlite3_column_text(stmt, 8)) : ""

            let msg = ChatMessage(
                id: id,
                guid: guid,
                text: text,
                isFromMe: isFromMe,
                date: date,
                service: service,
                handleId: handleId,
                senderAddress: handleAddress,
                senderName: nil,
                tapbacks: [],
                attachments: []
            )

            messages.append(msg)
            messageGuids.append(guid)
            messageIds.append(id)
        }

        // Attachments
        if !messageIds.isEmpty {
            let attachmentsByMsgId = try fetchAttachments(forMessageIds: messageIds)
            for i in 0..<messages.count {
                if let atts = attachmentsByMsgId[messages[i].id] {
                    messages[i].attachments = atts
                }
            }
        }

        // Tapbacks
        if !messageGuids.isEmpty {
            let tapbacksByGuid = try fetchTapbacks(forMessageGuids: messageGuids)
            for i in 0..<messages.count {
                if let taps = tapbacksByGuid[messages[i].guid] {
                    messages[i].tapbacks = taps
                }
            }
        }

        return messages
    }

    private func fetchAttachments(forMessageIds messageIds: [Int64]) throws -> [Int64: [ChatAttachment]] {
        guard let db = db, !messageIds.isEmpty else { return [:] }
        let idList = messageIds.map(String.init).joined(separator: ",")
        let query = """
        SELECT 
            maj.message_id, 
            a.ROWID, 
            a.guid, 
            a.filename, 
            a.mime_type, 
            a.total_bytes, 
            a.transfer_name, 
            a.is_sticker
        FROM message_attachment_join maj 
        JOIN attachment a ON maj.attachment_id = a.ROWID 
        WHERE maj.message_id IN (\(idList));
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var result: [Int64: [ChatAttachment]] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let msgId = sqlite3_column_int64(stmt, 0)
            let attId = sqlite3_column_int64(stmt, 1)
            let guid = String(cString: sqlite3_column_text(stmt, 2))
            let filename = sqlite3_column_text(stmt, 3) != nil ? String(cString: sqlite3_column_text(stmt, 3)) : ""
            let mime = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : nil
            let totalBytes = sqlite3_column_int64(stmt, 5)
            let transferName = sqlite3_column_text(stmt, 6) != nil ? String(cString: sqlite3_column_text(stmt, 6)) : nil
            let isSticker = sqlite3_column_int(stmt, 7) == 1

            let attachment = ChatAttachment(
                id: attId,
                guid: guid,
                filename: filename,
                mimeType: mime,
                fileSize: totalBytes,
                transferName: transferName,
                isSticker: isSticker
            )

            result[msgId, default: []].append(attachment)
        }

        return result
    }

    private func fetchTapbacks(forMessageGuids guids: [String]) throws -> [String: [Tapback]] {
        guard let db = db, !guids.isEmpty else { return [:] }
        // Create matching set of potential prefixed guids: original, p:0/guid, bp:guid
        var candidates: [String] = []
        for g in guids {
            let escaped = g.replacingOccurrences(of: "'", with: "''")
            candidates.append("'\(escaped)'")
            candidates.append("'p:0/\(escaped)'")
            candidates.append("'bp:\(escaped)'")
        }
        let inClause = candidates.joined(separator: ",")

        let query = """
        SELECT 
            m.associated_message_type, 
            m.associated_message_guid, 
            m.associated_message_emoji, 
            m.is_from_me, 
            h.id as handle_address
        FROM message m 
        LEFT JOIN handle h ON m.handle_id = h.ROWID 
        WHERE m.associated_message_type IS NOT NULL 
          AND m.associated_message_type != 0
          AND m.associated_message_guid IN (\(inClause));
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var result: [String: [Tapback]] = [:]
        let guidSet = Set(guids)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let typeInt = Int(sqlite3_column_int(stmt, 0))
            guard let rawAssocGuid = sqlite3_column_text(stmt, 1) else { continue }
            let assocGuidStr = String(cString: rawAssocGuid)
            let cleanGuid = Self.normalizeAssociatedGuid(assocGuidStr)

            guard guidSet.contains(cleanGuid) else { continue }

            let emojiStr = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : ""
            let isFromMe = sqlite3_column_int(stmt, 3) == 1
            let handleAddress = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : ""

            let tapType = TapbackType(rawValue: typeInt) ?? .customEmoji
            let tapback = Tapback(
                type: tapType,
                emojiReaction: emojiStr,
                senderAddress: handleAddress,
                isFromMe: isFromMe
            )

            result[cleanGuid, default: []].append(tapback)
        }

        return result
    }

    public static func normalizeAssociatedGuid(_ raw: String) -> String {
        // Strip p:0/ or bp: prefix
        if let range = raw.range(of: "/", options: .backwards) {
            return String(raw[range.upperBound...])
        }
        if raw.hasPrefix("bp:") {
            return String(raw.dropFirst(3))
        }
        return raw
    }

    public static func convertDate(_ timestamp: Int64) -> Date {
        // Apple timestamps are nanoseconds since 2001-01-01 00:00:00 UTC
        // Older timestamps might be in seconds.
        if timestamp > 100_000_000_000 {
            let seconds = Double(timestamp) / 1_000_000_000.0
            return Date(timeIntervalSinceReferenceDate: seconds)
        } else {
            return Date(timeIntervalSinceReferenceDate: Double(timestamp))
        }
    }

    public static func extractAttributedText(from data: Data) -> String? {
        let unarchiverClass = NSClassFromString("NSUnarchiver") as AnyObject
        if let unarchiveSelector = NSSelectorFromString("unarchiveObjectWithData:") as Selector?,
           unarchiverClass.responds(to: unarchiveSelector) {
            if let result = unarchiverClass.perform(unarchiveSelector, with: data)?.takeUnretainedValue() as? NSAttributedString {
                return result.string
            }
        }

        if let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
            unarchiver.requiresSecureCoding = false
            if let attrStr = unarchiver.decodeObject(forKey: "NS.string") as? String {
                return attrStr
            }
        }

        return nil
    }
}
