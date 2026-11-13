import Foundation

/// the number of the newest model of each family ("opus" → "5.5") and the effort that model starts
/// with ("effort.opus" → "medium"), read from the installed `claude` itself, so the window shows what
/// `--model opus` runs today and follows every claude update without a change here. the result is kept per claude binary (its path names its version), so the binary is
/// read again only after claude updates.
enum ModelVersions {
    static let families = ["fable", "opus", "sonnet", "haiku"]
    private static let cacheKey = "modelCatalog"

    /// where claude is installed, symlinks resolved. the app starts without a shell PATH, so the usual
    /// places are tried in turn.
    static func binary() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }
        return nil
    }

    /// what was read last time, if it was read from this binary
    static func cached(for binary: String?, _ defaults: UserDefaults = .standard) -> [String: String]? {
        guard let binary, let saved = defaults.dictionary(forKey: cacheKey),
              saved["binary"] as? String == binary else { return nil }
        return saved["versions"] as? [String: String]
    }

    static func save(_ versions: [String: String], for binary: String, _ defaults: UserDefaults = .standard) {
        defaults.set(["binary": binary, "versions": versions], forKey: cacheKey)
    }

    /// reads the binary for every "claude-<family>-<major>[-<minor>]" and keeps the highest of each
    static func scan(_ path: String) -> [String: String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return [:] }
        return newest(in: data)
    }

    static func newest(in data: Data) -> [String: String] {
        var best: [String: (Int, Int)] = [:]
        let marker = Array("claude-".utf8)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let bytes = raw.bindMemory(to: UInt8.self)
            var at = 0
            while at < raw.count, let hit = memmem(base + at, raw.count - at, marker, marker.count) {
                let start = base.distance(to: UnsafeRawPointer(hit)) + marker.count
                at = start
                // the family
                var i = start
                while i < raw.count, bytes[i] >= 97, bytes[i] <= 122 { i += 1 }
                guard i - start <= 6, i < raw.count, bytes[i] == 45,
                      let family = String(bytes: bytes[start..<i], encoding: .ascii), families.contains(family) else { continue }
                // the major number, then a minor of one or two digits (a date of eight is not a minor)
                func number(_ from: Int) -> (Int, Int)? {
                    var j = from, n = 0
                    while j < raw.count, bytes[j] >= 48, bytes[j] <= 57, j - from < 9 { n = n * 10 + Int(bytes[j] - 48); j += 1 }
                    return j > from ? (n, j - from) : nil
                }
                guard let (major, majorDigits) = number(i + 1), majorDigits <= 2 else { continue }
                var minor = 0
                let afterMajor = i + 1 + majorDigits
                if afterMajor < raw.count, bytes[afterMajor] == 45, let (m, digits) = number(afterMajor + 1), digits <= 2 {
                    minor = m
                }
                if let old = best[family], old >= (major, minor) { continue }
                best[family] = (major, minor)
            }
        }
        var result = best.mapValues { $0.1 == 0 ? "\($0.0)" : "\($0.0).\($0.1)" }
        let efforts = defaultEfforts(in: data)
        for (family, (major, minor)) in best {
            let id = "claude-\(family)-\(major)" + (minor == 0 ? "" : "-\(minor)")
            if let effort = efforts[id] { result["effort." + family] = effort }
        }
        return result
    }

    /// claude's model table gives each model a default_effort. each one belongs to the model id named
    /// last before it (as id:"claude-opus-5-5", model:..., name:...); the most common answer wins.
    static func defaultEfforts(in data: Data) -> [String: String] {
        let levels: Set<String> = ["low", "medium", "high", "xhigh", "max"]
        var ids: [(Int, String)] = []
        var efforts: [(Int, String)] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let bytes = raw.bindMemory(to: UInt8.self)
            func word(from: Int, allowed: (UInt8) -> Bool) -> String? {
                var j = from
                while j < raw.count, allowed(bytes[j]), j - from < 40 { j += 1 }
                return j > from ? String(bytes: bytes[from..<j], encoding: .ascii) : nil
            }
            // ids that are the value of a key: id:"claude-…"
            let idMarker = Array(":\"claude-".utf8)
            var at = 0
            while at < raw.count, let hit = memmem(base + at, raw.count - at, idMarker, idMarker.count) {
                let pos = base.distance(to: UnsafeRawPointer(hit))
                at = pos + idMarker.count
                var k = pos - 1
                while k >= 0, (bytes[k] >= 97 && bytes[k] <= 122) || bytes[k] == 95 { k -= 1 }
                guard let key = String(bytes: bytes[(k + 1)..<pos], encoding: .ascii),
                      ["id", "model", "name", "model_id", "canonical_id"].contains(key),
                      let id = word(from: pos + 2, allowed: { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 })
                else { continue }
                ids.append((pos, id))
            }
            let effortMarker = Array("default_effort:\"".utf8)
            at = 0
            while at < raw.count, let hit = memmem(base + at, raw.count - at, effortMarker, effortMarker.count) {
                let pos = base.distance(to: UnsafeRawPointer(hit))
                at = pos + effortMarker.count
                if let level = word(from: at, allowed: { $0 >= 97 && $0 <= 122 }), levels.contains(level) {
                    efforts.append((pos, level))
                }
            }
        }
        var tally: [String: [String: Int]] = [:]
        var i = 0
        for (pos, level) in efforts {
            while i + 1 < ids.count, ids[i + 1].0 < pos { i += 1 }
            guard i < ids.count, ids[i].0 < pos, pos - ids[i].0 < 6000 else { continue }
            tally[ids[i].1, default: [:]][level, default: 0] += 1
        }
        return tally.compactMapValues { $0.max { $0.value < $1.value }?.key }
    }
}
