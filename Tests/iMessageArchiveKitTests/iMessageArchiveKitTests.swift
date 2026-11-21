import Foundation
import Testing
@testable import iMessageArchiveKit

@Test("Apple timestamp conversion")
func testTimestampConversion() {
    // 0 in Apple epoch is 2001-01-01 00:00:00 UTC
    let d0 = MessagesDatabaseReader.convertDate(0)
    let comp0 = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: d0)
    #expect(comp0.year == 2001)
    #expect(comp0.month == 1)
    #expect(comp0.day == 1)

    // Test nanosecond timestamp
    // 700000000000000000 ns = 700,000,000 seconds since 2001-01-01
    let dNano = MessagesDatabaseReader.convertDate(700_000_000_000_000_000)
    let expectedSeconds = Date(timeIntervalSinceReferenceDate: 700_000_000)
    #expect(abs(dNano.timeIntervalSince1970 - expectedSeconds.timeIntervalSince1970) < 1.0)
}

@Test("Phone number normalization and pretty printing", arguments: [
    ("+15551234567", "5551234567", "+1 (555) 123-4567"),
    ("5551234567", "5551234567", "(555) 123-4567"),
    ("1-555-123-4567", "5551234567", "+1 (555) 123-4567"),
])
func testPhoneFormatting(input: String, expectedDigits: String, expectedPretty: String) {
    #expect(ContactResolver.normalizePhone(input) == expectedDigits)
    #expect(ContactResolver.prettyPrintPhone(input) == expectedPretty)
}

@Test("Associated message GUID normalization")
func testGuidNormalization() {
    let pGuid = "p:0/AB15FDFC-5E7C-4B87-832B-30F77C1DAD2D"
    #expect(MessagesDatabaseReader.normalizeAssociatedGuid(pGuid) == "AB15FDFC-5E7C-4B87-832B-30F77C1DAD2D")

    let bpGuid = "bp:AB15FDFC-5E7C-4B87-832B-30F77C1DAD2D"
    #expect(MessagesDatabaseReader.normalizeAssociatedGuid(bpGuid) == "AB15FDFC-5E7C-4B87-832B-30F77C1DAD2D")

    let rawGuid = "AB15FDFC-5E7C-4B87-832B-30F77C1DAD2D"
    #expect(MessagesDatabaseReader.normalizeAssociatedGuid(rawGuid) == "AB15FDFC-5E7C-4B87-832B-30F77C1DAD2D")
}

@Test("Tapback emoji & symbol representations")
func testTapbacks() {
    #expect(TapbackType.love.emoji == "❤️")
    #expect(TapbackType.like.emoji == "👍")
    #expect(TapbackType.dislike.emoji == "👎")
    #expect(TapbackType.laugh.emoji == "😆")
    #expect(TapbackType.emphasize.emoji == "‼️")
    #expect(TapbackType.question.emoji == "❓")

    let customTap = Tapback(type: .customEmoji, emojiReaction: "🔥", senderAddress: "test@example.com", isFromMe: false)
    #expect(customTap.displayEmoji == "🔥")
}

@Test("HTML Exporter output contains elements")
func testHTMLExporter() {
    let conv = Conversation(
        id: 1,
        guid: "iMessage;-;+15551234567",
        chatIdentifier: "+15551234567",
        displayName: "John Appleseed",
        service: .iMessage
    )

    let msg1 = ChatMessage(
        id: 100,
        guid: "msg-100",
        text: "Hello from iMessageArchive!",
        isFromMe: false,
        date: Date(),
        service: .iMessage,
        senderName: "John"
    )

    let msg2 = ChatMessage(
        id: 101,
        guid: "msg-101",
        text: "This is a reply.",
        isFromMe: true,
        date: Date().addingTimeInterval(60),
        service: .iMessage
    )

    let html = HTMLExporter.export(conversation: conv, messages: [msg1, msg2])
    #expect(html.contains("John Appleseed"))
    #expect(html.contains("Hello from iMessageArchive!"))
    #expect(html.contains("This is a reply."))
    #expect(html.contains("filterMessages"))
}
