import AppKit
import Combine

/// the palette's state. three tabs, each doing one thing:
/// - running (where it opens): the claude code sessions running now. enter goes to one.
/// - resume: past sessions, newest first. enter resumes one in its folder.
/// - new: folders, with the launch options below. enter starts claude there.
/// tab and ⇧tab walk the tabs, ⌘1 ⌘2 ⌘3 jump to one, the shortcut again goes to new.
@MainActor
final class PaletteModel: ObservableObject {
    enum Mode: Int, CaseIterable { case running, resume, new }

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
        case openNew // ⌘↵: a new session straight away
        case newMode // ⌘N: the new tab
        case backTab // ⇧tab: the tab before
        case tabNumber(Int) // ⌘1 ⌘2 ⌘3
    }

    @Published private(set) var mode: Mode = .running
    @Published var text = "" { didSet { if text != oldValue { textChanged() } } }
    /// the folders listed in the new session mode
    @Published private(set) var rows: [String] = []
    @Published private(set) var showingRecents = false
    /// the lit line of the list shown (sessions: running ones then past ones; new: folders), nil on
    /// the field
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
        mode = .running
        refreshLive()
        refreshModelVersions()
        refreshProjects()
        refreshUsage()
        picks = LaunchOptions.all.map { _ in 0 }
        notice = nil
        optionRow = nil
        text = ""
        refreshRows()
    }

    /// to a tab (or the next one); the field starts empty in each
    func switchMode(to new: Mode? = nil) {
        mode = new ?? Mode(rawValue: (mode.rawValue + 1) % Mode.allCases.count)!
        optionRow = nil
        if text.isEmpty { refreshRows() } else { text = "" }
    }

    private func textChanged() {
        // typing always happens in the field: the arrows go back there
        optionRow = nil
        refreshRows()
    }

    func refreshRows() {
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

    // MARK: sessions mode

    /// every running session, or the ones whose name or folder matches what is typed
    var shownLive: [LiveSession] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return live }
        return live
            .compactMap { s -> (LiveSession, Int)? in
                let a = Fuzzy.score(typed, s.name), b = Fuzzy.score(typed, FolderPath.display(s.cwd))
                guard let best = [a, b].compactMap({ $0 }).max() else { return nil }
                return (s, best)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// past sessions, newest first, without the ones running now; while something is typed, those
    /// whose title has every word typed or whose folder matches
    var pastShown: [(folder: String, session: SessionInfo)] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let words = typed.lowercased().split(separator: " ").map(String.init)
        let running = Set(live.map(\.sessionId))
        return projects.values
            .flatMap { p in p.sessions.map { (FolderPath.display(p.path), $0) } }
            .filter { folder, s in
                guard !running.contains(s.id) else { return false }
                guard !typed.isEmpty else { return true }
                let title = s.title.lowercased()
                return words.allSatisfy { title.contains($0) } || Fuzzy.score(typed, folder) != nil && folder.lowercased().contains(words[0])
            }
            .sorted { $0.1.updated > $1.1.updated }
            .prefix(200)
            .map { (folder: $0.0, session: $0.1) }
    }

    func refreshLive() {
        let now = LiveSessions.all()
        if now != live { live = now }
        if mode == .running, let i = selected, i >= count { selected = count == 0 ? nil : count - 1 }
    }

    /// how many lines the current tab lists
    var count: Int {
        switch mode {
        case .running: shownLive.count
        case .resume: pastShown.count
        case .new: rows.count
        }
    }

    /// enter on a line: go to the running session, or resume the past one in its folder
    func act(on index: Int) {
        switch mode {
        case .running:
            let running = shownLive
            if running.indices.contains(index) { onFocus(running[index]) }
        case .resume:
            let past = pastShown
            guard past.indices.contains(index) else { return }
            onOpen(past[index].folder, LaunchOptions.args(for: picks) + ["--resume", past[index].session.id])
        case .new:
            open(row: rows[index])
        }
    }

    /// the folder of a line, for ⌘↵ (a new session there)
    private func folder(of index: Int) -> String? {
        switch mode {
        case .running:
            let running = shownLive
            return running.indices.contains(index) ? FolderPath.display(running[index].cwd) : nil
        case .resume:
            let past = pastShown
            return past.indices.contains(index) ? past[index].folder : nil
        case .new:
            return rows.indices.contains(index) ? rows[index] : nil
        }
    }

    /// the shortcut pressed with the palette open: to the new tab, and from there a new session now
    func hotkeyAgain() {
        if mode == .new { openNew() } else { switchMode(to: .new) }
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

    /// what enter would open now in the new session mode
    var target: String {
        if let selected, rows.indices.contains(selected) { return rows[selected] }
        return text
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
        switch key {
        case .newMode: switchMode(to: .new); return true
        case .backTab: switchMode(to: Mode(rawValue: (mode.rawValue + Mode.allCases.count - 1) % Mode.allCases.count)); return true
        case let .tabNumber(n): if let m = Mode(rawValue: n - 1) { switchMode(to: m) }; return true
        default: break
        }
        if mode == .new, key == .optionsDown { optionRow = optionRow ?? 0; return true }
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
            // typing is cleared first, then the palette closes
            if text.isEmpty { close() } else { text = "" }
        case .enter: submit()
        case .openNew: openNew()
        case .tab:
            // the next tab; in new, with a folder lit, tab completes it instead
            if mode == .new, selected != nil { complete() } else { switchMode() }
        case .left, .right, .space: return false // the caret and spaces belong to the field
        case .optionsDown, .optionsUp, .newMode, .backTab, .tabNumber: break
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
        case .enter, .openNew: openNew()
        case .space, .optionsDown, .optionsUp, .newMode, .backTab, .tabNumber: break
        }
        return true
    }

    /// tab in the new session mode: the lit folder goes into the field and its subfolders are listed
    func complete() {
        guard mode == .new, let selected, rows.indices.contains(selected) else { return }
        text = rows[selected]
    }

    /// enter. sessions: go to the lit running session or resume the lit past one. new session:
    /// start claude in the lit folder, or in what is typed (home when nothing is)
    func submit() {
        if mode == .new { openNew(); return }
        guard let selected else { NSSound.beep(); return }
        act(on: selected)
    }

    /// ⌘↵, or the shortcut again: a new session now, in the lit line's folder, what is typed, or home
    func openNew() {
        if mode != .new {
            onOpen(selected.flatMap(folder(of:)) ?? "", LaunchOptions.args(for: picks))
            return
        }
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
