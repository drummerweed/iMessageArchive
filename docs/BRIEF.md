# iMessageArchive

A fast, modern native macOS app to archive, browse, search, and export Apple iMessage and SMS conversations locally from `chat.db`.

## Replaces
MAX Messages by Moth Software (replaces outdated Xojo UI, confusing multi-step setup, and serial number / registration gates with a clean, high-performance native SwiftUI app).

## Main jobs
1. **Browse & Search Conversations**: Read directly from `~/Library/Messages/chat.db` (or custom folder), resolving phone numbers and emails to real names and avatars via macOS Contacts.
2. **Incremental Local Archiving**: Archive conversations and media attachments into a standalone, local database so messages are preserved even if deleted from the Messages app.
3. **Rich Export (HTML & PDF)**: Export full conversation threads or date ranges to standalone, styled HTML pages (viewable in any browser with images) or clean printable PDFs.
4. **Scheduled Background Archiving**: Automated recurring archival via native launchd LaunchAgent or on-demand one-click sync.

## Data
- **Conversation**: id, guid, chatIdentifier, displayName, service (iMessage/SMS/RCS), participants, messageCount, dateRange
- **Message**: id, guid, text, isFromMe, date, handle, service, tapbacks/reactions, attachments
- **Attachment**: id, filename, mimeType, originalPath, archivedPath, fileSize, isSticker
- **ArchivePlan**: id, name, mode (all or selected), selectedChatIds, destinationURL, lastRunDate
- **ArchiveSchedule**: id, planId, frequency (Daily, Weekly, Monthly), time, isEnabled

## Shape
Standard 3-column `NavigationSplitView` (Sidebar, Conversation List, Rich Thread View) on macOS 26/27. Pure native Swift & SwiftUI. Local data. 100% offline. No accounts or registration.

## System hooks
- Full Disk Access status detection with one-click direct system settings jump
- Native macOS `CNContactStore` for address book name & avatar lookup
- macOS `launchd` LaunchAgent generation for background scheduled runs

## Reference
MAX Messages (Moth Software), Apple Messages

## Look
Native macOS 26+ design with system materials, SF Symbols, authentic iMessage (blue), SMS (green), and received (gray) bubbles, adaptive typography, and full Light & Dark mode support.

## Not in version one
- Cloud/server syncing (100% private and on-device)
- Two-way message sending (pure archival, backup, and extraction tool)
- License keys, registration dialogs, or paid upgrades
