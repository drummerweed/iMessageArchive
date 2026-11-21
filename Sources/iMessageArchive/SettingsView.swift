import SwiftUI
import iMessageArchiveKit

struct SettingsView: View {
    var body: some View {
        Form {
            GeneralSettings()
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
        .noInitialFocus()
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }
    var title: String { "General" }
    var symbol: String { "gearshape" }
}

struct GeneralSettings: View {
    @AppStorage("archiveDestination") private var archiveDestination = "~/Documents/iMessageArchive"
    @AppStorage("includeAttachments") private var includeAttachments = true
    @AppStorage("resolveContacts") private var resolveContacts = true

    var body: some View {
        Section("Archive Storage") {
            TextField("Default Destination", text: $archiveDestination)
            Toggle("Archive full-resolution media attachments", isOn: $includeAttachments)
        }

        Section("Contacts & Resolution") {
            Toggle("Resolve phone numbers & emails via macOS Contacts", isOn: $resolveContacts)
        }
    }
}
