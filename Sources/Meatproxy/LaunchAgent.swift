import Foundation
import FactoryCollector

/// The heartbeat while the app is closed (D47, optional): a user launch agent that runs `Meatproxy --heartbeat` every
/// five minutes. That headless run starts any factory whose beat is due and exits; the lock file keeps it and the app
/// from running the same CEO twice. Installed and removed from Settings; nothing else is touched.
enum LaunchAgent {
    static let label = "dev.tuinstra.meatproxy.heartbeat"
    static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }

    static func install(executable: String = Bundle.main.executablePath ?? CommandLine.arguments[0]) throws {
        let log = AppSupport.folder.appendingPathComponent("heartbeats/agent.log").path
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--heartbeat"],
            "StartInterval": 300,
            "RunAtLoad": true,
            "StandardOutPath": log, "StandardErrorPath": log,
            "ProcessType": "Background",
        ]
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppSupport.folder.appendingPathComponent("heartbeats"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plist, options: .atomic)
        launchctl(["bootout", "gui/\(getuid())/\(label)"])           // an older one, if any
        guard launchctl(["bootstrap", "gui/\(getuid())", plist.path]) == 0 else {
            throw NSError(domain: "Meatproxy", code: 1, userInfo: [NSLocalizedDescriptionKey: "launchctl refused the agent"])
        }
    }

    static func remove() throws {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
