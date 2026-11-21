import Foundation
import Contacts
import SQLite3

public final class ContactResolver: @unchecked Sendable {
    public static let shared = ContactResolver()

    private let store = CNContactStore()
    private let lock = NSLock()
    private var phoneCache: [String: String] = [:]
    private var emailCache: [String: String] = [:]
    private var avatarCache: [String: Data] = [:]
    private var isIndexed = false

    public init() {
        // Automatically warm cache from local AddressBook database on init
        warmCache()
    }

    public func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    public func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestAccess(for: .contacts)
            if granted {
                enrichFromCNContacts()
            }
            return granted
        } catch {
            return false
        }
    }

    public func warmCache() {
        lock.lock()
        defer { lock.unlock() }
        guard !isIndexed else { return }

        // 1. Direct read from AddressBook SQLite databases (fast, ~30ms, no permission prompt needed under FDA)
        indexLocalAddressBookDatabases()

        // 2. Also check CNContactStore if authorized
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized {
            enrichFromCNContacts()
        }

        isIndexed = true
    }

    private func indexLocalAddressBookDatabases() {
        let fm = FileManager.default
        let abDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AddressBook")
        guard fm.fileExists(atPath: abDir.path) else { return }

        // Root database
        let rootDb = abDir.appendingPathComponent("AddressBook-v22.abcddb")
        if fm.fileExists(atPath: rootDb.path) {
            indexSingleAddressBookDatabase(rootDb)
        }

        // Source subdirectories (iCloud, Exchange, Google accounts)
        let sourcesDir = abDir.appendingPathComponent("Sources")
        if let subdirs = try? fm.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil) {
            for dir in subdirs {
                let dbPath = dir.appendingPathComponent("AddressBook-v22.abcddb")
                if fm.fileExists(atPath: dbPath.path) {
                    indexSingleAddressBookDatabase(dbPath)
                }
            }
        }
    }

    private func indexSingleAddressBookDatabase(_ url: URL) {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }

        // Query phones
        let phoneQuery = """
        SELECT r.ZFIRSTNAME, r.ZLASTNAME, r.ZNICKNAME, r.ZORGANIZATION, p.ZFULLNUMBER 
        FROM ZABCDRECORD r 
        JOIN ZABCDPHONENUMBER p ON r.Z_PK = p.ZOWNER;
        """

        var phoneStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, phoneQuery, -1, &phoneStmt, nil) == SQLITE_OK {
            while sqlite3_step(phoneStmt) == SQLITE_ROW {
                let first = phoneStmt != nil && sqlite3_column_text(phoneStmt, 0) != nil ? String(cString: sqlite3_column_text(phoneStmt, 0)) : ""
                let last = phoneStmt != nil && sqlite3_column_text(phoneStmt, 1) != nil ? String(cString: sqlite3_column_text(phoneStmt, 1)) : ""
                let nick = phoneStmt != nil && sqlite3_column_text(phoneStmt, 2) != nil ? String(cString: sqlite3_column_text(phoneStmt, 2)) : ""
                let org = phoneStmt != nil && sqlite3_column_text(phoneStmt, 3) != nil ? String(cString: sqlite3_column_text(phoneStmt, 3)) : ""
                let phone = phoneStmt != nil && sqlite3_column_text(phoneStmt, 4) != nil ? String(cString: sqlite3_column_text(phoneStmt, 4)) : ""

                let name = makeContactName(first: first, last: last, nick: nick, org: org)
                guard !name.isEmpty, !phone.isEmpty else { continue }

                let digits = phone.filter { $0.isNumber }
                if !digits.isEmpty {
                    phoneCache[digits] = name
                    // Also index 10-digit standard if it starts with 1
                    if digits.count == 11 && digits.hasPrefix("1") {
                        let ten = String(digits.dropFirst())
                        phoneCache[ten] = name
                    }
                }
            }
            sqlite3_finalize(phoneStmt)
        }

        // Query emails
        let emailQuery = """
        SELECT r.ZFIRSTNAME, r.ZLASTNAME, r.ZNICKNAME, r.ZORGANIZATION, e.ZADDRESS 
        FROM ZABCDRECORD r 
        JOIN ZABCDEMAILADDRESS e ON r.Z_PK = e.ZOWNER;
        """

        var emailStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, emailQuery, -1, &emailStmt, nil) == SQLITE_OK {
            while sqlite3_step(emailStmt) == SQLITE_ROW {
                let first = emailStmt != nil && sqlite3_column_text(emailStmt, 0) != nil ? String(cString: sqlite3_column_text(emailStmt, 0)) : ""
                let last = emailStmt != nil && sqlite3_column_text(emailStmt, 1) != nil ? String(cString: sqlite3_column_text(emailStmt, 1)) : ""
                let nick = emailStmt != nil && sqlite3_column_text(emailStmt, 2) != nil ? String(cString: sqlite3_column_text(emailStmt, 2)) : ""
                let org = emailStmt != nil && sqlite3_column_text(emailStmt, 3) != nil ? String(cString: sqlite3_column_text(emailStmt, 3)) : ""
                let email = emailStmt != nil && sqlite3_column_text(emailStmt, 4) != nil ? String(cString: sqlite3_column_text(emailStmt, 4)) : ""

                let name = makeContactName(first: first, last: last, nick: nick, org: org)
                let cleanedEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !cleanedEmail.isEmpty else { continue }

                emailCache[cleanedEmail] = name
            }
            sqlite3_finalize(emailStmt)
        }
    }

    private func makeContactName(first: String, last: String, nick: String, org: String) -> String {
        var fullName = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        if fullName.isEmpty {
            fullName = nick.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if fullName.isEmpty {
            fullName = org.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fullName
    }

    private func enrichFromCNContacts() {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        do {
            try store.enumerateContacts(with: request) { [weak self] contact, _ in
                guard let self = self else { return }
                var name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                if name.isEmpty { name = contact.nickname }
                if name.isEmpty { name = contact.organizationName }
                guard !name.isEmpty else { return }

                for phone in contact.phoneNumbers {
                    let digits = phone.value.stringValue.filter { $0.isNumber }
                    if !digits.isEmpty {
                        self.phoneCache[digits] = name
                        if digits.count == 11 && digits.hasPrefix("1") {
                            self.phoneCache[String(digits.dropFirst())] = name
                        }
                        if let thumb = contact.thumbnailImageData {
                            self.avatarCache[digits] = thumb
                        }
                    }
                }

                for email in contact.emailAddresses {
                    let lower = (email.value as String).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lower.isEmpty {
                        self.emailCache[lower] = name
                        if let thumb = contact.thumbnailImageData {
                            self.avatarCache[lower] = thumb
                        }
                    }
                }
            }
        } catch {
            // Non-fatal
        }
    }

    public func resolve(address: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return address }

        if trimmed.contains("@") {
            let lower = trimmed.lowercased()
            if let cached = emailCache[lower] { return cached }
            return trimmed
        }

        let digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty else { return address }

        // 1. Direct match on full digits
        if let cached = phoneCache[digits] { return cached }

        // 2. 10-digit match (strip leading 1)
        if digits.count == 11 && digits.hasPrefix("1") {
            let ten = String(digits.dropFirst())
            if let cached = phoneCache[ten] { return cached }
        }

        // 3. Last 10 digits match
        if digits.count > 10 {
            let lastTen = String(digits.suffix(10))
            if let cached = phoneCache[lastTen] { return cached }
        }

        // Fallback: pretty formatted phone number
        return Self.prettyPrintPhone(trimmed)
    }

    public func avatarData(for address: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") {
            return avatarCache[trimmed.lowercased()]
        }
        let digits = trimmed.filter { $0.isNumber }
        if let data = avatarCache[digits] { return data }
        if digits.count == 11 && digits.hasPrefix("1") {
            return avatarCache[String(digits.dropFirst())]
        }
        return nil
    }

    public static func normalizePhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count > 10 && digits.hasPrefix("1") {
            return String(digits.dropFirst())
        }
        return digits
    }

    public static func prettyPrintPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count == 10 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(mid)-\(last)"
        }
        if digits.count == 11 && digits.hasPrefix("1") {
            let rest = digits.dropFirst()
            let area = rest.prefix(3)
            let mid = rest.dropFirst(3).prefix(3)
            let last = rest.suffix(4)
            return "+1 (\(area)) \(mid)-\(last)"
        }
        return phone
    }
}
