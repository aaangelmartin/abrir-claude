import AppKit
import Combine

/// the palette's state: one field and one list, as claude's own session list works. the first line
/// is always "new session", in a folder shown beside it; under it, your sessions, the running ones
/// first with their state, then the past ones. enter on a session goes to it (running) or resumes it
/// (past); enter with nothing lit, or on the first line, starts a new session. → on the first line
/// picks another folder for it.
@MainActor
final class PaletteModel: ObservableObject {
    enum Notice: Equatable {
        /// macOS said no to controlling terminal
        case notAllowed
        case failed(String)
        /// a running session whose window could not be found
        case windowNotFound(String)
    }

    enum Key: Equatable {
        case up, down, left, right, enter, tab, escape, space
        case jumpDown, jumpUp // ⌘↓ ⌘↑
        case optionsDown, optionsUp // ⌥↓ ⌥↑: open and fold the options
        case openNew // ⌘↵: a new session (in the lit session's folder)
    }

    /// one line of the list
    enum Item: Equatable {
        case running(LiveSession)
        case past(folder: String, session: SessionInfo)
    }

    @Published var text = "" { didSet { if text != oldValue { textChanged() } } }
    /// true while the folder for the new session is being picked (the list shows folders then)
    @Published private(set) var pickingFolder = false
    /// the folder picked for the new session, nil to follow what is typed (or the last one used)
    @Published private(set) var pickedFolder: String?
    /// the folders listed while picking one
    @Published private(set) var rows: [String] = []
    @Published private(set) var showingRecents = false
    /// the lit line, nil on the field. in the list, 0 is "new session" and 1... the sessions; while
    /// picking a folder, the folder rows from 0
    @Published var selected: Int?
    /// true when the pointer, not the keys, picked the row: the list then stays where it is
    private(set) var selectedByPointer = false
    @Published var notice: Notice?
    /// changes with every new set of rows, so the list view starts fresh (top, same margins)
    @Published private(set) var listID = UUID()

    /// the picked value of each launch option. every time the palette opens they start again from
    /// claude's defaults, so a one-off choice never carries over to the next launch
    @Published private(set) var picks: [Int] = LaunchOptions.all.map { _ in 0 }
    /// the plan's session and weekly use, when claude code's sign-in can be read
    @Published var usage: Usage?
    private var usageFetchedAt: Date?
    /// the option the arrows are on (the options are open while it is set), nil on the field and list
    @Published private(set) var optionRow: Int?
    /// which way the last change went (-1 back, 1 forward), so a carousel slides the right way
    private(set) var lastDelta = 1
    var optionsOpen: Bool { optionRow != nil }
    /// the newest number of each model family, as the installed claude knows them
    @Published private(set) var modelVersions: [String: String] = ModelVersions.cached(for: ModelVersions.binary()) ?? [:]
    private var versionsBinary: String?

    /// every folder worth offering, with its sessions and branch (built in the background)
    @Published var projects: [String: ProjectInfo] = [:]
    private var projectsBuiltAt: Date?
    /// the newest recent when the projects were built: a folder opened since rebuilds them at once
    private var projectsNewestRecent: String?
    /// claude code sessions running now on this mac, read again while the palette is open
    @Published var live: [LiveSession] = []
    /// asks the panel to bring a running session forward
    var onFocus: (LiveSession) -> Void = { _ in }

    init() { refreshModelVersions() }

    /// asks the panel to open a folder (raw, as typed, with the flags) or to close
    var onOpen: (String, [String]) -> Void = { _, _ in }
    var onClose: () -> Void = {}

    /// the folder part of what is typed ("Developer/" in "Developer/Pr"), dimmed in the rows
    var typedParent: String {
        guard let slash = text.lastIndex(of: "/") else { return "" }
        return String(text[...slash])
    }

    func reset() {
        refreshLive()
        refreshModelVersions()
        refreshProjects()
        refreshUsage()
        picks = LaunchOptions.all.map { _ in 0 }
        notice = nil
        optionRow = nil
        pickingFolder = false
        pickedFolder = nil
        text = ""
        refreshRows()
    }

    private func textChanged() {
        // typing always happens in the field: the arrows go back there
        optionRow = nil
        refreshRows()
    }

    func refreshRows() {
        listID = UUID()
        selectedByPointer = false
        // nothing is lit until an arrow or the pointer lights it
        selected = nil
        guard pickingFolder else { rows = []; showingRecents = false; return }
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            rows = recentRows()
            showingRecents = !rows.isEmpty
        } else if isPath(typed) {
            rows = Suggestions.completions(for: text)
            showingRecents = false
        } else {
            rows = fuzzyRows(typed)
            showingRecents = false
        }
    }

    private func isPath(_ typed: String) -> Bool { typed.contains("/") || typed.hasPrefix("~") }

    // MARK: the list

    /// the sessions listed: the running ones (those needing you first), then the past ones, newest
    /// first. typing keeps the running ones whose name or folder matches and the past ones whose title
    /// has every word typed or whose folder matches.
    var items: [Item] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let words = typed.lowercased().split(separator: " ").map(String.init)
        func matches(_ title: String, _ folder: String) -> Bool {
            guard !words.isEmpty else { return true }
            let t = title.lowercased(), f = folder.lowercased()
            return words.allSatisfy { t.contains($0) || f.contains($0) }
        }
        let running = live.filter { matches($0.name, FolderPath.display($0.cwd)) }
        let ids = Set(live.map(\.sessionId))
        let past = projects.values
            .flatMap { p in p.sessions.map { (FolderPath.display(p.path), $0) } }
            .filter { !ids.contains($0.1.id) && matches($0.1.title, $0.0) }
            .sorted { $0.1.updated > $1.1.updated }
            .prefix(typed.isEmpty ? 30 : 100)
        return running.map(Item.running) + past.map { Item.past(folder: $0.0, session: $0.1) }
    }

    /// where "new session" starts: the folder picked, or what is typed when it is a path, or the
    /// folder that best matches a name typed, or the folder used last (home when there is none)
    var newFolder: String {
        if let pickedFolder { return pickedFolder }
        let typed = text.trimmingCharacters(in: .whitespaces)
        if isPath(typed), FolderPath.isDirectory(FolderPath.resolve(typed)) { return typed }
        if !typed.isEmpty, !isPath(typed), let best = fuzzyRows(typed).first { return best }
        return recentRows().first ?? ""
    }

    /// how many lines can be lit: the folders while picking; "new session" and the sessions otherwise
    var count: Int { pickingFolder ? rows.count : 1 + items.count }

    func refreshLive() {
        let now = LiveSessions.all()
        if now != live { live = now }
        if let i = selected, i >= count { selected = count - 1 }
    }

    /// enter on a line of the list
    func act(on index: Int) {
        if index == 0 { startNew(in: newFolder); return }
        let list = items
        guard list.indices.contains(index - 1) else { return }
        switch list[index - 1] {
        case let .running(s): onFocus(s)
        case let .past(folder, s): onOpen(folder, LaunchOptions.args(for: picks) + ["--resume", s.id])
        }
    }

    private func startNew(in folder: String) {
        onOpen(folder, LaunchOptions.args(for: picks))
    }

    /// ⌘↵: a new session in the lit session's folder, or where "new session" points
    func openNew() {
        if pickingFolder { choose(selected.flatMap { rows.indices.contains($0) ? rows[$0] : nil } ?? text); return }
        if let i = selected, i > 0, items.indices.contains(i - 1) {
            switch items[i - 1] {
            case let .running(s): startNew(in: FolderPath.display(s.cwd))
            case let .past(folder, _): startNew(in: folder)
            }
            return
        }
        startNew(in: newFolder)
    }

    /// the shortcut pressed with the palette open: start the new session
    func hotkeyAgain() { openNew() }

    // MARK: picking the folder

    func pickFolder() {
        pickingFolder = true
        optionRow = nil
        if text.isEmpty { refreshRows() } else { text = "" }
    }

    /// a folder chosen for the new session: back to the list, "new session" lit and pointing there
    func choose(_ row: String) {
        let folder = row.trimmingCharacters(in: .whitespaces)
        guard folder.isEmpty || FolderPath.isDirectory(FolderPath.resolve(folder)) else { NSSound.beep(); return }
        pickedFolder = folder
        pickingFolder = false
        text = ""
        refreshRows()
        selected = 0
    }

    func cancelPick() {
        pickingFolder = false
        if text.isEmpty { refreshRows() } else { text = "" }
    }

    /// what enter would open now while picking
    var target: String {
        if let selected, rows.indices.contains(selected) { return rows[selected] }
        return text
    }

    // MARK: projects

    /// rebuilds the projects at most every two minutes, off the main thread
    func refreshProjects() {
        let newest = Recents.all.first
        if let at = projectsBuiltAt, Date().timeIntervalSince(at) < 120, newest == projectsNewestRecent { return }
        projectsBuiltAt = Date()
        projectsNewestRecent = newest
        let recents = Recents.dates
        Task.detached(priority: .userInitiated) {
            let built = ProjectIndex.build(recents: recents)
            await MainActor.run {
                self.projects = built
                if self.optionRow == nil, self.selected == nil { self.refreshRows() }
            }
        }
    }

    /// what a row is, when it is a known project
    func info(for row: String) -> ProjectInfo? {
        projects[ProjectIndex.trimmed(FolderPath.resolve(row))]
    }

    /// the folders used last, here or in claude, newest first
    private func recentRows() -> [String] {
        let known = projects.values
            .filter { $0.lastUsed != nil }
            .sorted { $0.lastUsed! > $1.lastUsed! }
            .prefix(12)
            .map { FolderPath.display($0.path) }
        return known.isEmpty ? Recents.all : Array(known)
    }

    /// a name typed, not a path: the home folder's own folders and every known project, matched
    /// fuzzily (letters in order, anywhere), the best first and the recently used a little ahead
    private func fuzzyRows(_ typed: String) -> [String] {
        var candidates: [String: Date?] = [:]
        for row in Suggestions.completions(for: "", allIn: FolderPath.home) { candidates[row] = .some(nil) }
        // every row ends in "/" so tab goes on into it
        for p in projects.values { candidates[FolderPath.display(p.path) + "/"] = p.lastUsed }
        let now = Date()
        let scored: [(String, Int)] = candidates.compactMap { row, used in
            guard let s = Fuzzy.score(typed, row) else { return nil }
            let days = used.flatMap { $0 }.map { now.timeIntervalSince($0) / 86_400 } ?? 1_000
            let recency = days < 1 ? 14 : days < 7 ? 9 : days < 30 ? 4 : 0
            return (row, s + recency)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            .prefix(60)
            .map(\.0)
    }

    /// the pointer moved onto a line
    func point(at index: Int) {
        guard index < count, selected != index else { return }
        selectedByPointer = true
        selected = index
    }

    // MARK: launch options

    /// reads the model numbers again when claude has been updated since they were last read; the
    /// binary is large, so that happens off the main thread and the labels follow when it is done
    func refreshModelVersions() {
        guard let binary = ModelVersions.binary(), binary != versionsBinary else { return }
        versionsBinary = binary
        if let cached = ModelVersions.cached(for: binary) {
            if cached != modelVersions { modelVersions = cached }
            return
        }
        Task.detached(priority: .utility) {
            let found = ModelVersions.scan(binary)
            guard !found.isEmpty else { return }
            await MainActor.run {
                ModelVersions.save(found, for: binary)
                self.modelVersions = found
            }
        }
    }

    /// asks for the plan's use again, at most once a minute
    func refreshUsage() {
        // only the installed app reads the keychain (tests and previews would make macOS ask)
        guard Bundle.main.bundleIdentifier == "com.aaangelmartin.open-claude" else { return }
        if let at = usageFetchedAt, Date().timeIntervalSince(at) < 60 { return }
        usageFetchedAt = Date()
        Task.detached(priority: .utility) {
            let found = await Usage.fetch()
            await MainActor.run { self.usage = found }
        }
    }

    /// a value as shown: models with their number ("Opus 5.5"), the rest as they are
    func display(_ choice: Choice, of option: Int) -> String {
        guard option == LaunchOptions.model, let alias = choice.args.last,
              let number = modelVersions[alias] else { return choice.label }
        return choice.label + " " + number
    }

    /// the value an option stands at, as shown: for an option whose default is marked rather than
    /// offered, the value its default amounts to
    func shown(_ option: Int) -> Int {
        let pick = picks[option]
        return pick == 0 && LaunchOptions.all[option].defaultIsMarked ? defaultValue(of: option) : pick
    }

    func choice(of option: Int) -> Choice { LaunchOptions.all[option].choices[shown(option)] }

    /// the value claude starts with when this option adds no flag: the settings' model (opus when they
    /// name none), the effort that model ships with, the settings' permission mode (manual when none)
    func defaultValue(of option: Int) -> Int {
        let o = LaunchOptions.all[option]
        guard o.defaultIsMarked else { return 0 }
        func index(_ label: String?) -> Int? { label.flatMap { l in o.choices.firstIndex { $0.label == l } } }
        switch option {
        case LaunchOptions.model:
            return index(LaunchOptions.settingsDefault(of: option)) ?? index("Opus") ?? 1
        case LaunchOptions.effort:
            let family = choice(of: LaunchOptions.model).args.last ?? "opus"
            return index(modelVersions["effort." + family]) ?? index("medium") ?? 1
        default:
            return index(LaunchOptions.settingsDefault(of: option)) ?? 1
        }
    }

    /// pick a value as shown: picking the default value stores "no flag", so it keeps following claude
    func pickShown(_ value: Int, of option: Int) {
        let o = LaunchOptions.all[option]
        pick(o.defaultIsMarked && value == defaultValue(of: option) ? 0 : value, of: option)
    }

    /// ← → on an option: the value before or after, stopping at the ends
    func step(_ option: Int, by delta: Int) {
        let o = LaunchOptions.all[option]
        let first = o.defaultIsMarked ? 1 : 0
        pickShown(min(max(shown(option) + delta, first), o.choices.count - 1), of: option)
    }

    func pick(_ value: Int, of option: Int) {
        guard LaunchOptions.all[option].choices.indices.contains(value), picks[option] != value else { return }
        lastDelta = value > shown(option) ? 1 : -1
        picks[option] = value
    }

    /// open the options on one of them (a click on the summary line, ⌘↓)
    func openOptions(at row: Int = 0) { optionRow = row }
    func closeOptions() { optionRow = nil }

    // MARK: keys

    /// one key, wherever the arrows are. false: not ours, the field gets it (←→ move the caret there,
    /// space types a space).
    func handle(_ key: Key) -> Bool {
        if key == .optionsDown { optionRow = optionRow ?? 0; return true }
        if key == .optionsUp { optionRow = nil; return true }
        if let optionRow { return handleOptions(key, optionRow) }
        switch key {
        case .down:
            // the last line is the end
            guard count > 0 else { return true }
            selectedByPointer = false
            selected = min((selected ?? -1) + 1, count - 1)
        case .up:
            // at the top already: stay there, never wrap round to the bottom
            guard let s = selected else { return true }
            selectedByPointer = false
            selected = s == 0 ? nil : s - 1
        case .jumpDown: if count > 0 { selectedByPointer = false; selected = count - 1 }
        case .jumpUp: selected = nil
        case .escape:
            // back out one step at a time: the folder picker, what is typed, then the palette
            if pickingFolder { cancelPick() } else if !text.isEmpty { text = "" } else { close() }
        case .enter: submit()
        case .openNew: openNew()
        case .tab:
            if pickingFolder { complete() } else if selected == nil || selected == 0 { pickFolder() }
        case .right:
            // → on "new session" picks its folder; elsewhere the caret moves
            guard !pickingFolder, selected == 0 else { return false }
            pickFolder()
        case .left, .space: return false // the caret and spaces belong to the field
        case .optionsDown, .optionsUp: break
        }
        return true
    }

    /// the options are open: ↑ ↓ go from one to the next, ← → change the value, esc folds them away
    private func handleOptions(_ key: Key, _ row: Int) -> Bool {
        let last = LaunchOptions.all.count - 1
        switch key {
        case .up: optionRow = row == 0 ? nil : row - 1
        case .down: optionRow = min(last, row + 1)
        case .tab: optionRow = row == last ? 0 : row + 1
        case .jumpUp, .escape: optionRow = nil
        case .jumpDown: optionRow = last
        case .left: step(row, by: -1)
        case .right: step(row, by: 1)
        case .enter, .openNew: submit()
        case .space, .optionsDown, .optionsUp: break
        }
        return true
    }

    /// tab while picking a folder: the lit folder goes into the field and its subfolders are listed
    func complete() {
        guard pickingFolder, let selected, rows.indices.contains(selected) else { return }
        text = rows[selected]
    }

    /// enter: while picking, choose the lit folder (or what is typed); in the list, act on the lit
    /// line, and with nothing lit start the new session
    func submit() {
        if pickingFolder { choose(target); return }
        act(on: selected ?? 0)
    }

    func open(row: String) { choose(row) }
    func close() { onClose() }
}
