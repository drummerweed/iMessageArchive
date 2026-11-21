import Foundation

public struct HTMLExportOptions: Sendable {
    public var embedImagesAsBase64: Bool
    public var includeTapbacks: Bool
    public var title: String?

    public init(embedImagesAsBase64: Bool = true, includeTapbacks: Bool = true, title: String? = nil) {
        self.embedImagesAsBase64 = embedImagesAsBase64
        self.includeTapbacks = includeTapbacks
        self.title = title
    }
}

public enum HTMLExporter {
    public static func export(
        conversation: Conversation,
        messages: [ChatMessage],
        options: HTMLExportOptions = HTMLExportOptions()
    ) -> String {
        let title = options.title ?? conversation.resolvedTitle
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(title)) - iMessageArchive Export</title>
            <style>
                :root {
                    --bg-color: #f5f5f7;
                    --text-color: #1d1d1f;
                    --header-bg: rgba(255, 255, 255, 0.85);
                    --imessage-bg: linear-gradient(135deg, #007aff, #0051d5);
                    --sms-bg: linear-gradient(135deg, #34c759, #248a3d);
                    --received-bg: #e5e5ea;
                    --received-text: #000000;
                    --sent-text: #ffffff;
                    --time-color: #8e8e93;
                    --bubble-border: transparent;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg-color: #1c1c1e;
                        --text-color: #f2f2f7;
                        --header-bg: rgba(44, 44, 46, 0.85);
                        --imessage-bg: linear-gradient(135deg, #0a84ff, #0062cc);
                        --sms-bg: linear-gradient(135deg, #30d158, #208b3a);
                        --received-bg: #2c2c2e;
                        --received-text: #ffffff;
                        --sent-text: #ffffff;
                        --time-color: #98989d;
                    }
                }
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: var(--bg-color);
                    color: var(--text-color);
                }
                .header-bar {
                    position: sticky;
                    top: 0;
                    backdrop-filter: blur(20px);
                    -webkit-backdrop-filter: blur(20px);
                    background: var(--header-bg);
                    padding: 16px 24px;
                    border-bottom: 1px solid rgba(128, 128, 128, 0.2);
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    z-index: 100;
                }
                .header-info h1 {
                    margin: 0;
                    font-size: 1.25rem;
                    font-weight: 600;
                }
                .header-info p {
                    margin: 4px 0 0 0;
                    font-size: 0.85rem;
                    color: var(--time-color);
                }
                .search-input {
                    padding: 8px 14px;
                    border-radius: 20px;
                    border: 1px solid rgba(128, 128, 128, 0.3);
                    background: var(--bg-color);
                    color: var(--text-color);
                    font-size: 0.9rem;
                    outline: none;
                }
                .chat-container {
                    max-width: 720px;
                    margin: 0 auto;
                    padding: 24px 16px;
                    display: flex;
                    flex-direction: column;
                    gap: 12px;
                }
                .message-row {
                    display: flex;
                    flex-direction: column;
                    margin-bottom: 4px;
                }
                .message-row.sent {
                    align-items: flex-end;
                }
                .message-row.received {
                    align-items: flex-start;
                }
                .sender-label {
                    font-size: 0.75rem;
                    color: var(--time-color);
                    margin-bottom: 4px;
                    margin-left: 12px;
                }
                .bubble-wrapper {
                    position: relative;
                    max-width: 75%;
                }
                .bubble {
                    padding: 10px 16px;
                    border-radius: 18px;
                    font-size: 0.95rem;
                    line-height: 1.4;
                    word-wrap: break-word;
                    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
                }
                .message-row.sent .bubble.imessage {
                    background: var(--imessage-bg);
                    color: var(--sent-text);
                    border-bottom-right-radius: 4px;
                }
                .message-row.sent .bubble.sms {
                    background: var(--sms-bg);
                    color: var(--sent-text);
                    border-bottom-right-radius: 4px;
                }
                .message-row.received .bubble {
                    background: var(--received-bg);
                    color: var(--received-text);
                    border-bottom-left-radius: 4px;
                }
                .message-time {
                    font-size: 0.7rem;
                    color: var(--time-color);
                    margin-top: 4px;
                    padding: 0 4px;
                }
                .tapback-pill {
                    position: absolute;
                    top: -10px;
                    font-size: 0.85rem;
                    background: var(--bg-color);
                    border: 1px solid rgba(128, 128, 128, 0.25);
                    border-radius: 12px;
                    padding: 2px 6px;
                    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                }
                .message-row.sent .tapback-pill {
                    left: -8px;
                }
                .message-row.received .tapback-pill {
                    right: -8px;
                }
                .attachment-preview {
                    margin-top: 6px;
                    max-width: 100%;
                    border-radius: 12px;
                    overflow: hidden;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.15);
                }
                .attachment-preview img {
                    max-width: 100%;
                    display: block;
                    border-radius: 12px;
                }
                .attachment-card {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    background: rgba(128, 128, 128, 0.15);
                    padding: 8px 12px;
                    border-radius: 8px;
                    font-size: 0.85rem;
                    margin-top: 4px;
                }
            </style>
        </head>
        <body>
            <div class="header-bar">
                <div class="header-info">
                    <h1>\(escapeHTML(title))</h1>
                    <p>\(messages.count) messages · Service: \(conversation.service.rawValue) · Exported on \(dateFormatter.string(from: Date()))</p>
                </div>
                <input type="text" id="filterInput" class="search-input" placeholder="Search in conversation..." onkeyup="filterMessages()">
            </div>
            <div class="chat-container" id="chatContainer">
        """

        for msg in messages {
            let rowClass = msg.isFromMe ? "sent" : "received"
            let svcClass = msg.service == .sms ? "sms" : "imessage"
            let timeStr = dateFormatter.string(from: msg.date)

            html += """
                <div class="message-row \(rowClass)" data-text="\(escapeHTML(msg.cleanText.lowercased()))">
            """

            if !msg.isFromMe, let sName = msg.senderName, !sName.isEmpty {
                html += """
                    <span class="sender-label">\(escapeHTML(sName))</span>
                """
            }

            html += """
                    <div class="bubble-wrapper">
            """

            if options.includeTapbacks && !msg.tapbacks.isEmpty {
                let emojis = msg.tapbacks.map(\.displayEmoji).joined(separator: " ")
                html += """
                        <div class="tapback-pill">\(emojis)</div>
                """
            }

            if !msg.cleanText.isEmpty {
                html += """
                        <div class="bubble \(svcClass)">\(escapeHTML(msg.cleanText))</div>
                """
            }

            // Render attachments
            for att in msg.attachments {
                if att.isImage, let url = att.resolvedURL {
                    if options.embedImagesAsBase64, let data = try? Data(contentsOf: url) {
                        let mime = att.mimeType ?? "image/jpeg"
                        let b64 = data.base64EncodedString()
                        html += """
                        <div class="attachment-preview">
                            <img src="data:\(mime);base64,\(b64)" alt="attachment" />
                        </div>
                        """
                    } else {
                        html += """
                        <div class="attachment-preview">
                            <img src="\(url.absoluteString)" alt="attachment" />
                        </div>
                        """
                    }
                } else {
                    let name = att.transferName ?? (att.filename as NSString).lastPathComponent
                    html += """
                    <div class="attachment-card">
                        <span>📎</span>
                        <span>\(escapeHTML(name.isEmpty ? "Attachment" : name))</span>
                    </div>
                    """
                }
            }

            html += """
                        <div class="message-time">\(timeStr)</div>
                    </div>
                </div>
            """
        }

        html += """
            </div>
            <script>
                function filterMessages() {
                    const query = document.getElementById('filterInput').value.toLowerCase();
                    const rows = document.querySelectorAll('.message-row');
                    rows.forEach(row => {
                        const text = row.getAttribute('data-text') || '';
                        if (!query || text.includes(query)) {
                            row.style.display = 'flex';
                        } else {
                            row.style.display = 'none';
                        }
                    });
                }
            </script>
        </body>
        </html>
        """

        return html
    }

    private static func escapeHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        result = result.replacingOccurrences(of: "\n", with: "<br>")
        return result
    }
}
