import Foundation

/// the number of the newest model of each family ("opus" → "5.5"), read from the installed `claude`
/// itself, so the palette shows what `--model opus` runs today and follows every claude update without
/// a change here. the result is kept per claude binary (its path names its version), so the binary is
/// read again only after claude updates.
enum ModelVersions {
    static let families = ["fable", "opus", "sonnet", "haiku"]
    private static let cacheKey = "modelVersions"

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
        return best.mapValues { $0.1 == 0 ? "\($0.0)" : "\($0.0).\($0.1)" }
    }
}
