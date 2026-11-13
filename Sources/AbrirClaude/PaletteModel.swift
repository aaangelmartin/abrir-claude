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
    }

    enum Key {
        case up, down, left, right, enter, tab, escape, space
        case jumpDown, jumpUp // ⌘↓ ⌘↑
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

    /// the picked value of each launch option, remembered between launches
    @Published private(set) var picks: [Int] = LaunchOptions.load()
    /// the option the arrows are on (the options are open while it is set), nil on the field and folders
    @Published private(set) var optionRow: Int?
    /// which way the last change went (-1 back, 1 forward), so a carousel slides the right way
    private(set) var lastDelta = 1
    var optionsOpen: Bool { optionRow != nil }
    /// the newest number of each model family, as the installed claude knows them
    @Published private(set) var modelVersions: [String: String] = ModelVersions.cached(for: ModelVersions.binary()) ?? [:]
    private var versionsBinary: String?

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

    func reset() {
        refreshModelVersions()
        notice = nil
        optionRow = nil
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
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            rows = Recents.all
            showingRecents = !rows.isEmpty
        } else {
            rows = Suggestions.completions(for: text)
            showingRecents = false
        }
        selectedByPointer = false
        selected = Self.defaultSelection(text: text, rows: rows)
    }

    /// what is lit before any key or pointer moves: the first match, so tab and enter take what is seen.
    /// nothing when the field is empty (enter opens home) or when what is typed is already a folder whose
    /// subfolders are listed (enter opens that folder, not one of them).
    static func defaultSelection(text: String, rows: [String], home: String = FolderPath.home) -> Int? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, let first = rows.first else { return nil }
        let typed = FolderPath.resolve(text, home: home)
        guard FolderPath.isDirectory(typed) else { return 0 }
        // "Developer" typed and "Developer/" offered: the same folder, light it
        return FolderPath.resolve(first, home: home).trimmingSlash == typed.trimmingSlash ? 0 : nil
    }

    /// what enter would open now
    var target: String {
        if let selected, rows.indices.contains(selected) { return rows[selected] }
        return text
    }

    /// the pointer moved onto a row
    func point(at index: Int) {
        guard rows.indices.contains(index), selected != index else { return }
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
        LaunchOptions.save(picks)
    }

    /// open the options on one of them (a click on the summary line, ⌘↓)
    func openOptions(at row: Int = 0) { optionRow = row }
    func closeOptions() { optionRow = nil }

    // MARK: keys

    /// one key, wherever the arrows are. false: not ours, the field gets it (←→ move the caret there,
    /// space types a space).
    func handle(_ key: Key) -> Bool {
        if let optionRow { return handleOptions(key, optionRow) }
        return handleField(key)
    }

    private func handleField(_ key: Key) -> Bool {
        switch key {
        case .down:
            if rows.isEmpty { optionRow = 0; return true }
            selectedByPointer = false
            if let selected {
                if selected == rows.count - 1 { optionRow = 0 } else { self.selected = selected + 1 }
            } else {
                selected = 0
            }
        case .up:
            guard !rows.isEmpty else { return true }
            selectedByPointer = false
            if let selected { self.selected = selected == 0 ? nil : selected - 1 } else { selected = rows.count - 1 }
        case .jumpDown: optionRow = 0
        case .jumpUp: selected = Self.defaultSelection(text: text, rows: rows)
        case .tab: complete()
        case .enter: submit()
        case .escape: close()
        case .left, .right, .space: return false // the caret and spaces belong to the field
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
        case .space: break // the field keeps its text
        }
        return true
    }

    /// tab: the lit row goes into the field and the rows go one level down. with nothing lit, the first
    /// tab lights the first row, so tab never acts on something unseen.
    func complete() {
        guard !rows.isEmpty else { NSSound.beep(); return }
        guard let selected, rows.indices.contains(selected) else {
            selectedByPointer = false
            self.selected = 0
            return
        }
        text = rows[selected]
    }

    func submit() { onOpen(target, LaunchOptions.args(for: picks)) }
    func open(row: String) { onOpen(row, LaunchOptions.args(for: picks)) }
    func close() { onClose() }
}

private extension String {
    var trimmingSlash: String { count > 1 && hasSuffix("/") ? String(dropLast()) : self }
}
