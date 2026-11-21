import Foundation
import SwiftData
import SwiftUI
import AppKit
import iMessageArchiveKit

@Model
final class SavedArchivePlan {
    var id: UUID = UUID()
    var name: String
    var archiveAll: Bool = true
    var destinationPath: String = "~/Documents/iMessageArchive"
    var lastArchivedDate: Date? = nil
    var includeAttachments: Bool = true

    init(name: String, archiveAll: Bool = true, destinationPath: String = "~/Documents/iMessageArchive") {
        self.name = name
        self.archiveAll = archiveAll
        self.destinationPath = destinationPath
    }
}

public enum SidebarItem: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case imessage = "imessage"
    case sms = "sms"
    case attachments = "attachments"
    case plans = "plans"
    case schedules = "schedules"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All Messages"
        case .imessage: return "iMessage"
        case .sms: return "SMS & RCS"
        case .attachments: return "Media & Files"
        case .plans: return "Archive Plans"
        case .schedules: return "Auto Schedules"
        }
    }

    public var symbol: String {
        switch self {
        case .all: return "bubble.left.and.bubble.right.fill"
        case .imessage: return "message.fill"
        case .sms: return "antenna.radiowaves.left.and.right"
        case .attachments: return "paperclip"
        case .plans: return "archivebox.fill"
        case .schedules: return "clock.arrow.circlepath"
        }
    }
}

@Observable
final class AppModel: @unchecked Sendable {
    let container: ModelContainer

    var sidebar: SidebarItem? = .all
    var searchQuery: String = ""
    var filterHasAttachments: Bool = false

    var conversations: [Conversation] = []
    var selectedConversation: Conversation? = nil
    var messages: [ChatMessage] = []

    var isLoadingConversations: Bool = false
    var isLoadingMessages: Bool = false
    var databaseAccessStatus: DatabaseAccessStatus = .accessible

    var activeDatabaseURL: URL = MessagesDatabaseReader.defaultDatabaseURL
    var isArchiving: Bool = false
    var archiveProgress: ArchiveProgress? = nil

    var isScheduled: Bool = SchedulerManager.isScheduled()
    var scheduledHour: Int = 2
    var scheduledMinute: Int = 0

    var toastMessage: String? = nil

    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet {
            if !Store.isOverridden {
                UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab")
            }
        }
    }

    init(container: ModelContainer) {
        self.container = container
        self.isScheduled = SchedulerManager.isScheduled()
    }

    @MainActor
    func refresh() async {
        if ProcessInfo.processInfo.environment["APP_SEED"] == "1" || Store.isOverridden {
            // Snapshot / seed mode: NEVER read real user database
            return
        }

        isLoadingConversations = true
        defer { isLoadingConversations = false }

        databaseAccessStatus = MessagesDatabaseReader.checkAccess(at: activeDatabaseURL)
        guard databaseAccessStatus == .accessible else {
            conversations = []
            return
        }

        ContactResolver.shared.warmCache()
        _ = await ContactResolver.shared.requestAccess()

        do {
            let reader = MessagesDatabaseReader(databaseURL: activeDatabaseURL)
            var loaded = try reader.fetchConversations()

            // Resolve contact names
            for i in 0..<loaded.count {
                for j in 0..<loaded[i].participants.count {
                    let addr = loaded[i].participants[j].address
                    loaded[i].participants[j].contactName = ContactResolver.shared.resolve(address: addr)
                }
                if loaded[i].displayName == nil || loaded[i].displayName?.isEmpty == true {
                    if loaded[i].participants.isEmpty {
                        let name = ContactResolver.shared.resolve(address: loaded[i].chatIdentifier)
                        loaded[i].participants.append(Handle(id: 0, address: loaded[i].chatIdentifier, service: loaded[i].service, contactName: name))
                    }
                }
            }

            self.conversations = loaded
            if selectedConversation == nil, let first = loaded.first {
                selectConversation(first)
            }
        } catch {
            conversations = []
        }
    }

    @MainActor
    func selectConversation(_ conv: Conversation) {
        self.selectedConversation = conv
        loadMessages(for: conv)
    }

    @MainActor
    func loadMessages(for conv: Conversation) {
        if ProcessInfo.processInfo.environment["APP_SEED"] == "1" || Store.isOverridden {
            // Snapshot / seed mode: keep mock messages populated by SeedData
            return
        }

        isLoadingMessages = true
        let reader = MessagesDatabaseReader(databaseURL: activeDatabaseURL)
        
        Task.detached {
            do {
                var msgs = try reader.fetchMessages(chatId: conv.id, limit: 1500)
                for i in 0..<msgs.count {
                    if !msgs[i].isFromMe && !msgs[i].senderAddress.isEmpty {
                        msgs[i].senderName = ContactResolver.shared.resolve(address: msgs[i].senderAddress)
                    }
                }
                await MainActor.run {
                    self.messages = msgs
                    self.isLoadingMessages = false
                }
            } catch {
                await MainActor.run {
                    self.messages = []
                    self.isLoadingMessages = false
                }
            }
        }
    }

    @MainActor
    func runArchiveNow() {
        guard !isArchiving else { return }
        isArchiving = true

        let reader = MessagesDatabaseReader(databaseURL: activeDatabaseURL)
        let engine = ArchiveEngine(sourceReader: reader)
        let plan = ArchivePlan(
            name: "Default Full Backup",
            archiveAll: true,
            destinationPath: "~/Documents/iMessageArchive"
        )

        Task.detached {
            do {
                _ = try await engine.execute(plan: plan) { progress in
                    Task { @MainActor in
                        self.archiveProgress = progress
                    }
                }
                await MainActor.run {
                    self.isArchiving = false
                    self.toastMessage = "Archive successfully completed to ~/Documents/iMessageArchive!"
                }
            } catch {
                await MainActor.run {
                    self.isArchiving = false
                    self.toastMessage = "Archive error: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    func exportHTML(conversation: Conversation) {
        let msgs = self.messages
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.html]
        savePanel.nameFieldStringValue = "\(conversation.resolvedTitle).html"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let html = HTMLExporter.export(conversation: conversation, messages: msgs)
            try? html.write(to: url, atomically: true, encoding: .utf8)
            self.toastMessage = "Exported to \(url.lastPathComponent)"
        }
    }

    @MainActor
    func exportPDF(conversation: Conversation) {
        let msgs = self.messages
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(conversation.resolvedTitle).pdf"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try PDFExporter.export(conversation: conversation, messages: msgs, to: url)
                self.toastMessage = "PDF exported to \(url.lastPathComponent)"
            } catch {
                self.toastMessage = "PDF export error: \(error.localizedDescription)"
            }
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    func chooseCustomDatabase() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select chat.db"

        if panel.runModal() == .OK, let chosen = panel.url {
            var target = chosen
            if (try? chosen.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                target = chosen.appendingPathComponent("chat.db")
            }
            activeDatabaseURL = target
            Task {
                await refresh()
            }
        }
    }

    @MainActor
    func toggleSchedule() {
        if isScheduled {
            SchedulerManager.removeSchedule()
            isScheduled = false
            toastMessage = "Background schedule disabled."
        } else {
            do {
                try SchedulerManager.installSchedule(hour: scheduledHour, minute: scheduledMinute)
                isScheduled = true
                toastMessage = "Background schedule activated for \(scheduledHour):00 daily."
            } catch {
                toastMessage = "Failed to install schedule: \(error.localizedDescription)"
            }
        }
    }
}
