import AppKit
import Combine

/// the palette's state: what is typed, the folders under it, the launch options at the bottom, and
/// where the arrows are (the field and its folders, or one of the options, which then open up).
@MainActor
final class PaletteModel: ObservableObject {
    enum Notice: Equatable {
        /// macOS said no to controlling terminal
        case notAllowed
        case failed(String)
        /// a running session whose window could not be found
        case windowNotFound(String)
    }

    enum Key {
        case up, down, left, right, enter, tab, escape, space
        case jumpDown, jumpUp // ⌘↓ ⌘↑
        case optionsDown, optionsUp // ⌥↓ ⌥↑: open and fold the options
        case openNew // ⌘↵: a new session straight away, no session list
    }

    @Published var text = "" { didSet { if text != oldValue { textChanged() } } }
    @Published private(set) var rows: [String] = []
    @Published private(set) var showingRecents = false
    /// the one lit folder, and what tab and enter act on. nil: enter opens what is typed.
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
    /// the option the arrows are on (the options are open while it is set), nil on the field and folders
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
    /// the folder whose claude sessions are listed instead of the folders, nil for the folders
    @Published private(set) var sessionsFolder: String?
    /// the lit line in the sessions: 0 is a new session, then each session newest first
    @Published var sessionSelected = 0
    /// claude code sessions running now on this mac, read again while the palette is open
    @Published var live: [LiveSession] = []
    /// the lit active session, when the arrows are on one (then no folder is lit)
    @Published var liveSelected: Int?
    /// asks the panel to bring a running session forward
    var onFocus: (LiveSession) -> Void = { _ in }
    /// at most this many active sessions are listed before anything is typed
    static let liveLimit = 5

    /// whether the field's caret is at the end of what is typed (→ there opens a folder's sessions)
    var caretAtEnd: () -> Bool = { true }

    init() { refreshModelVersions() }

    /// asks the panel to open a folder (raw, as typed, with the flags) or to close
    var onOpen: (String, [String]) -> Void = { _, _ in }
    var onClose: () -> Void = {}

    // MARK: folders

    /// the folder part of what is typed ("Developer/" in "Developer/Pr"), dimmed in the rows
    var typedParent: String {
        guard let slash = text.lastIndex(of: "/") else { return "" }
        return String(text[...slash])
    }

    /// the active sessions listed now: the most urgent few with nothing typed, the matching ones while
    /// a name is typed, none while a path is
    var shownLive: [LiveSession] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return Array(live.prefix(Self.liveLimit)) }
        if typed.contains("/") || typed.hasPrefix("~") { return [] }
        return live
            .compactMap { s -> (LiveSession, Int)? in
                let a = Fuzzy.score(typed, s.name), b = Fuzzy.score(typed, FolderPath.display(s.cwd))
                guard let best = [a, b].compactMap({ $0 }).max() else { return nil }
                return (s, best)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.liveLimit)
            .map(\.0)
    }

    func refreshLive() {
        let now = LiveSessions.all()
        if now != live { live = now }
        if let i = liveSelected, i >= shownLive.count { liveSelected = shownLive.isEmpty ? nil : shownLive.count - 1 }
    }

    /// the pointer moved onto an active session
    func pointLive(at index: Int) {
        guard shownLive.indices.contains(index), liveSelected != index else { return }
        selected = nil
        liveSelected = index
    }

    func focusLive(_ index: Int) {
        let list = shownLive
        guard list.indices.contains(index) else { return }
        onFocus(list[index])
    }

    func reset() {
        refreshLive()
        liveSelected = nil
        refreshModelVersions()
        refreshProjects()
        sessionsFolder = nil
        refreshUsage()
        picks = LaunchOptions.all.map { _ in 0 }
        notice = nil
        optionRow = nil
        text = ""
        refreshRows()
    }

    private func textChanged() {
        // typing always happens in the field: the arrows go back there
        optionRow = nil
        sessionsFolder = nil
        refreshRows()
    }

    func refreshRows() {
        liveSelected = nil
        listID = UUID()
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty {
            rows = recentRows()
            showingRecents = !rows.isEmpty
        } else if typed.contains("/") || typed.hasPrefix("~") {
            // a path being typed: its subfolders, as a shell completes them
            rows = Suggestions.completions(for: text)
            showingRecents = false
        } else {
            rows = fuzzyRows(typed)
            showingRecents = false
        }
        selectedByPointer = false
        // nothing is lit until an arrow or the pointer lights it
        selected = nil
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
                if self.sessionsFolder == nil, self.optionRow == nil { self.refreshRows() }
            }
        }
    }

    /// what a row is, when it is a known project
    func info(for row: String) -> ProjectInfo? {
        projects[ProjectIndex.trimmed(FolderPath.resolve(row))]
    }

    /// with nothing typed: the folders used last, here or in claude, newest first
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

    // MARK: sessions

    var sessionList: [SessionInfo] { sessionsFolder.flatMap { info(for: $0)?.sessions } ?? [] }

    /// list a folder's claude sessions in place of the folders
    func openSessions(of row: String) {
        guard info(for: row)?.sessions.isEmpty == false else { return }
        sessionSelected = 0
        sessionsFolder = row
    }

    func closeSessions() { sessionsFolder = nil }

    /// open claude in the folder: a new session (0) or one of its sessions resumed
    func openSession(_ index: Int) {
        guard let folder = sessionsFolder else { return }
        if index == 0 { onOpen(folder, LaunchOptions.args(for: picks)); return }
        let list = sessionList
        guard list.indices.contains(index - 1) else { return }
        onOpen(folder, LaunchOptions.args(for: picks) + ["--resume", list[index - 1].id])
    }

    private func handleSessions(_ key: Key) -> Bool {
        let last = sessionList.count
        switch key {
        case .up: sessionSelected = max(0, sessionSelected - 1)
        case .down: sessionSelected = min(last, sessionSelected + 1)
        case .jumpUp: sessionSelected = 0
        case .jumpDown: sessionSelected = last
        case .enter: openSession(sessionSelected)
        case .openNew: openSession(0)
        case .left, .escape: closeSessions()
        case .right, .tab, .space, .optionsDown, .optionsUp: break
        }
        return true
    }

    /// what enter would open now
    var target: String {
        if let selected, rows.indices.contains(selected) { return rows[selected] }
        return text
    }

    /// the pointer moved onto a row
    func point(at index: Int) {
        guard rows.indices.contains(index), selected != index else { return }
        liveSelected = nil
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
        // the options open and fold from anywhere
        if key == .optionsDown { optionRow = optionRow ?? 0; return true }
        if key == .optionsUp { optionRow = nil; return true }
        if sessionsFolder != nil, optionRow == nil { return handleSessions(key) }
        if let optionRow { return handleOptions(key, optionRow) }
        return handleField(key)
    }

    /// the arrows on an active session: up and down through them and on into the folders, enter goes
    /// to it, ⌘↵ opens a new session in its folder
    private func handleLive(_ key: Key, _ index: Int) -> Bool {
        let count = shownLive.count
        switch key {
        case .down:
            if index < count - 1 { liveSelected = index + 1 } else if !rows.isEmpty { liveSelected = nil; selectedByPointer = false; selected = 0 }
        case .up: liveSelected = index == 0 ? nil : index - 1
        case .jumpUp: liveSelected = nil
        case .jumpDown: if !rows.isEmpty { liveSelected = nil; selected = rows.count - 1 } else { liveSelected = count - 1 }
        case .enter: focusLive(index)
        case .openNew:
            let s = shownLive[index]
            onOpen(FolderPath.display(s.cwd), LaunchOptions.args(for: picks))
        case .escape: close()
        case .left, .right, .space: return false
        case .tab, .optionsDown, .optionsUp: break
        }
        return true
    }

    private func handleField(_ key: Key) -> Bool {
        if let liveSelected, shownLive.indices.contains(liveSelected) { return handleLive(key, liveSelected) }
        switch key {
        case .down:
            // the active sessions come first, then the folders; the last row is the end
            if selected == nil, !shownLive.isEmpty { liveSelected = 0; return true }
            guard !rows.isEmpty else { return true }
            selectedByPointer = false
            if let selected { self.selected = min(selected + 1, rows.count - 1) } else { selected = 0 }
        case .up:
            // at the top already: stay there, never wrap round to the bottom
            guard !rows.isEmpty, let selected else { return true }
            selectedByPointer = false
            if selected == 0, !shownLive.isEmpty {
                self.selected = nil
                liveSelected = shownLive.count - 1
            } else {
                self.selected = selected == 0 ? nil : selected - 1
            }
        case .jumpDown: if !rows.isEmpty { selectedByPointer = false; selected = rows.count - 1 }
        case .jumpUp: selected = nil
        case .openNew: openNew()
        case .optionsDown, .optionsUp: break
        case .tab: complete()
        case .enter: submit()
        case .escape: close()
        case .right:
            // → at the end of the text opens the lit folder's sessions; elsewhere it moves the caret
            guard caretAtEnd(), let selected, rows.indices.contains(selected),
                  info(for: rows[selected])?.sessions.isEmpty == false else { return false }
            openSessions(of: rows[selected])
        case .left, .space: return false // the caret and spaces belong to the field
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
        case .enter: submit()
        case .openNew: openNew()
        case .space, .optionsDown, .optionsUp: break // the field keeps its text
        }
        return true
    }

    /// tab: the lit row goes into the field and the rows go one level down. with nothing lit, tab
    /// does nothing.
    func complete() {
        guard let selected, rows.indices.contains(selected) else { return }
        text = rows[selected]
    }

    /// enter: the lit row, or what is typed. a name that is no folder (typed to search) with nothing
    /// lit opens nothing: a terminal with a cd error helps no one.
    /// enter on a folder with claude sessions lists them (a new one first) to pick from; a folder
    /// without any opens straight away.
    func submit() {
        guard targetIsOpenable else { NSSound.beep(); return }
        if info(for: target)?.sessions.isEmpty == false {
            optionRow = nil
            openSessions(of: target)
        } else {
            onOpen(target, LaunchOptions.args(for: picks))
        }
    }

    /// ⌘↵, or the shortcut again: a new session in the folder now, without the list
    func openNew() {
        if sessionsFolder != nil { openSession(0); return }
        guard targetIsOpenable else { NSSound.beep(); return }
        onOpen(target, LaunchOptions.args(for: picks))
    }

    private var targetIsOpenable: Bool {
        let typed = text.trimmingCharacters(in: .whitespaces)
        return selected != nil || typed.isEmpty || FolderPath.isDirectory(FolderPath.resolve(typed))
    }
    func open(row: String) { onOpen(row, LaunchOptions.args(for: picks)) }
    func close() { onClose() }
}

private extension String {
    var trimmingSlash: String { count > 1 && hasSuffix("/") ? String(dropLast()) : self }
}
