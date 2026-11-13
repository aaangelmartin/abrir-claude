@testable import OpenClaude
import AppKit
import SwiftUI
import Testing

/// renders the palette off screen to png, to look at it without opening a window. runs only with
/// SNAPSHOT_DIR set: SNAPSHOT_DIR=/tmp/shots swift test --filter Snapshot
@MainActor
@Suite struct SnapshotTests {
    let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]

    private func shot(_ name: String, _ setUp: (PaletteModel) -> Void) {
        guard let dir else { return }
        let model = PaletteModel()
        setUp(model)
        let view = NSHostingView(rootView: PaletteView(model: model).environment(\.colorScheme, .dark))
        view.appearance = NSAppearance(named: .darkAqua)
        let size = view.fittingSize
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    @Test func empty() { shot("1-empty") { m in m.reset(); m.live = []; m.usage = Usage(session: .init(percent: 6, resetsAt: Date().addingTimeInterval(8040)), week: .init(percent: 84, resetsAt: Date().addingTimeInterval(270000))) } }
    @Test func typing() { shot("2-typing") { m in m.projects = Self.sample(); m.text = "Dev" } }
    @Test func optionsFolded() { shot("3-folded") { m in m.reset(); m.text = "Developer"; _ = m.handle(.enter); m.usage = Usage(session: .init(percent: 6, resetsAt: Date().addingTimeInterval(8040)), week: .init(percent: 84, resetsAt: Date().addingTimeInterval(270000))); m.pick(2, of: 0); m.pick(4, of: 1); m.pick(3, of: 2) } }
    @Test func optionsOpen() { shot("4-open") { m in m.reset(); m.pick(2, of: 0); m.pick(3, of: 1); m.pick(5, of: 2); m.text = "Developer"; _ = m.handle(.enter); _ = m.handle(.optionsDown); _ = m.handle(.down) } }
    @Test func optionsMax() { shot("5-max") { m in m.reset(); m.pick(5, of: 1); m.pick(2, of: 2); m.text = "Developer"; _ = m.handle(.enter); _ = m.handle(.optionsDown); _ = m.handle(.down) } }
    @Test func optionsPermissions() { shot("7-permissions") { m in m.reset(); m.pick(1, of: 0); m.pick(4, of: 2); m.text = "Developer"; _ = m.handle(.enter); _ = m.handle(.optionsDown); _ = m.handle(.down); _ = m.handle(.down) } }
    @Test func optionsBypass() { shot("8-bypass") { m in m.reset(); m.pick(0, of: 1); m.pick(5, of: 2); m.text = "Developer"; _ = m.handle(.enter); _ = m.handle(.optionsDown); _ = m.handle(.down); _ = m.handle(.down) } }
    @Test func optionsAllDefaultOpen() { shot("9-defaults-open") { m in m.reset(); for i in 0..<3 { m.pick(0, of: i) }; m.text = "Developer"; _ = m.handle(.enter); _ = m.handle(.optionsDown) } }
    private static func sample() -> [String: ProjectInfo] {
        let home = FolderPath.home
        let s = (0..<4).map { SessionInfo(id: "s\($0)", title: ["Add plan usage to the palette", "Fuzzy project search like T3 Code", "Fix the effort slider", "Translate everything to English"][$0], updated: Date().addingTimeInterval(-Double($0 + 1) * 5000)) }
        return [
            home + "/Developer/open-claude": ProjectInfo(path: home + "/Developer/open-claude", lastUsed: Date().addingTimeInterval(-600), sessions: s, branch: "feat/open-claude"),
            home + "/Developer": ProjectInfo(path: home + "/Developer", lastUsed: Date().addingTimeInterval(-86_400 * 2)),
        ]
    }
    @Test func active() { shot("13-active") { m in
        m.reset(); m.projects = Self.sample()
        let now = Date()
        m.live = [
            LiveSession(pid: 1, sessionId: "a", cwd: FolderPath.home + "/Desktop/laaabs", name: "Brain & Ranking", state: .waiting, waitingFor: "permission", since: now.addingTimeInterval(-40)),
            LiveSession(pid: 2, sessionId: "b", cwd: FolderPath.home + "/Developer/open-claude", name: "open-claude-a1", state: .busy, waitingFor: nil, since: now.addingTimeInterval(-300)),
            LiveSession(pid: 3, sessionId: "c", cwd: FolderPath.home + "/Developer/Priv8", name: "priv8-f3", state: .busy, waitingFor: nil, since: now.addingTimeInterval(-90)),
            LiveSession(pid: 4, sessionId: "d", cwd: FolderPath.home, name: "aaangel-62", state: .idle, waitingFor: nil, since: now.addingTimeInterval(-7200)),
        ]
        m.refreshRows(); m.selected = 1; m.usage = Usage(session: .init(percent: 6, resetsAt: Date().addingTimeInterval(8040)), week: .init(percent: 71, resetsAt: Date().addingTimeInterval(270000)))
    } }
    @Test func recents() { shot("12-step") { m in m.reset(); m.projects = Self.sample(); m.text = "Developer/open-claude"; _ = m.handle(.enter) } }
    @Test func fuzzy() { shot("10-fuzzy") { m in m.reset(); m.projects = Self.sample(); m.text = "abr" } }
    @Test func newMode() { shot("11-new") { m in m.reset(); m.projects = Self.sample(); m.text = "Developer"; _ = m.handle(.enter) } }
    @Test func optionsDefault() { shot("6-default") { m in m.reset(); for i in 0..<3 { m.pick(0, of: i) } } }
}
