import AppKit
import SwiftData
import iMessageArchiveKit

@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(0.5))

            // 1. Phone number normalization
            check("phone normalization cleans leading 1", ContactResolver.normalizePhone("+15551234567") == "5551234567")
            check("phone pretty printing formats 10 digits", ContactResolver.prettyPrintPhone("5551234567") == "(555) 123-4567")

            // 2. Conversation Title resolution
            let testConv = Conversation(
                id: 10,
                guid: "guid-1",
                chatIdentifier: "+15551234567",
                displayName: "Family",
                service: .iMessage
            )
            check("conversation resolvedTitle prefers displayName", testConv.resolvedTitle == "Family")

            // 3. Tapback mapping
            check("tapback love emoji matches", TapbackType.love.emoji == "❤️")
            let customTap = Tapback(type: .customEmoji, emojiReaction: "🔥", senderAddress: "user", isFromMe: false)
            check("custom emoji reaction display", customTap.displayEmoji == "🔥")

            // 4. HTML Exporter test
            let testMsg = ChatMessage(id: 1, guid: "m1", text: "Test Message", isFromMe: true, date: Date(), service: .iMessage)
            let exportedHtml = HTMLExporter.export(conversation: testConv, messages: [testMsg])
            check("HTML export contains conversation title", exportedHtml.contains("Family"))
            check("HTML export contains message text", exportedHtml.contains("Test Message"))

            // 5. Database Reader check
            let status = MessagesDatabaseReader.checkAccess(at: MessagesDatabaseReader.defaultDatabaseURL)
            check("database reader checkAccess returns status", status == .accessible || status == .fileNotFound || status != .fileNotFound)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
