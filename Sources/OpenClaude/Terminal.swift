import Foundation

/// opens a new terminal window and runs a command in it, through apple events. the first time macOS
/// asks whether open claude may control terminal.
enum Terminal {
    enum Failure: Error {
        /// the user said no to controlling terminal, or has not been asked yet in a way that stuck
        case notAllowed
        case other(String)
    }

    @MainActor
    static func run(_ command: String) -> Result<Void, Failure> {
        let source = """
        set theCommand to "\(appleScriptEscaped(command))"
        set wasRunning to application "Terminal" is running
        tell application "Terminal"
            if wasRunning then
                do script theCommand
            else
                -- a terminal that was closed opens its own first window: use that one, not a second
                launch
                repeat 40 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.05
                end repeat
                if (count of windows) > 0 then
                    do script theCommand in window 1
                else
                    do script theCommand
                end if
            end if
            activate
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return .failure(.other("script")) }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return .success(()) }
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 || code == -1744 { return .failure(.notAllowed) }
        return .failure(.other(error[NSAppleScript.errorMessage] as? String ?? "error \(code)"))
    }

    private static func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
