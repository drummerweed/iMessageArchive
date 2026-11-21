import AppKit
import SwiftData
import SwiftUI
import iMessageArchiveKit

@main
struct iMessageArchiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("iMessageArchive", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 840, minHeight: 520)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Run Archive Now") {
                    model.runArchiveNow()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Export Selected to HTML...") {
                    if let conv = model.selectedConversation {
                        model.exportHTML(conversation: conv)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button("Export Selected to PDF...") {
                    if let conv = model.selectedConversation {
                        model.exportPDF(conversation: conv)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--archive-background") {
            runBackgroundArchiveAndExit()
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    private func runBackgroundArchiveAndExit() {
        Task.detached {
            let reader = MessagesDatabaseReader(databaseURL: MessagesDatabaseReader.defaultDatabaseURL)
            let engine = ArchiveEngine(sourceReader: reader)
            let plan = ArchivePlan(name: "Scheduled Backup", archiveAll: true, destinationPath: "~/Documents/iMessageArchive")
            do {
                _ = try await engine.execute(plan: plan) { _ in }
                exit(0)
            } catch {
                exit(1)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

enum Store {
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let custom = ProcessInfo.processInfo.environment["APP_STORE"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iMessageArchive", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("iMessageArchive.store")
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedArchivePlan.self])
        let config = ModelConfiguration(schema: schema, url: url)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
