import Foundation
import SQLite3

public struct ArchiveProgress: Sendable {
    public let processedMessages: Int
    public let totalMessages: Int
    public let currentAction: String
    public let percent: Double

    public init(processedMessages: Int, totalMessages: Int, currentAction: String) {
        self.processedMessages = processedMessages
        self.totalMessages = totalMessages
        self.currentAction = currentAction
        self.percent = totalMessages > 0 ? Double(processedMessages) / Double(totalMessages) : 0.0
    }
}

public final class ArchiveEngine: @unchecked Sendable {
    private let sourceReader: MessagesDatabaseReader
    private let contactResolver: ContactResolver

    public init(sourceReader: MessagesDatabaseReader, contactResolver: ContactResolver = .shared) {
        self.sourceReader = sourceReader
        self.contactResolver = contactResolver
    }

    public func execute(
        plan: ArchivePlan,
        progress: @Sendable (ArchiveProgress) -> Void
    ) async throws -> Int {
        let destinationDir = URL(fileURLWithPath: NSString(string: plan.destinationPath).expandingTildeInPath)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        let attachmentsDir = destinationDir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

        let dbURL = destinationDir.appendingPathComponent("archive.sqlite")
        var archiveDb: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(dbURL.path, &archiveDb, flags, nil) == SQLITE_OK else {
            throw NSError(domain: "iMessageArchive.ArchiveEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create or open archive database at \(dbURL.path)"])
        }
        defer { sqlite3_close(archiveDb) }

        try initArchiveDatabase(archiveDb)

        progress(ArchiveProgress(processedMessages: 0, totalMessages: 100, currentAction: "Scanning conversations..."))
        let allConversations = try sourceReader.fetchConversations()
        let targetConversations = allConversations.filter { conv in
            if plan.archiveAll { return true }
            return plan.selectedChatGuids.contains(conv.guid)
        }

        let totalExpected = targetConversations.reduce(0) { $0 + $1.messageCount }
        var totalArchived = 0

        for conv in targetConversations {
            progress(ArchiveProgress(
                processedMessages: totalArchived,
                totalMessages: max(totalExpected, 1),
                currentAction: "Archiving \(conv.resolvedTitle)..."
            ))

            // Save conversation record
            try insertOrUpdateConversation(conv, in: archiveDb)

            // Fetch messages in batches
            var offset = 0
            let batchSize = 500

            while true {
                let batch = try sourceReader.fetchMessages(chatId: conv.id, limit: batchSize, offset: offset)
                if batch.isEmpty { break }

                for msg in batch {
                    try insertMessage(msg, chatId: conv.id, in: archiveDb)

                    // Copy attachments
                    if plan.includeAttachments && !msg.attachments.isEmpty {
                        for att in msg.attachments {
                            let copiedFilename = try copyAttachment(att, to: attachmentsDir)
                            try insertAttachment(att, messageId: msg.id, localRelPath: copiedFilename, in: archiveDb)
                        }
                    }

                    // Save tapbacks
                    for tap in msg.tapbacks {
                        try insertTapback(tap, messageGuid: msg.guid, in: archiveDb)
                    }

                    totalArchived += 1
                }

                offset += batch.count
                progress(ArchiveProgress(
                    processedMessages: totalArchived,
                    totalMessages: max(totalExpected, 1),
                    currentAction: "Archiving \(conv.resolvedTitle) (\(totalArchived)/\(totalExpected))..."
                ))

                if batch.count < batchSize { break }
            }
        }

        // Update plan metadata in archive
        try updateArchiveMetadata(totalMessages: totalArchived, in: archiveDb)

        progress(ArchiveProgress(
            processedMessages: totalArchived,
            totalMessages: max(totalArchived, 1),
            currentAction: "Archive complete! (\(totalArchived) messages saved)"
        ))

        return totalArchived
    }

    private func initArchiveDatabase(_ db: OpaquePointer?) throws {
        let schema = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY,
            guid TEXT UNIQUE NOT NULL,
            chat_identifier TEXT NOT NULL,
            display_name TEXT,
            service TEXT,
            participants_json TEXT,
            message_count INTEGER,
            last_message_date REAL
        );

        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY,
            guid TEXT UNIQUE NOT NULL,
            chat_id INTEGER NOT NULL,
            text TEXT,
            is_from_me INTEGER,
            date REAL NOT NULL,
            service TEXT,
            sender_address TEXT,
            sender_name TEXT,
            FOREIGN KEY (chat_id) REFERENCES conversations(id)
        );

        CREATE TABLE IF NOT EXISTS attachments (
            id INTEGER PRIMARY KEY,
            guid TEXT UNIQUE NOT NULL,
            message_id INTEGER NOT NULL,
            original_filename TEXT,
            stored_relative_path TEXT,
            mime_type TEXT,
            file_size INTEGER,
            is_sticker INTEGER,
            FOREIGN KEY (message_id) REFERENCES messages(id)
        );

        CREATE TABLE IF NOT EXISTS tapbacks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message_guid TEXT NOT NULL,
            tapback_type INTEGER NOT NULL,
            emoji TEXT,
            sender_address TEXT,
            is_from_me INTEGER
        );

        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_messages_chat_date ON messages(chat_id, date);
        CREATE INDEX IF NOT EXISTS idx_attachments_msg ON attachments(message_id);
        CREATE INDEX IF NOT EXISTS idx_tapbacks_guid ON tapbacks(message_guid);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, schema, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg != nil ? String(cString: errMsg!) : "Schema error"
            sqlite3_free(errMsg)
            throw NSError(domain: "iMessageArchive.ArchiveEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private func insertOrUpdateConversation(_ conv: Conversation, in db: OpaquePointer?) throws {
        let sql = """
        INSERT INTO conversations (id, guid, chat_identifier, display_name, service, participants_json, message_count, last_message_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(guid) DO UPDATE SET 
            display_name = excluded.display_name,
            message_count = excluded.message_count,
            last_message_date = excluded.last_message_date;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, conv.id)
        sqlite3_bind_text(stmt, 2, conv.guid, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, conv.chatIdentifier, -1, SQLITE_TRANSIENT)
        if let name = conv.displayName {
            sqlite3_bind_text(stmt, 4, name, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_text(stmt, 5, conv.service.rawValue, -1, SQLITE_TRANSIENT)
        
        let participantsData = try? JSONEncoder().encode(conv.participants)
        let participantsStr = participantsData != nil ? String(data: participantsData!, encoding: .utf8) : "[]"
        sqlite3_bind_text(stmt, 6, participantsStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 7, Int32(conv.messageCount))
        sqlite3_bind_double(stmt, 8, conv.lastMessageDate?.timeIntervalSince1970 ?? 0)

        sqlite3_step(stmt)
    }

    private func insertMessage(_ msg: ChatMessage, chatId: Int64, in db: OpaquePointer?) throws {
        let sql = """
        INSERT OR IGNORE INTO messages (id, guid, chat_id, text, is_from_me, date, service, sender_address, sender_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, msg.id)
        sqlite3_bind_text(stmt, 2, msg.guid, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, chatId)
        sqlite3_bind_text(stmt, 4, msg.text, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, msg.isFromMe ? 1 : 0)
        sqlite3_bind_double(stmt, 6, msg.date.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 7, msg.service.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, msg.senderAddress, -1, SQLITE_TRANSIENT)
        if let sName = msg.senderName {
            sqlite3_bind_text(stmt, 9, sName, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        sqlite3_step(stmt)
    }

    private func copyAttachment(_ att: ChatAttachment, to dir: URL) throws -> String {
        guard let sourceURL = att.resolvedURL else { return "" }
        let ext = sourceURL.pathExtension.filter { $0.isLetter || $0.isNumber }
        let safeGuid = att.guid
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "")
        let safeName = "\(safeGuid)\(ext.isEmpty ? "" : ".\(ext)")"
        let destURL = dir.appendingPathComponent(safeName)

        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        }
        return "attachments/\(safeName)"
    }

    private func insertAttachment(_ att: ChatAttachment, messageId: Int64, localRelPath: String, in db: OpaquePointer?) throws {
        let sql = """
        INSERT OR IGNORE INTO attachments (id, guid, message_id, original_filename, stored_relative_path, mime_type, file_size, is_sticker)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, att.id)
        sqlite3_bind_text(stmt, 2, att.guid, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, messageId)
        sqlite3_bind_text(stmt, 4, att.filename, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, localRelPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, att.mimeType ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 7, att.fileSize)
        sqlite3_bind_int(stmt, 8, att.isSticker ? 1 : 0)

        sqlite3_step(stmt)
    }

    private func insertTapback(_ tap: Tapback, messageGuid: String, in db: OpaquePointer?) throws {
        let sql = """
        INSERT INTO tapbacks (message_guid, tapback_type, emoji, sender_address, is_from_me)
        VALUES (?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, messageGuid, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(tap.type.rawValue))
        sqlite3_bind_text(stmt, 3, tap.displayEmoji, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, tap.senderAddress, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, tap.isFromMe ? 1 : 0)

        sqlite3_step(stmt)
    }

    private func updateArchiveMetadata(totalMessages: Int, in db: OpaquePointer?) throws {
        let sql = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let nowStr = ISO8601DateFormatter().string(from: Date())
        
        sqlite3_bind_text(stmt, 1, "last_sync_date", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, nowStr, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        sqlite3_reset(stmt)

        sqlite3_bind_text(stmt, 1, "total_messages", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, String(totalMessages), -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
