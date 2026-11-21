import Foundation

public enum SchedulerManager {
    public static let agentLabel = "com.imessagearchive"
    
    public static var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    public static func isScheduled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    public static func installSchedule(
        hour: Int = 2,
        minute: Int = 0,
        appExecutablePath: String = "/Applications/iMessageArchive.app/Contents/MacOS/iMessageArchive"
    ) throws {
        let launchAgentsDir = launchAgentPlistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appExecutablePath)</string>
                <string>--archive-background</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key>
                <integer>\(hour)</integer>
                <key>Minute</key>
                <integer>\(minute)</integer>
            </dict>
            <key>RunAtLoad</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/tmp/\(agentLabel).log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/\(agentLabel).err</string>
        </dict>
        </plist>
        """

        try plistContent.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)
        
        // Reload launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", launchAgentPlistURL.path]
        try? process.run()
        process.waitUntilExit()
    }

    public static func removeSchedule() {
        guard isScheduled() else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", launchAgentPlistURL.path]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: launchAgentPlistURL)
    }
}
