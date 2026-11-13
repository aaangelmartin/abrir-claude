import AppKit
import SwiftUI

/// the palette, built as claude desktop's quick entry: one 56 pt bar with the starburst in a 56 pt
/// cell and the field beside it, no field border, no focus ring. folders (recent while empty, matching
/// while typing) open under a hairline inside the same card and scroll past seven. at the bottom, the
/// launch options: one summary line that opens into four rows, each changed with ← →.
struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    @FocusState private var fieldFocused: Bool
    private let theme = PaletteTheme.current

    /// claude's quick entry window is 606 wide; its bar fills it
    static let width: CGFloat = 606
    static let radius: CGFloat = 16
    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 36
    static let visibleRows = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar

            if let notice = model.notice {
                divider
                noticeView(notice)
            }

            if model.sessionsFolder != nil {
                divider
                SessionList(model: model, theme: theme)
            } else if !model.rows.isEmpty {
                divider
                rowsView
            }

            divider
            OptionsSection(model: model, theme: theme)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            LinearGradient(colors: [theme.gradientTop, theme.gradientBottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.radius))
        .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(theme.ring, lineWidth: 0.5))
        .onAppear { fieldFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .paletteDidShow)) { _ in fieldFocused = true }
    }

    // MARK: the bar

    private var bar: some View {
        HStack(spacing: 0) {
            ClaudeMark(color: theme.mark)
                .frame(width: 18, height: 18)
                .frame(width: Self.barHeight, height: Self.barHeight)
            TextField(
                "", text: $model.text,
                prompt: Text(theme.say("Which folder should Claude open in?")).foregroundStyle(theme.placeholder)
            )
            .textFieldStyle(.plain)
            .font(theme.input)
            .foregroundStyle(theme.text)
            .focused($fieldFocused)
            .autocorrectionDisabled()
            .frame(height: 24)
            .padding(.trailing, 30)
        }
        .frame(height: Self.barHeight)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 0.5)
    }

    // MARK: folders

    private var rowsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showingRecents {
                Text(theme.say("Recent"))
                    .font(theme.label)
                    .foregroundStyle(theme.textMuted)
                    .padding(.leading, Self.barHeight)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
            }
            FolderList(model: model, theme: theme)
                // a new list (typing, tab) is a new scroll view: it always starts at the top, same margins
                .id(model.listID)
        }
    }

    // MARK: permission notice

    private func noticeView(_ notice: PaletteModel.Notice) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(theme.icon)
                .frame(width: Self.barHeight)
            Group {
                switch notice {
                case .notAllowed: Text(theme.say("Open Claude needs permission to control Terminal."))
                case let .failed(message): Text(theme.say("Terminal did not respond: ") + message)
                }
            }
            .font(theme.row)
            .foregroundStyle(theme.textRow)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if notice == .notAllowed {
                Button(theme.say("Open Settings")) { Permissions.openAutomationSettings() }
                    .buttonStyle(ClaudeButtonStyle(theme: theme))
            }
        }
        .padding(.vertical, 12)
        .padding(.trailing, 14)
    }
}

/// the folders under the bar: seven rows tall, then it scrolls, with a thin thumb of its own (no system
/// track) and soft edges where there is more to see.
private struct FolderList: View {
    @ObservedObject var model: PaletteModel
    let theme: PaletteTheme
    /// where the pointer was when this list appeared: a row under a pointer that has not moved is not
    /// picked, only one the pointer moves onto
    @State private var pointerAtStart = NSEvent.mouseLocation

    @State private var metrics = ScrollMetrics()
    @State private var thumbVisible = false
    @State private var hideThumb: Task<Void, Never>?
    @State private var pointerInside = false

    private static let padding: CGFloat = 6
    private static let fade: CGFloat = 18
    private static let topID = -1
    private static let endID = Int.max
    private var rowHeight: CGFloat { PaletteView.rowHeight }
    private var visibleHeight: CGFloat {
        CGFloat(min(model.rows.count, PaletteView.visibleRows)) * rowHeight + Self.padding * 2
    }
    private var overflows: Bool { model.rows.count > PaletteView.visibleRows }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: Self.padding).id(Self.topID)
                    ForEach(Array(model.rows.enumerated()), id: \.element) { index, row in
                        FolderRow(
                            row: row, prefix: model.typedParent, theme: theme,
                            isSelected: index == model.selected,
                            info: model.showingRecents ? nil : model.info(for: row),
                            openSessions: { model.openSessions(of: row) }
                        )
                        .id(index)
                        .onContinuousHover { phase in
                            guard case .active = phase, NSEvent.mouseLocation != pointerAtStart else { return }
                            model.point(at: index)
                        }
                        .onTapGesture { model.open(row: row) }
                    }
                    Color.clear.frame(height: Self.padding).id(Self.endID)
                }
            }
            .scrollIndicators(.never)
            .modifier(TrackScroll(metrics: $metrics, onScroll: flashThumb))
            .frame(height: visibleHeight)
            .mask(edgeFade)
            .overlay(alignment: .topTrailing) { thumb }
            .onHover { inside in
                pointerInside = inside
                if inside { flashThumb() }
            }
            .onChange(of: model.selected) { old, selected in
                guard let selected, !model.selectedByPointer else { return }
                reveal(selected, movingDown: (old ?? -1) < selected, proxy: proxy)
            }
        }
    }

    /// scrolls only when the picked row is not fully clear of the soft edges, and then leaves the next
    /// row peeking past it, as a native list does
    private func reveal(_ index: Int, movingDown: Bool, proxy: ScrollViewProxy) {
        guard overflows else { return }
        let top = Self.padding + CGFloat(index) * rowHeight
        let clearTop = metrics.offset + (metrics.offset > 1 ? Self.fade : 0)
        let clearBottom = metrics.offset + metrics.container - Self.fade
        guard top < clearTop || top + rowHeight > clearBottom else { return }
        let below = top + rowHeight > clearBottom
        if below {
            proxy.scrollTo(index + 1 < model.rows.count ? index + 1 : Self.endID, anchor: .bottom)
        } else {
            proxy.scrollTo(index > 0 ? index - 1 : Self.topID, anchor: .top)
        }
        flashThumb()
    }

    // MARK: soft edges

    private var edgeFade: some View {
        let fade = Self.fade
        let top = overflows && metrics.offset > 1
        let bottom = overflows && metrics.offset < metrics.content - metrics.container - 1
        return VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(top ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(bottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
        .animation(.easeOut(duration: 0.15), value: top)
        .animation(.easeOut(duration: 0.15), value: bottom)
    }

    // MARK: the thumb

    @ViewBuilder private var thumb: some View {
        if overflows, metrics.content > metrics.container, metrics.container > 0 {
            let inset: CGFloat = 6
            let track = metrics.container - inset * 2
            let height = max(28, track * metrics.container / metrics.content)
            let travel = track - height
            let progress = min(max(metrics.offset / (metrics.content - metrics.container), 0), 1)
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 5, height: height)
                .offset(x: -4, y: inset + travel * progress)
                .opacity(thumbVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: thumbVisible)
                .allowsHitTesting(false)
        }
    }

    /// show the thumb, then hide it a moment after the list stops moving (unless the pointer is on it)
    private func flashThumb() {
        guard overflows else { return }
        thumbVisible = true
        hideThumb?.cancel()
        hideThumb = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            if !pointerInside { thumbVisible = false }
        }
    }
}

struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var container: CGFloat = 0
}

/// reads where the list is scrolled (macOS 15 and later; earlier, no thumb and no fades)
private struct TrackScroll: ViewModifier {
    @Binding var metrics: ScrollMetrics
    let onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                ScrollMetrics(offset: geo.contentOffset.y + geo.contentInsets.top,
                              content: geo.contentSize.height, container: geo.containerSize.height)
            } action: { old, new in
                metrics = new
                if old.offset != new.offset, old.content == new.content { onScroll() }
            }
        } else {
            content
        }
    }
}

/// one folder: the part already typed dimmed, the folder's own name in full.
private struct FolderRow: View {
    let row: String
    let prefix: String
    let theme: PaletteTheme
    let isSelected: Bool
    /// its branch, when it was last used and its claude sessions, for a known project
    var info: ProjectInfo?
    var openSessions: () -> Void = {}

    var body: some View {
        let (parent, name) = split
        HStack(spacing: 0) {
            // the icon sits in the starburst's column, the name lines up with what is typed
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? theme.text : theme.icon)
                .frame(width: PaletteView.barHeight - 16)
                .padding(.trailing, 8)
            (Text(parent).foregroundStyle(theme.textMuted)
                + Text(name.hasSuffix("/") ? String(name.dropLast()) : name) // the trailing slash is for tab, not for reading
                    .foregroundStyle(isSelected ? theme.text : theme.textRow))
                .font(theme.row)
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(1)
            Spacer(minLength: 12)
            if let info { meta(info) }
        }
        .padding(.trailing, 10)
        .frame(height: PaletteView.rowHeight)
        .background(
            isSelected ? theme.rowSelected : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    /// on the right: the branch, how long ago it was used, and its sessions (click, or → when lit)
    private func meta(_ info: ProjectInfo) -> some View {
        HStack(spacing: 12) {
            if let branch = info.branch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5))
                    Text(branch).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: 140, alignment: .trailing)
            }
            if let used = info.lastUsed { Text(Ago.short(used) == "now" ? "just now" : Ago.short(used) + " ago").monospacedDigit() }
            if !info.sessions.isEmpty {
                HStack(spacing: 3) {
                    Text(info.sessions.count == 1 ? "1 session" : "\(info.sessions.count) sessions").monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(isSelected ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onTapGesture(perform: openSessions)
                .help(isSelected ? "Sessions (→)" : "Sessions")
            }
        }
        .font(theme.label)
        .foregroundStyle(isSelected ? theme.textSecondary : theme.textMuted.opacity(0.8))
        .lineLimit(1)
    }

    /// "Developer/Priv8/" with "Developer/" typed: ("Developer/", "Priv8/"). recents have no typed
    /// part, so their own parent folders are dimmed instead.
    private var split: (String, String) {
        if !prefix.isEmpty, row.hasPrefix(prefix) { return (prefix, String(row.dropFirst(prefix.count))) }
        let trimmed = row.hasSuffix("/") ? String(row.dropLast()) : row
        guard let slash = trimmed.lastIndex(of: "/") else { return ("", row) }
        return (String(row[...slash]), String(row[row.index(after: slash)...]))
    }
}

private struct ClaudeButtonStyle: ButtonStyle {
    let theme: PaletteTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonFont)
            .foregroundStyle(theme.buttonText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(theme.button.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// the starburst, from the path claude's quick entry draws.
struct ClaudeMark: View {
    let color: Color

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "claude", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().renderingMode(.template)
            } else {
                Image(systemName: "sparkle").resizable()
            }
        }
        .aspectRatio(contentMode: .fit)
        .foregroundStyle(color)
    }
}

/// a folder's claude sessions, in place of the folders: a header with the folder (← goes back), then
/// a new session and each session newest first, by title, with how long ago it ran. enter opens the
/// lit one (claude --resume for a session); the launch options below still apply.
private struct SessionList: View {
    @ObservedObject var model: PaletteModel
    let theme: PaletteTheme

    var body: some View {
        let sessions = model.sessionList
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text(model.sessionsFolder.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 } ?? "")
                    .foregroundStyle(theme.textRow)
                if let branch = model.sessionsFolder.flatMap({ model.info(for: $0)?.branch }) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5)).padding(.leading, 6)
                    Text(branch)
                }
                Spacer()
                Text(theme.say("\(sessions.count) sessions"))
            }
            .font(theme.label)
            .foregroundStyle(theme.textMuted)
            .padding(.leading, 22)
            .padding(.trailing, 20)
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture { model.closeSessions() }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        line(0, icon: "plus", title: theme.say("New session"), time: nil)
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                            line(i + 1, icon: "text.bubble", title: s.title, time: Ago.short(s.updated))
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.never)
                .frame(height: CGFloat(min(sessions.count + 1, PaletteView.visibleRows)) * PaletteView.rowHeight + 12)
                .onChange(of: model.sessionSelected) { _, i in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(i) }
                }
            }
        }
    }

    private func line(_ index: Int, icon: String, title: String, time: String?) -> some View {
        let on = index == model.sessionSelected
        return HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(on ? theme.text : theme.icon)
                .frame(width: PaletteView.barHeight - 16)
                .padding(.trailing, 8)
            Text(title)
                .font(theme.row)
                .foregroundStyle(on ? theme.text : theme.textRow)
                .lineLimit(1)
            Spacer(minLength: 12)
            if let time {
                Text(time).font(theme.label).monospacedDigit().foregroundStyle(theme.textMuted)
            }
        }
        .padding(.trailing, 12)
        .frame(height: PaletteView.rowHeight)
        .background(on ? theme.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .id(index)
        .onHover { if $0 { model.sessionSelected = index } }
        .onTapGesture { model.openSession(index) }
    }
}

/// how long ago, as short as a list wants it: now, 5m, 3h, 2d, 3w, 4mo
enum Ago {
    static func short(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86_400: return "\(Int(s / 3600))h"
        case ..<(86_400 * 14): return "\(Int(s / 86_400))d"
        case ..<(86_400 * 60): return "\(Int(s / 604_800))w"
        default: return "\(Int(s / 2_592_000))mo"
        }
    }
}

extension Notification.Name {
    static let paletteDidShow = Notification.Name("paletteDidShow")
}
