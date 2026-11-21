import Foundation
import AppKit

public enum PDFExporter {
    public static func export(
        conversation: Conversation,
        messages: [ChatMessage],
        to fileURL: URL
    ) throws {
        let pageWidth: CGFloat = 612.0
        let pageHeight: CGFloat = 792.0
        let margin: CGFloat = 36.0
        let contentWidth = pageWidth - (margin * 2)

        var pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(url: fileURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw NSError(domain: "iMessageArchive.PDFExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF context"])
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var pageNumber = 1

        func startNewPage() {
            context.beginPage(mediaBox: &pageRect)
            
            // Draw page header
            let headerText = "\(conversation.resolvedTitle) — Page \(pageNumber)"
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let headerString = NSAttributedString(string: headerText, attributes: headerAttrs)
            headerString.draw(at: CGPoint(x: margin, y: pageHeight - 26))

            // Draw line below header
            context.setStrokeColor(NSColor.separatorColor.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: pageHeight - 30))
            context.addLine(to: CGPoint(x: pageWidth - margin, y: pageHeight - 30))
            context.strokePath()
        }

        func finishPage() {
            context.endPage()
            pageNumber += 1
        }

        startNewPage()
        var currentY: CGFloat = pageHeight - 48

        // Draw title on first page
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor
        ]
        let titleString = NSAttributedString(string: conversation.resolvedTitle, attributes: titleAttrs)
        titleString.draw(at: CGPoint(x: margin, y: currentY - 20))
        currentY -= 30

        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let metaString = NSAttributedString(string: "\(messages.count) messages · Service: \(conversation.service.rawValue) · Exported: \(dateFormatter.string(from: Date()))", attributes: metaAttrs)
        metaString.draw(at: CGPoint(x: margin, y: currentY - 14))
        currentY -= 26

        let bubbleMaxWidth: CGFloat = contentWidth * 0.72

        for msg in messages {
            let text = msg.cleanText
            let timeStr = dateFormatter.string(from: msg.date)
            let isSent = msg.isFromMe

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: isSent ? NSColor.white : NSColor.labelColor
            ]
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor.secondaryLabelColor
            ]

            let displayText = text.isEmpty && !msg.attachments.isEmpty ? "[Attachment]" : text
            let textBounding = (displayText as NSString).boundingRect(
                with: CGSize(width: bubbleMaxWidth - 20, height: 1000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: textAttrs
            )

            let bubbleWidth = max(textBounding.width + 20, 80)
            let bubbleHeight = textBounding.height + 16
            let totalRowHeight = bubbleHeight + 18 // including timestamp

            // Check if we need a new page
            if currentY - totalRowHeight < margin + 20 {
                finishPage()
                startNewPage()
                currentY = pageHeight - 48
            }

            let bubbleX = isSent ? (pageWidth - margin - bubbleWidth) : margin
            let bubbleRect = CGRect(x: bubbleX, y: currentY - bubbleHeight, width: bubbleWidth, height: bubbleHeight)

            // Draw bubble
            context.saveGState()
            let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 12, yRadius: 12)
            if isSent {
                if msg.service == .sms {
                    NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0).setFill()
                } else {
                    NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0).setFill()
                }
            } else {
                NSColor(white: 0.90, alpha: 1.0).setFill()
            }
            path.fill()
            context.restoreGState()

            // Draw message text
            let textDrawRect = CGRect(x: bubbleX + 10, y: currentY - bubbleHeight + 8, width: textBounding.width, height: textBounding.height)
            (displayText as NSString).draw(in: textDrawRect, withAttributes: textAttrs)

            // Draw timestamp
            let timeString = NSAttributedString(string: timeStr, attributes: timeAttrs)
            let timeX = isSent ? (pageWidth - margin - timeString.size().width) : margin + 4
            timeString.draw(at: CGPoint(x: timeX, y: currentY - bubbleHeight - 12))

            currentY -= (totalRowHeight + 6)
        }

        finishPage()
        context.closePDF()
    }
}
