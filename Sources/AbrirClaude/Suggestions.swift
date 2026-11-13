import Foundation

/// the rows under the field: recent folders while it is empty, matching subfolders while typing.
enum Suggestions {
    /// enough to scroll through any real folder, and a ceiling for the odd one with thousands
    static let limit = 500

    /// subfolders of what is typed so far, in the same form the user types (relative or absolute),
    /// each ending in "/" so tab can keep going deeper.
    static func completions(for raw: String, home: String = FolderPath.home) -> [String] {
        let typed = raw.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }

        let parentTyped: String
        let prefix: String
        if typed.hasSuffix("/") {
            parentTyped = typed
            prefix = ""
        } else if let slash = typed.lastIndex(of: "/") {
            parentTyped = String(typed[...slash])
            prefix = String(typed[typed.index(after: slash)...])
        } else {
            parentTyped = ""
            prefix = typed
        }

        let parent = FolderPath.resolve(parentTyped, home: home)
        let url = URL(fileURLWithPath: parent, isDirectory: true)
        let showHidden = prefix.hasPrefix(".")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: showHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }

        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { prefix.isEmpty || $0.lowercased().hasPrefix(prefix.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { parentTyped + $0 + "/" }
    }
}

/// the last folders claude was opened in, newest first, in their display form ("" is home).
enum Recents {
    private static let key = "recentFolders"
    static let limit = 10

    static var all: [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FolderPath.isDirectory(FolderPath.resolve($0)) }
    }

    static func add(_ raw: String) {
        let display = FolderPath.display(FolderPath.resolve(raw))
        guard !display.isEmpty else { return } // home needs no row: an empty field already opens it
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == display }
        list.insert(display, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }
}
