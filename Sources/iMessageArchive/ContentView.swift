import SwiftUI
import SwiftData
import iMessageArchiveKit
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            MiddleColumnView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 450)
        } detail: {
            DetailContentView()
        }
        .task {
            if ProcessInfo.processInfo.environment["APP_SEED"] == "1" || Store.isOverridden {
                SeedData.insertIfRequested(into: model)
            } else {
                await model.refresh()
            }
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
        .overlay(alignment: .bottom) {
            if model.isArchiving, let progress = model.archiveProgress {
                ArchivingProgressBanner(progress: progress)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let toast = model.toastMessage {
                ToastBanner(message: toast) {
                    model.toastMessage = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Section("Messages Library") {
                ForEach([SidebarItem.all, .imessage, .sms, .attachments]) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }

            Section("Automation & Tools") {
                ForEach([SidebarItem.plans, .schedules]) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }

            Section("Database Source") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(model.activeDatabaseURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Button("Change Source...") {
                        model.chooseCustomDatabase()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
    }

    private var statusColor: Color {
        switch model.databaseAccessStatus {
        case .accessible: return .green
        case .fileNotFound: return .yellow
        case .permissionDenied: return .red
        }
    }

    private var statusText: String {
        switch model.databaseAccessStatus {
        case .accessible: return "Live Messages DB Connected"
        case .fileNotFound: return "chat.db Not Found"
        case .permissionDenied: return "Permissions Required"
        }
    }
}

// MARK: - Middle Column (Conversations or Tool Views)

struct MiddleColumnView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.sidebar ?? .all {
        case .all, .imessage, .sms, .attachments:
            ConversationsListView()
        case .plans:
            PlansListView()
        case .schedules:
            SchedulesView()
        }
    }
}

struct ConversationsListView: View {
    @Environment(AppModel.self) private var model

    private var filteredConversations: [Conversation] {
        var list = model.conversations

        // Service filter
        if model.sidebar == .imessage {
            list = list.filter { $0.service == .iMessage }
        } else if model.sidebar == .sms {
            list = list.filter { $0.service == .sms || $0.service == .rcs }
        }

        // Search query
        let query = model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { conv in
                conv.resolvedTitle.lowercased().contains(query) ||
                (conv.lastMessageSnippet?.lowercased().contains(query) ?? false) ||
                conv.participants.contains(where: { $0.address.lowercased().contains(query) })
            }
        }

        return list
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.databaseAccessStatus != .accessible {
                PermissionRequiredCard()
                    .padding()
            } else {
                List(filteredConversations, selection: $model.selectedConversation) { conv in
                    ConversationRow(conversation: conv)
                        .tag(conv)
                }
                .listStyle(.inset)
                .overlay {
                    if filteredConversations.isEmpty && !model.isLoadingConversations {
                        ContentUnavailableView(
                            "No Conversations",
                            systemImage: "bubble.left.and.exclamationmark",
                            description: Text(model.searchQuery.isEmpty ? "No conversations found in database." : "No results matching \"\(model.searchQuery)\"")
                        )
                    }
                }
            }
        }
        .navigationTitle(model.sidebar?.title ?? "All Messages")
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Search people and messages...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.runArchiveNow()
                } label: {
                    Label("Archive All", systemImage: "arrow.down.doc.fill")
                }
                .disabled(model.isArchiving || model.databaseAccessStatus != .accessible)
                .help("Archive all conversations and media to ~/Documents/iMessageArchive")
            }
        }
        .onChange(of: model.selectedConversation) { _, newSelected in
            if let conv = newSelected {
                model.loadMessages(for: conv)
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            AvatarCircle(name: conversation.resolvedTitle, service: conversation.service)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.resolvedTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()

                    if let date = conversation.lastMessageDate {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(conversation.lastMessageSnippet ?? "\(conversation.messageCount) messages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(conversation.messageCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(serviceBadgeColor.opacity(0.15))
                        .foregroundStyle(serviceBadgeColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var serviceBadgeColor: Color {
        conversation.service == .sms ? .green : .blue
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.timeStyle = .short
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: date)
    }
}

struct AvatarCircle: View {
    let name: String
    let service: ServiceType

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: service == .sms ? [Color.green.opacity(0.8), Color.green] : [Color.blue.opacity(0.8), Color.blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 36, height: 36)

            Text(initials(name))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func initials(_ str: String) -> String {
        let parts = str.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return "\(first)\(second)".uppercased()
        }
        return String(str.prefix(1)).uppercased()
    }
}

// MARK: - Detail View

struct DetailContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.sidebar ?? .all {
        case .all, .imessage, .sms, .attachments:
            if let conv = model.selectedConversation {
                ThreadInspectorView(conversation: conv)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a conversation from the list to view its archived history, export to HTML, or generate a PDF.")
                )
            }
        case .plans:
            PlansDetailView()
        case .schedules:
            SchedulesDetailView()
        }
    }
}

struct ThreadInspectorView: View {
    @Environment(AppModel.self) private var model
    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                AvatarCircle(name: conversation.resolvedTitle, service: conversation.service)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.resolvedTitle)
                        .font(.headline)
                    Text("\(conversation.messageCount) messages · \(conversation.service.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.exportHTML(conversation: conversation)
                } label: {
                    Label("Export HTML", systemImage: "safari")
                }
                .help("Export standalone HTML file viewable in any browser with search")

                Button {
                    model.exportPDF(conversation: conversation)
                } label: {
                    Label("Export PDF", systemImage: "doc.text.fill")
                }
                .help("Export clean formatted PDF for legal/personal records")
            }
            .padding()
            .background(.bar)
            .dividerBottom()

            // Message History ScrollView
            if model.isLoadingMessages {
                ProgressView("Loading messages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.messages) { msg in
                                MessageBubbleRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .defaultScrollAnchor(.bottom)
                }
            }
        }
    }
}

struct MessageBubbleRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromMe { Spacer(minLength: 40) }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 3) {
                if !message.isFromMe, let name = message.senderName, !name.isEmpty {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }

                ZStack(alignment: message.isFromMe ? .topLeading : .topTrailing) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !message.cleanText.isEmpty {
                            Text(message.cleanText)
                                .font(.body)
                                .foregroundStyle(message.isFromMe ? .white : .primary)
                        }

                        // Attachments
                        ForEach(message.attachments) { att in
                            AttachmentItemView(attachment: att)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // Tapback reaction pills
                    if !message.tapbacks.isEmpty {
                        TapbackBadge(tapbacks: message.tapbacks)
                            .offset(x: message.isFromMe ? -10 : 10, y: -8)
                    }
                }

                Text(formatTimestamp(message.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }

            if !message.isFromMe { Spacer(minLength: 40) }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if message.isFromMe {
                if message.service == .sms {
                    LinearGradient(colors: [Color.green, Color(red: 0.18, green: 0.68, blue: 0.28)], startPoint: .top, endPoint: .bottom)
                } else {
                    LinearGradient(colors: [Color.blue, Color(red: 0.05, green: 0.42, blue: 0.9)], startPoint: .top, endPoint: .bottom)
                }
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

struct TapbackBadge: View {
    let tapbacks: [Tapback]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tapbacks) { tap in
                Text(tap.displayEmoji)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
    }
}

struct AttachmentItemView: View {
    let attachment: ChatAttachment

    var body: some View {
        if attachment.isImage, let url = attachment.resolvedURL, let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    NSWorkspace.shared.open(url)
                }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                Text(attachment.transferName ?? attachment.filename)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Automation & Settings Views

struct PlansListView: View {
    var body: some View {
        List {
            Section("Configured Plans") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Full Backup")
                        .font(.headline)
                    Text("Destination: ~/Documents/iMessageArchive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Includes all 2,423 conversations & attachments")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Archive Plans")
    }
}

struct PlansDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Archive Plan Settings") {
                Text("Default Backup Plan")
                    .font(.title3.bold())
                Text("Backs up all conversations and media attachments into a standalone SQLite archive directory.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LabeledContent("Destination Folder", value: "~/Documents/iMessageArchive")
                LabeledContent("Scope", value: "All Conversations")
                LabeledContent("Include Attachments", value: "Yes (Full Resolution Photos/Audio/Video)")

                Button("Run Plan Now") {
                    model.runArchiveNow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isArchiving)
            }
        }
        .formStyle(.grouped)
    }
}

struct SchedulesView: View {
    var body: some View {
        List {
            Section("LaunchAgent Schedules") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nightly Automated Archival")
                        .font(.headline)
                    Text("Daily at 02:00 AM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Auto Schedules")
    }
}

struct SchedulesDetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Background Scheduling") {
                Toggle("Enable Daily Background Archive", isOn: Binding(
                    get: { model.isScheduled },
                    set: { _ in model.toggleSchedule() }
                ))

                Text("When enabled, macOS launchd will automatically wake and run iMessageArchive in the background to sync newly received iMessage and SMS threads without any user interaction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Scheduled Time", value: "02:00 AM Daily")
                LabeledContent("LaunchAgent Identifier", value: SchedulerManager.agentLabel)
                LabeledContent("Status", value: model.isScheduled ? "Active (Registered with launchd)" : "Disabled")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Banner & Permissions

struct ArchivingProgressBanner: View {
    let progress: ArchiveProgress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress.percent)
                .frame(width: 140)

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.currentAction)
                    .font(.caption.bold())
                Text("\(Int(progress.percent * 100))% complete")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        .shadow(radius: 6)
    }
}

struct ToastBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        .shadow(radius: 6)
        .task {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
    }
}

struct PermissionRequiredCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("Full Disk Access Required")
                .font(.title2.bold())

            Text("macOS protects your Messages database (`~/Library/Messages/chat.db`) with Full Disk Access permissions. To archive your conversations, grant Full Disk Access to iMessageArchive in macOS System Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    model.openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Select Backup Folder...") {
                    model.chooseCustomDatabase()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func dividerBottom() -> some View {
        overlay(alignment: .bottom) {
            Divider()
        }
    }
}
