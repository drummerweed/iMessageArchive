import Foundation
import SwiftData
import iMessageArchiveKit

@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" || Store.isOverridden else { return }

        // Populate generic mock conversations for snapshot testing (100% fictional data)
        let conv1 = Conversation(
            id: 101,
            guid: "iMessage;-;+15550192834",
            chatIdentifier: "+15550192834",
            displayName: "Alex Morgan",
            service: .iMessage,
            participants: [Handle(id: 1, address: "+15550192834", service: .iMessage, contactName: "Alex Morgan")],
            messageCount: 42,
            lastMessageDate: Date().addingTimeInterval(-120),
            lastMessageSnippet: "Can you grab some groceries on the way home?"
        )

        let conv2 = Conversation(
            id: 102,
            guid: "any;+;chat123456789012345",
            chatIdentifier: "chat123456789012345",
            displayName: "Product Design Team",
            service: .iMessage,
            participants: [
                Handle(id: 2, address: "+15550149921", service: .iMessage, contactName: "Sarah"),
                Handle(id: 3, address: "+15550184720", service: .iMessage, contactName: "David"),
                Handle(id: 4, address: "+15550123345", service: .iMessage, contactName: "Chris")
            ],
            messageCount: 154,
            lastMessageDate: Date().addingTimeInterval(-3600),
            lastMessageSnippet: "The latest mockups for the dashboard look great!"
        )

        let conv3 = Conversation(
            id: 103,
            guid: "SMS;-;+15550149921",
            chatIdentifier: "+15550149921",
            displayName: "Jordan Smith",
            service: .sms,
            participants: [Handle(id: 5, address: "+15550149921", service: .sms, contactName: "Jordan Smith")],
            messageCount: 18,
            lastMessageDate: Date().addingTimeInterval(-86400),
            lastMessageSnippet: "Looking forward to catching up this weekend."
        )

        let conv4 = Conversation(
            id: 104,
            guid: "iMessage;-;+15550184720",
            chatIdentifier: "+15550184720",
            displayName: "Taylor Reed",
            service: .iMessage,
            participants: [Handle(id: 6, address: "+15550184720", service: .iMessage, contactName: "Taylor Reed")],
            messageCount: 89,
            lastMessageDate: Date().addingTimeInterval(-172800),
            lastMessageSnippet: "Sent over the project brief."
        )

        let conv5 = Conversation(
            id: 105,
            guid: "any;+;chat987654321098765",
            chatIdentifier: "chat987654321098765",
            displayName: "Weekend Hiking Club",
            service: .iMessage,
            participants: [
                Handle(id: 7, address: "+15550112233", service: .iMessage, contactName: "Sam"),
                Handle(id: 8, address: "+15550199887", service: .iMessage, contactName: "Maya")
            ],
            messageCount: 230,
            lastMessageDate: Date().addingTimeInterval(-259200),
            lastMessageSnippet: "Trailhead meetup at 8:00 AM on Saturday."
        )

        model.conversations = [conv1, conv2, conv3, conv4, conv5]
        model.selectedConversation = conv1

        let msg1 = ChatMessage(
            id: 1,
            guid: "m-001",
            text: "Hey! Are you heading back from the office soon?",
            isFromMe: false,
            date: Date().addingTimeInterval(-600),
            service: .iMessage,
            senderName: "Alex"
        )

        let msg2 = ChatMessage(
            id: 2,
            guid: "m-002",
            text: "Just wrapping up the last commit, leaving in 10 minutes!",
            isFromMe: true,
            date: Date().addingTimeInterval(-500),
            service: .iMessage,
            tapbacks: [Tapback(type: .love, emojiReaction: "❤️", senderAddress: "+15550192834", isFromMe: false)]
        )

        let msg3 = ChatMessage(
            id: 3,
            guid: "m-003",
            text: "Awesome! Can you grab some groceries on the way home?",
            isFromMe: false,
            date: Date().addingTimeInterval(-120),
            service: .iMessage,
            senderName: "Alex",
            tapbacks: [Tapback(type: .like, emojiReaction: "👍", senderAddress: "", isFromMe: true)]
        )

        let msg4 = ChatMessage(
            id: 4,
            guid: "m-004",
            text: "Sure thing, grabbed some apples and coffee beans.",
            isFromMe: true,
            date: Date().addingTimeInterval(-60),
            service: .iMessage
        )

        model.messages = [msg1, msg2, msg3, msg4]
    }
}
