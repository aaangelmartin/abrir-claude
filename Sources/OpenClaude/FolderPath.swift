import Foundation

/// what the user types, turned into a folder: relative to the home folder, absolute (/Volumes/...),
/// or empty for the home folder itself. a leading "~/" is accepted too.
enum FolderPath {
    static var home: String { NSHomeDirectory() }

    static func resolve(_ raw: String, home: String = FolderPath.home) -> String {
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == "~" { return home }
        if typed.hasPrefix("~/") { return join(home, String(typed.dropFirst(2))) }
        if typed.hasPrefix("/") { return typed }
        return join(home, typed)
    }

    /// the form shown to the user: relative to home when inside it, absolute otherwise.
    static func display(_ absolute: String, home: String = FolderPath.home) -> String {
        if absolute == home { return "" }
        if absolute.hasPrefix(home + "/") { return String(absolute.dropFirst(home.count + 1)) }
        return absolute
    }

    static func isDirectory(_ absolute: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: absolute, isDirectory: &isDir) && isDir.boolValue
    }

    /// single quotes for zsh: 'it'\''s'
    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// the line the new terminal window runs. `cd` fails loudly and `&&` keeps claude from starting
    /// when the folder does not exist.
    static func command(for raw: String, args: [String] = []) -> String {
        (["cd", shellQuoted(resolve(raw)), "&&", "claude"] + args.map(shellWord)).joined(separator: " ")
    }

    /// a flag as typed when it is plain (--model opus), quoted only when it needs it
    static func shellWord(_ s: String) -> String {
        let plain = !s.isEmpty && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.=".unicodeScalars.contains($0) }
        return plain ? s : shellQuoted(s)
    }

    private static func join(_ base: String, _ rest: String) -> String {
        base.hasSuffix("/") ? base + rest : base + "/" + rest
    }
}
