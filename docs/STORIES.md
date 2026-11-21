# iMessageArchive User Stories

Backlog for iMessageArchive, replacing MAX Messages with a native, registration-free, modern macOS SwiftUI application.

## Milestone 1: Core Reader & Thread Inspection

### S-001 Direct chat.db extraction
As a user, I want iMessageArchive to read my local `chat.db` directly and list all conversations, handles, and message counts without manual export steps.
Depends: none
Acceptance:
- [unit] SQLite parser opens `chat.db` in read-only immutable mode.
- [unit] Extracts chats, handles, messages, attachments, and tapbacks accurately.
- [unit] Accurately converts Apple CoreData timestamps (nanoseconds since 2001-01-01) to Swift `Date`.
Status: done

### S-002 Contact resolution via macOS Contacts
As a user, I want phone numbers and email addresses to automatically resolve to real contact names and photos from my Mac's AddressBook.
Depends: S-001
Acceptance:
- [unit] `ContactResolver` queries `CNContactStore` with phone number and email keys.
- [unit] Formats fallback names gracefully when contact is not in address book (e.g. pretty phone number or email handle).
- [snap] Shows avatar initial circle or contact photo next to thread names.
Status: done

### S-003 3-Column Conversation List
As a user, I want a clean modern sidebar and conversation list displaying my threads, search bar, and message stats.
Depends: S-001, S-002
Acceptance:
- [snap] Left sidebar displays Library, Plans, Schedules, and Settings tabs.
- [snap] Middle column lists all conversations with contact avatars, participant names, last message snippet, and total message count.
- [snap] Selecting a conversation updates the detail view instantly.
Status: done

### S-004 Authentic Message Thread View
As a user, I want to view my message history in a familiar, modern chat bubble interface with timestamps, service styling, and attachment previews.
Depends: S-003
Acceptance:
- [snap] Distinguishes sent messages (Blue for iMessage, Green for SMS) from received messages (Gray).
- [snap] Displays image attachments inline with click-to-preview or QuickLook.
- [snap] Renders tapbacks (loved, liked, disliked, laughed, emphasized, questioned) as bubble badges.
Status: done

## Milestone 2: Archiving & Plans

### S-005 Archival Plans
As a user, I want to create archival plans to archive either all conversations or specific selected chats to a chosen directory.
Depends: S-003
Acceptance:
- [unit] Plan model saves name, target directory, selection mode (all vs selected), and conversation IDs.
- [snap] Plan creation sheet allows naming, picking destination folder, and selecting conversations.
Status: done

### S-006 Incremental Archiving Engine
As a user, I want the archive engine to copy messages and media attachments into a self-contained archive database so messages are saved even if deleted from Apple Messages.
Depends: S-005
Acceptance:
- [unit] Engine copies attachments into `attachments/` subdirectory within archive folder.
- [unit] Incremental run only processes messages newer than the last archived timestamp.
- [unit] Generates an index database in the target archive directory.
Status: done

## Milestone 3: Search & Filtering

### S-007 Full-text search and filtering
As a user, I want to search for keywords across all conversations or within a single thread.
Depends: S-004
Acceptance:
- [snap] Search field in toolbar filters conversations in real time.
- [snap] Highlighting matching text in message content.
Status: done

### S-008 Date Navigator & Jump to Date
As a user, I want to filter messages by date or jump directly to a specific month or year.
Depends: S-004
Acceptance:
- [snap] Date picker or jump dropdown jumps to messages around that date.
- [unit] Date filter restricts messages displayed to a start/end date range.
Status: done

## Milestone 4: Export Engine (HTML & PDF)

### S-009 Standalone HTML Export
As a user, I want to export any conversation into a standalone, styled HTML file with attachments so I can view it offline in any web browser without needing the app.
Depends: S-004
Acceptance:
- [unit] Generates self-contained HTML file with embedded or relative attachments and responsive CSS.
- [manual] Opens cleanly in Brave / Safari and renders chat bubbles and images.
Status: done

### S-010 Formatted PDF Export
As a user, I want to export conversations to clean, paginated PDF documents for records or legal archiving.
Depends: S-004
Acceptance:
- [unit] Generates PDF using `PDFKit` / `NSPrintOperation` with headers, page numbers, participant names, and message bubbles.
- [manual] PDF preview renders with clear typography and margins.
Status: done

## Milestone 5: Automation & Simple Setup

### S-011 Simple Setup & Permissions Detector
As a user, I want the app to guide me smoothly on first run with clear status of Full Disk Access, without complex wizard steps or registration dialogs.
Depends: none
Acceptance:
- [snap] Shows permission banner or card if Full Disk Access is missing with a 1-click button to open System Settings.
- [unit] Provides fallback file picker to select a custom `chat.db` or folder if running without FDA.
Status: done

### S-012 Background Scheduled Archiving
As a user, I want to configure automatic scheduled archives (e.g. daily or weekly) so my messages are continuously backed up in the background.
Depends: S-006
Acceptance:
- [unit] Generates and registers a macOS `launchd` LaunchAgent plist in `~/Library/LaunchAgents/` with scheduled calendar interval.
- [unit] CLI / helper mode runs the archive plan headlessly and updates the archive.
Status: done
