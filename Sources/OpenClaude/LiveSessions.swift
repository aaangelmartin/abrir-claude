import AppKit
import Foundation

/// a claude code session running right now on this mac, as claude keeps it in
/// ~/.claude/sessions/<pid>.json while its process lives: where it runs, its name and what it is doing.
struct LiveSession: Equatable, Sendable, Identifiable {
    enum State: String, Sendable {
        /// thinking or using tools
        case busy
        /// stopped on something only you can give: a permission, an answer
        case waiting
        /// its turn is over: waiting for your next message (claude's "shell" too: not working)
        case idle
    }

    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String
    let state: State
    /// what a waiting session waits for, as claude says it ("permission", ...)
    let waitingFor: String?
    let since: Date
    var id: Int32 { pid }

    /// the order they are listed in: what needs you first, then what is working, then the rest
    var urgency: Int {
        switch state {
        case .waiting: 0
        case .busy: 1
        case .idle: 2
        }
    }
}

enum LiveSessions {
    private static var folder: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")
    }

    /// every session whose process is still alive, what needs you first, newest change first within
    static func all() -> [LiveSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap(parse)
            .filter { isAlive($0.pid) }
            .sorted { $0.urgency != $1.urgency ? $0.urgency < $1.urgency : $0.since > $1.since }
    }

    static func parse(_ data: Data) -> LiveSession? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = (json["pid"] as? NSNumber)?.int32Value,
              let sessionId = json["sessionId"] as? String,
              let cwd = json["cwd"] as? String,
              json["spare"] as? Bool != true else { return nil }
        let millis = (json["statusUpdatedAt"] as? NSNumber ?? json["updatedAt"] as? NSNumber ?? json["startedAt"] as? NSNumber)?.doubleValue ?? 0
        let name = (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? URL(fileURLWithPath: cwd).lastPathComponent
        return LiveSession(
            pid: pid, sessionId: sessionId, cwd: cwd, name: name,
            state: (json["status"] as? String).flatMap(LiveSession.State.init) ?? .idle, // "shell" and unknown: not working
            waitingFor: json["waitingFor"] as? String,
            since: Date(timeIntervalSince1970: millis / 1000)
        )
    }

    /// a process that exists, ours or not (EPERM still means it is there)
    static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: going to a session

    /// brings the session's own window forward: its terminal tab when it runs in Terminal, otherwise
    /// the app it runs in. false when neither could be found.
    @MainActor
    static func focus(_ session: LiveSession) -> Bool {
        if let tty = tty(of: session.pid), focusTerminalTab(tty: "/dev/" + tty) { return true }
        if let app = owningApp(of: session.pid) { return app.activate() }
        return false
    }

    private static func tty(of pid: Int32) -> String? {
        let out = run("/bin/ps", ["-o", "tty=", "-p", String(pid)])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, !out.isEmpty, out != "??" else { return nil }
        return out
    }

    @MainActor
    private static func focusTerminalTab(tty: String) -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty == false else { return false }
        let source = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && result?.booleanValue == true
    }

    /// the app the process runs under (an editor's terminal, iTerm, ...), up its parents
    private static func owningApp(of pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            guard let parent = run("/bin/ps", ["-o", "ppid=", "-p", String(current)])
                .flatMap({ Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func run(_ tool: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
