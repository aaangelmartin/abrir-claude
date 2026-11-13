import LaaabsKit
import SwiftUI

/// one easing for everything that moves in the options, so opening, focus and values feel as one
enum Motion {
    /// an ease out that starts quick and lands soft (claude's own expo-ish curve)
    static let open = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.42)
    static let close = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)
    static let focus = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let value = Animation.spring(response: 0.32, dampingFraction: 0.8)
    /// each open row follows the one above it by this much
    static let stagger = 0.035
}

/// the launch options at the foot of the palette, in order: model, effort, permissions, session.
/// folded: one line with each value painted as claude code paints it. open (↓ past the folders, ⌘↓,
/// or a click): a row per option, changed with ← →. the section has a known height either way, so the
/// card grows and shrinks smoothly; the summary steps aside and the rows come in one after another.
struct OptionsSection: View {
    @ObservedObject var model: PaletteModel
    let theme: PaletteTheme
    @Namespace private var focus

    static let foldedHeight: CGFloat = 44
    static let rowHeight: CGFloat = 40
    static let sliderHeight: CGFloat = 78
    static let modesHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 2
    static let padding: CGFloat = 8
    /// what a control may take: the card less the row's margins and the title column
    static let controlWidth: CGFloat = PaletteView.width - 16 - 12 - 88 - 14

    static func height(of option: LaunchOption) -> CGFloat {
        switch option.style {
        case .slider: sliderHeight
        case .modes: modesHeight
        case .segments: rowHeight
        }
    }

    static var openHeight: CGFloat {
        let rows = LaunchOptions.all.map(height(of:)).reduce(0, +)
        return rows + rowSpacing * CGFloat(LaunchOptions.all.count - 1) + padding * 2
    }

    var body: some View {
        let open = model.optionsOpen
        ZStack(alignment: .top) {
            if open {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(LaunchOptions.all.enumerated()), id: \.offset) { index, option in
                        OptionRow(model: model, index: index, option: option, theme: theme, focus: focus)
                    }
                }
                .padding(.vertical, Self.padding)
                // the rows bring themselves in; going away they all fade at once
                .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else {
                summary
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -4)).animation(.easeOut(duration: 0.22).delay(0.1)),
                        removal: .opacity.combined(with: .offset(y: -6)).animation(.easeOut(duration: 0.12))
                    ))
            }
        }
        .frame(height: open ? Self.openHeight : Self.foldedHeight, alignment: .top)
        .clipped()
        .animation(open ? Motion.open : Motion.close, value: open)
        .animation(Motion.focus, value: model.optionRow)
    }

    // MARK: folded

    private var summary: some View {
        HStack(spacing: 0) {
            item(LaunchOptions.model) {
                let pick = model.picks[LaunchOptions.model]
                Group {
                    if pick == 0 {
                        Text(theme.say("Model")).foregroundStyle(theme.textMuted)
                    } else {
                        ModelName(label: model.display(model.choice(of: LaunchOptions.model), of: LaunchOptions.model), on: true, theme: theme)
                    }
                }
            }
            dot
            item(LaunchOptions.effort) {
                HStack(spacing: 5) {
                    Text(theme.say("Effort")).foregroundStyle(theme.textMuted)
                    PaintedText(text: model.choice(of: LaunchOptions.effort).label, paint: model.choice(of: LaunchOptions.effort).paint, font: theme.chip, bold: model.picks[LaunchOptions.effort] != 0)
                }
            }
            dot
            item(LaunchOptions.permissions) {
                let choice = model.choice(of: LaunchOptions.permissions)
                let isDefault = model.picks[LaunchOptions.permissions] == 0
                HStack(spacing: 5) {
                    if let symbol = choice.symbol {
                        PaintedText(text: symbol, paint: choice.paint, font: .system(size: 10))
                    }
                    PaintedText(text: theme.say(isDefault ? "Permissions" : choice.label), paint: isDefault ? .plain(CC.inactive) : choice.paint, font: theme.chip, bold: !isDefault)
                }
            }
            dot
            item(LaunchOptions.session) {
                let choice = model.choice(of: LaunchOptions.session)
                HStack(spacing: 5) {
                    if let icon = choice.icon { Image(systemName: icon).font(.system(size: 10.5)) }
                    Text(theme.say(model.picks[LaunchOptions.session] == 0 ? "New session" : choice.label))
                }
                .foregroundStyle(model.picks[LaunchOptions.session] == 0 ? theme.textMuted : theme.text)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("⌘↓").font(theme.label)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.textMuted.opacity(0.7))
        }
        .font(theme.chip)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: Self.foldedHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.openOptions() }
    }

    private func item<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .onTapGesture { model.openOptions(at: index) }
    }

    private var dot: some View {
        Text("·").font(theme.chip).foregroundStyle(Color.white.opacity(0.25))
    }
}

/// a model's name with its number a step quieter: "Opus 5.5"
private struct ModelName: View {
    let label: String
    let on: Bool
    let theme: PaletteTheme

    var body: some View {
        if let space = label.lastIndex(of: " "), label[label.index(after: space)...].first?.isNumber == true {
            (Text(label[..<space]).foregroundStyle(on ? theme.text : theme.textSecondary)
                + Text(" " + label[label.index(after: space)...]).foregroundStyle(on ? theme.textSecondary : theme.textMuted))
        } else {
            Text(label).foregroundStyle(on ? theme.text : theme.textSecondary)
        }
    }
}

/// one option, open: its name in a column, its control after it; lit while the arrows are on it. the
/// light is one shape that glides from row to row. when the options open, each row drops in a moment
/// after the one above.
private struct OptionRow: View {
    @ObservedObject var model: PaletteModel
    let index: Int
    let option: LaunchOption
    let theme: PaletteTheme
    let focus: Namespace.ID
    @State private var shown = false

    var body: some View {
        let focused = model.optionRow == index
        HStack(spacing: 0) {
            Text(theme.say(option.title))
                .font(theme.chip)
                .foregroundStyle(focused ? theme.text : theme.textSecondary)
                .frame(width: 88, alignment: .leading)
                .padding(.leading, 12)
            control
            Spacer(minLength: 0)
        }
        .frame(height: OptionsSection.height(of: option))
        .background {
            if focused {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.ghostHover)
                    .matchedGeometryEffect(id: "focus", in: focus)
            }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { model.openOptions(at: index) }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -10)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86).delay(0.04 + Double(index) * Motion.stagger)) { shown = true }
        }
    }

    @ViewBuilder private var control: some View {
        let pick = model.picks[index]
        switch option.style {
        case .segments:
            Segments(labels: option.choices.map { theme.say(model.display($0, of: index)) }, icons: option.choices.map(\.icon), picked: pick, theme: theme) {
                model.openOptions(at: index)
                model.pick($0, of: index)
            }
        case .slider:
            EffortSlider(option: option, picked: pick, theme: theme,
                         configured: LaunchOptions.settingsDefault(of: index)) {
                model.openOptions(at: index)
                model.pick($0, of: index)
            }
        case .modes:
            ModePicker(option: option, picked: pick, theme: theme,
                       configured: LaunchOptions.settingsDefault(of: index)) {
                model.openOptions(at: index)
                model.pick($0, of: index)
            }
        }
    }
}

// MARK: controls

/// every value side by side, sharing the width evenly; the picked one raised on a pill that slides.
private struct Segments: View {
    let labels: [String]
    let icons: [String?]
    let picked: Int
    let theme: PaletteTheme
    let pick: (Int) -> Void
    @Namespace private var thumb

    private var segmentWidth: CGFloat { (OptionsSection.controlWidth - 4) / CGFloat(labels.count) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let on = index == picked
                HStack(spacing: 5) {
                    if let icon = icons[index] {
                        Image(systemName: icon).font(.system(size: 10.5, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? theme.text : theme.textSecondary)
                    }
                    ModelName(label: label, on: on, theme: theme)
                        .font(theme.chip)
                        .fontWeight(on ? .medium : .regular)
                }
                .lineLimit(1)
                .frame(width: segmentWidth, height: 24)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.11))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { pick(index) }
            }
        }
        .padding(2)
        .background(theme.controlTrack, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairlineBorder, lineWidth: 0.5))
        .animation(Motion.value, value: picked)
    }
}

/// claude's effort slider. "auto" is not a level (claude picks its own default, medium), so it is a
/// pill of its own before the track rather than its first stop. the track holds the five real levels,
/// "faster" to "smarter": filled in the level's colour up to the ball, which carries a dot of that
/// colour and glows in it, follows the pointer while dragged and settles on the nearest level.
/// on auto the track steps back, the ball turns hollow on the level claude will use and that level
/// reads "medium · default"; touching the track takes over from auto.
private struct EffortSlider: View {
    let option: LaunchOption
    let picked: Int
    let theme: PaletteTheme
    /// the level claude uses when no effort is given
    let configured: String?
    let pick: (Int) -> Void

    @State private var dragX: CGFloat?
    @State private var hovering = false

    private static let pillWidth: CGFloat = 50
    private static let gap: CGFloat = 14
    private let width = OptionsSection.controlWidth - pillWidth - gap
    private let ball: CGFloat = 16
    private let track: CGFloat = 5
    private var inset: CGFloat { ball / 2 }
    /// the real levels, low to max: picks 1...5
    private var stops: Int { option.choices.count - 1 }
    private var isAuto: Bool { picked == 0 }
    /// auto, and not being dragged out of it
    private var resting: Bool { isAuto && dragX == nil }
    private func x(_ stop: Int) -> CGFloat { inset + CGFloat(stop) / CGFloat(stops - 1) * (width - inset * 2) }
    private func nearest(_ x: CGFloat) -> Int {
        min(max(Int(((x - inset) / (width - inset * 2) * CGFloat(stops - 1)).rounded()), 0), stops - 1)
    }
    /// where the ball rests on auto: the level claude will use
    private var autoStop: Int {
        max((configured.flatMap { c in option.choices.firstIndex { $0.label == c } } ?? 2) - 1, 0)
    }
    private var stop: Int { isAuto ? autoStop : picked - 1 }

    var body: some View {
        HStack(alignment: .center, spacing: Self.gap) {
            autoPill
            slider
        }
        .frame(width: OptionsSection.controlWidth, alignment: .leading)
        .animation(Motion.value, value: picked)
    }

    // MARK: auto

    private var autoPill: some View {
        Text(theme.say("Auto"))
            .font(theme.label)
            .fontWeight(isAuto ? .semibold : .regular)
            .foregroundStyle(isAuto ? theme.text : theme.textMuted)
            .frame(width: Self.pillWidth, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isAuto ? Color.white.opacity(0.12) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isAuto ? Color.white.opacity(0.12) : theme.hairlineBorder, lineWidth: 0.5))
                    .shadow(color: .black.opacity(isAuto ? 0.28 : 0), radius: 2, y: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture { pick(0) }
            .help("Let Claude pick its default effort (\(configured ?? "medium"))")
    }

    // MARK: the track

    private var slider: some View {
        let choice = option.choices[stop + 1]
        let ballX = dragX ?? x(stop)
        return VStack(spacing: 5) {
            HStack {
                Text(theme.say("Faster"))
                Spacer()
                Text(theme.say("Smarter"))
            }
            .font(theme.label)
            .foregroundStyle(theme.textMuted)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: track)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                // the colours stay put along the track; the fill only uncovers them
                Group {
                    if resting {
                        Color.white.opacity(0.18)
                    } else {
                        EffortSlider.fill(choice.paint)
                    }
                }
                .frame(width: width, height: track)
                .mask(alignment: .leading) { Capsule().frame(width: max(ballX, track), height: track) }
                ForEach(0..<stops, id: \.self) { s in
                    Capsule()
                        .fill(x(s) <= ballX + 0.5 ? Color.black.opacity(0.22) : Color.white.opacity(0.28))
                        .frame(width: 2, height: 9)
                        .offset(x: x(s) - 1)
                        .opacity(s == 0 || s == stops - 1 || abs(x(s) - ballX) < ball / 2 ? 0 : 1)
                }
                theBall(colour: EffortSlider.color(choice.paint))
                    .offset(x: ballX - inset)
            }
            .frame(width: width, height: 22)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let at = min(max(value.location.x, inset), width - inset)
                dragX = at
                pick(nearest(at) + 1)
            }.onEnded { _ in
                dragX = nil
            })

            ZStack {
                ForEach(0..<stops, id: \.self) { s in
                    label(s)
                        .fixedSize()
                        .frame(width: width, alignment: s == 0 ? .leading : s == stops - 1 ? .trailing : .center)
                        .offset(x: s == 0 || s == stops - 1 ? 0 : x(s) - width / 2)
                        .allowsHitTesting(false)
                }
                // each label takes the clicks of its share of the width
                HStack(spacing: 0) {
                    ForEach(0..<stops, id: \.self) { s in
                        Color.clear.contentShape(Rectangle()).onTapGesture { pick(s + 1) }
                    }
                }
            }
            .frame(width: width, height: 15)
        }
        .frame(width: width)
        // on auto the slider steps back, and comes forward under the pointer
        .opacity(resting ? (hovering ? 0.85 : 0.6) : 1)
        .animation(dragX == nil ? Motion.value : .interactiveSpring(response: 0.1, dampingFraction: 0.9), value: ballX)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.easeOut(duration: 0.2), value: resting)
    }

    /// white with a dot of the level's colour and a glow of it; on auto a hollow ring
    private func theBall(colour: Color) -> some View {
        ZStack {
            Circle().fill(resting ? Color(hex: 0x2A2826) : Color(hex: 0xF5F4EF))
            Circle().strokeBorder(Color.white.opacity(resting ? 0.7 : 0), lineWidth: 1.5)
            Circle().fill(colour).frame(width: 6, height: 6).opacity(resting ? 0 : 1)
        }
        .frame(width: ball, height: ball)
        .shadow(color: resting ? .clear : colour.opacity(0.55), radius: dragX == nil ? 5 : 8)
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        .scaleEffect(dragX != nil ? 1.15 : hovering ? 1.06 : 1)
    }

    @ViewBuilder private func label(_ s: Int) -> some View {
        let c = option.choices[s + 1]
        if s == stop && !resting {
            PaintedText(text: c.label, paint: c.paint, font: theme.label, bold: true)
        } else if s == stop {
            (Text(c.label).foregroundStyle(theme.text) + Text(" · default").foregroundStyle(theme.textMuted))
                .font(theme.label)
        } else {
            Text(c.label).font(theme.label).foregroundStyle(theme.textMuted.opacity(0.7))
        }
    }

    static func color(_ paint: Paint?) -> Color {
        switch paint {
        case .rainbow: Color(CC.rainbow[5])
        case let .shimmer(base, _): Color(base)
        case let .plain(rgb): Color(rgb)
        case nil: .white
        }
    }

    @ViewBuilder static func fill(_ paint: Paint?) -> some View {
        switch paint {
        case .rainbow:
            LinearGradient(colors: CC.rainbow.map(Color.init), startPoint: .leading, endPoint: .trailing)
        case let .shimmer(base, highlight):
            LinearGradient(colors: [Color(base).opacity(0.7), Color(base), Color(highlight)], startPoint: .leading, endPoint: .trailing)
        case let .plain(rgb):
            LinearGradient(colors: [Color(rgb).opacity(0.55), Color(rgb)], startPoint: .leading, endPoint: .trailing)
        case nil:
            Color.white.opacity(0.5)
        }
    }
}

/// the permission modes as claude's code view names them, side by side in one control, each as wide
/// as its name. the picked one sits on a pill tinted in its colour (claude code's colours) that
/// slides from mode to mode. what a mode does shows on hover.
private struct ModePicker: View {
    let option: LaunchOption
    let picked: Int
    let theme: PaletteTheme
    /// the mode ~/.claude/settings.json sets, which "default" falls back to
    let configured: String?
    let pick: (Int) -> Void
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(option.choices.enumerated()), id: \.offset) { i, c in
                segment(c, on: i == picked)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(i) }
                    .help(i == 0 ? "Your settings: \(configured ?? "default")" : c.detail ?? c.label)
            }
        }
        .padding(2)
        .frame(width: OptionsSection.controlWidth)
        .background(theme.controlTrack, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairlineBorder, lineWidth: 0.5))
        .animation(Motion.value, value: picked)
    }

    private func segment(_ c: Choice, on: Bool) -> some View {
        Text(theme.say(c.label))
            .font(theme.chip)
            .fontWeight(on ? .semibold : .regular)
            .foregroundStyle(on ? color(c) : theme.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isPlain(c) ? Color.white.opacity(0.11) : color(c).opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isPlain(c) ? Color.white.opacity(0.08) : color(c).opacity(0.35), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
    }

    private func color(_ c: Choice) -> Color {
        if case let .plain(rgb) = c.paint, rgb != CC.inactive { return Color(rgb) }
        return theme.text
    }

    private func isPlain(_ c: Choice) -> Bool {
        if case let .plain(rgb) = c.paint { return rgb == CC.inactive }
        return true
    }
}

// MARK: painted text

/// text painted as claude code paints it: one colour, a shimmer (a lighter letter running through,
/// its neighbours bold) or the rainbow moving letter by letter, both stepping every 100 ms as the
/// terminal does.
struct PaintedText: View {
    let text: String
    let paint: Paint?
    let font: Font
    var bold = false

    var body: some View {
        switch paint {
        case let .plain(rgb):
            Text(text).font(font).bold(bold).foregroundStyle(Color(rgb))
        case nil:
            Text(text).font(font).bold(bold)
        case let .shimmer(base, highlight):
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let letters = Array(text)
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 10)
                let at = tick % (letters.count + 4)
                letters.enumerated().reduce(Text("")) { line, item in
                    let (i, ch) = item
                    let lit = i == at
                    let near = i == at - 1 || i == at + 1
                    return line + Text(String(ch))
                        .foregroundColor(Color(lit ? highlight : base))
                        .fontWeight(bold || lit || near ? .bold : .regular)
                }
                .font(font)
            }
        case .rainbow:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate * 10)
                Array(text).enumerated().reduce(Text("")) { line, item in
                    let (i, ch) = item
                    return line + Text(String(ch)).foregroundColor(Color(CC.rainbow[(i + tick) % CC.rainbow.count]))
                }
                .font(font)
                .bold()
            }
        }
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255) }
}
