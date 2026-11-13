import Foundation

/// one claude session, as claude code keeps it in ~/.claude/projects/<folder>/<id>.jsonl
struct SessionInfo: Equatable, Sendable, Identifiable {
    let id: String
    /// its custom or ai title, else its first message
    let title: String
    let updated: Date
}

/// a folder worth offering: where claude was opened, by this app or by hand, and the git repos
/// under ~/Developer. what each row shows beside its name comes from here.
struct ProjectInfo: Equatable, Sendable {
    let path: String
    var lastUsed: Date?
    var sessions: [SessionInfo] = []
    var branch: String?
}

enum ProjectIndex {
    /// every project known, keyed by absolute path (no trailing slash)
    static func build(recents: [String: Date], home: String = FolderPath.home) -> [String: ProjectInfo] {
        var projects: [String: ProjectInfo] = [:]
        for (path, sessions) in sessions(home: home) {
            projects[path] = ProjectInfo(path: path, lastUsed: sessions.first?.updated, sessions: sessions)
        }
        for (display, date) in recents {
            let path = trimmed(FolderPath.resolve(display, home: home))
            var p = projects[path] ?? ProjectInfo(path: path)
            p.lastUsed = max(p.lastUsed ?? .distantPast, date)
            projects[path] = p
        }
        for repo in gitRepos(under: [home + "/Developer"]) where projects[repo] == nil {
            projects[repo] = ProjectInfo(path: repo)
        }
        for (path, var p) in projects {
            guard path != home, FolderPath.isDirectory(path) else { projects[path] = nil; continue }
            p.branch = branch(of: path)
            projects[path] = p
        }
        return projects
    }

    // MARK: claude's sessions

    /// claude's sessions by the folder they ran in, newest first. only the head and tail of each file
    /// are read (they reach hundreds of mb): the folder and first message are at the start, titles are
    /// appended as the session goes.
    static func sessions(home: String = FolderPath.home) -> [String: [SessionInfo]] {
        let root = URL(fileURLWithPath: home).appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [:] }
        var byFolder: [String: [SessionInfo]] = [:]
        for folder in folders {
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let (cwd, session) = read(file), !isScratch(cwd) else { continue }
                byFolder[trimmed(cwd), default: []].append(session)
            }
        }
        return byFolder.mapValues { $0.sorted { $0.updated > $1.updated } }
    }

    static func read(_ file: URL) -> (String, SessionInfo)? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: 96_000)) ?? Data()
        var tail = Data()
        if size > 96_000 {
            try? handle.seek(toOffset: size - min(size - 96_000, 96_000))
            tail = (try? handle.read(upToCount: 96_000)) ?? Data()
        }
        let updated = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return parse(head: head, tail: tail, id: file.deletingPathExtension().lastPathComponent, updated: updated)
    }

    static func parse(head: Data, tail: Data, id: String, updated: Date) -> (String, SessionInfo)? {
        var cwd: String?
        var firstMessage: String?
        var customTitle: String?
        var aiTitle: String?
        func scan(_ data: Data, isHead: Bool) {
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if cwd == nil, let c = json["cwd"] as? String { cwd = c }
                switch json["type"] as? String {
                case "custom-title": customTitle = (json["customTitle"] as? String) ?? customTitle
                case "ai-title": aiTitle = (json["aiTitle"] as? String) ?? aiTitle
                case "user" where isHead && firstMessage == nil && json["isMeta"] as? Bool != true:
                    firstMessage = text(of: json["message"])
                default: break
                }
            }
        }
        scan(head, isHead: true)
        scan(tail, isHead: false)
        guard let cwd else { return nil }
        let title = [customTitle, aiTitle, firstMessage].compactMap { $0 }.first { !$0.isEmpty } ?? "Untitled session"
        return (cwd, SessionInfo(id: id, title: title, updated: updated))
    }

    /// a user message's words on one line, without pasted blocks, tags or slash command noise
    static func text(of message: Any?) -> String? {
        guard let message = message as? [String: Any] else { return nil }
        var raw = ""
        if let s = message["content"] as? String {
            raw = s
        } else if let parts = message["content"] as? [[String: Any]] {
            raw = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
        }
        var s = raw
        s = s.replacingOccurrences(of: "<pasted_content[^>]*>[\\s\\S]*?</pasted_content[^>]*>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !s.hasPrefix("Caveat:") else { return nil }
        return String(s.prefix(120))
    }

    private static func isScratch(_ path: String) -> Bool {
        path.hasPrefix("/private/") || path.hasPrefix("/tmp/") || path.hasPrefix("/var/") || path.contains("/scratchpad")
    }

    // MARK: git

    /// git repos under the roots, three levels down at most, not looking inside a repo once found
    static func gitRepos(under roots: [String], depth: Int = 3) -> [String] {
        let fm = FileManager.default
        let skip: Set<String> = ["node_modules", "build", "dist", "Pods", "DerivedData", "vendor", "target"]
        var found: [String] = []
        var budget = 3000
        func walk(_ dir: String, _ level: Int) {
            guard budget > 0 else { return }
            budget -= 1
            if fm.fileExists(atPath: dir + "/.git") { found.append(dir); return }
            guard level < depth, let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items where !item.hasPrefix(".") && !skip.contains(item) && !item.hasSuffix(".app") {
                let path = dir + "/" + item
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { walk(path, level + 1) }
            }
        }
        for root in roots { walk(root, 0) }
        return found
    }

    /// the checked-out branch, from .git/HEAD (a worktree's .git file points at its own)
    static func branch(of path: String) -> String? {
        var gitDir = path + "/.git"
        if let pointer = try? String(contentsOfFile: gitDir, encoding: .utf8), pointer.hasPrefix("gitdir:") {
            gitDir = pointer.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let head = try? String(contentsOfFile: gitDir + "/HEAD", encoding: .utf8) else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") { return String(line.dropFirst(16)) }
        return line.isEmpty ? nil : String(line.prefix(7))
    }

    static func trimmed(_ path: String) -> String { path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path }
}

/// fuzzy matching as a command palette does it: the letters typed, in order, anywhere in the path,
/// scored up for matching the folder's own name, the start of a word and runs of letters together.
enum Fuzzy {
    static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return 0 }
        let trimmedCandidate = candidate.hasSuffix("/") ? String(candidate.dropLast()) : candidate
        let c = Array(trimmedCandidate.lowercased())
        let original = Array(trimmedCandidate)
        let nameStart = (c.lastIndex(of: "/") ?? -1) + 1
        var score = 0, qi = 0, last = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var s = 1
            if ci >= nameStart { s += 3 }
            if ci == nameStart { s += 8 }
            let prev: Character? = ci > 0 ? original[ci - 1] : nil
            if prev == nil || prev == "/" || prev == "-" || prev == "_" || prev == " " || prev == "." { s += 5 }
            if let p = prev, p.isLowercase, original[ci].isUppercase { s += 4 }
            if last == ci - 1 { s += 4 }
            score += s
            last = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        // a name that starts with what is typed beats everything; shorter paths edge ahead
        let name = String(c[nameStart...])
        if name.hasPrefix(String(q)) { score += 40 }
        return score - c.count / 8
    }
}
