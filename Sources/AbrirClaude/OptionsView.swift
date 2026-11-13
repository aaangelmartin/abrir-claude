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
    static let modesHeight: CGFloat = 62
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
                        Text(theme.say("Modelo")).foregroundStyle(theme.textMuted)
                    } else {
                        ModelName(label: model.display(model.choice(of: LaunchOptions.model), of: LaunchOptions.model), on: true, theme: theme)
                    }
                }
            }
            dot
            item(LaunchOptions.effort) {
                HStack(spacing: 5) {
                    Text(theme.say("Esfuerzo")).foregroundStyle(theme.textMuted)
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
                    PaintedText(text: theme.say(isDefault ? "Permisos" : choice.label), paint: isDefault ? .plain(CC.inactive) : choice.paint, font: theme.chip, bold: !isDefault)
                }
            }
            dot
            item(LaunchOptions.session) {
                let choice = model.choice(of: LaunchOptions.session)
                HStack(spacing: 5) {
                    if let icon = choice.icon { Image(systemName: icon).font(.system(size: 10.5)) }
                    Text(theme.say(model.picks[LaunchOptions.session] == 0 ? "Nueva sesión" : choice.label))
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

/// claude's effort slider: "más rápido" and "más listo" at the ends, a track filled in the level's
/// colour up to the thumb, a notch per level and the levels under them, the picked one bold in its
/// colour (xhigh shimmers, max runs through the rainbow). the thumb glows in the level's colour,
/// follows the pointer while dragged and settles on the nearest level when let go. on auto, a ring
/// marks the level claude's settings will use.
private struct EffortSlider: View {
    let option: LaunchOption
    let picked: Int
    let theme: PaletteTheme
    /// the level ~/.claude/settings.json sets, which auto falls back to
    let configured: String?
    let pick: (Int) -> Void

    @State private var dragX: CGFloat?
    @State private var hovering = false

    private let width = OptionsSection.controlWidth
    private let thumb: CGFloat = 16
    private let track: CGFloat = 5
    private var inset: CGFloat { thumb / 2 }
    private var stops: Int { option.choices.count }
    private func x(_ i: Int) -> CGFloat { inset + CGFloat(i) / CGFloat(stops - 1) * (width - inset * 2) }
    private func nearest(_ x: CGFloat) -> Int {
        min(max(Int(((x - inset) / (width - inset * 2) * CGFloat(stops - 1)).rounded()), 0), stops - 1)
    }
    private var configuredStop: Int? {
        guard picked == 0, let configured else { return nil }
        return option.choices.firstIndex { $0.label == configured }
    }

    var body: some View {
        let choice = option.choices[picked]
        let thumbX = dragX ?? x(picked)
        let glow = Self.color(choice.paint)
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(theme.say("Más rápido"))
                Spacer()
                if picked == stops - 1 {
                    Text(theme.say("Uso alto"))
                        .font(theme.label)
                        .foregroundStyle(Color(CC.warning))
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(Color(CC.warning).opacity(0.12), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
                Text(theme.say("Más listo"))
            }
            .font(theme.label)
            .foregroundStyle(theme.textMuted)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: track)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
                // the colours stay put along the track; the fill only uncovers them
                Self.fill(choice.paint)
                    .frame(width: width, height: track)
                    .mask(alignment: .leading) { Capsule().frame(width: max(thumbX, track), height: track) }
                    .opacity(picked == 0 && dragX == nil ? 0 : 1)
                ForEach(0..<stops, id: \.self) { i in
                    Capsule()
                        .fill(x(i) <= thumbX + 0.5 ? Color.black.opacity(0.22) : Color.white.opacity(0.28))
                        .frame(width: 2, height: 9)
                        .offset(x: x(i) - 1)
                        .opacity(i == 0 || i == stops - 1 || i == configuredStop ? 0 : 1)
                }
                if let stop = configuredStop {
                    Circle()
                        .strokeBorder(Self.color(option.choices[stop].paint).opacity(0.8), lineWidth: 1.5)
                        .frame(width: 11, height: 11)
                        .offset(x: x(stop) - 5.5)
                        .transition(.opacity)
                }
                Circle()
                    .fill(Color(hex: 0xF5F4EF))
                    .frame(width: thumb, height: thumb)
                    .overlay(Circle().fill(glow).frame(width: 6, height: 6).opacity(picked == 0 ? 0 : 1))
                    .shadow(color: glow.opacity(picked == 0 ? 0 : 0.55), radius: dragX == nil ? 5 : 8)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .scaleEffect(dragX != nil ? 1.15 : hovering ? 1.06 : 1)
                    .offset(x: thumbX - inset)
            }
            .frame(width: width, height: 22)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let at = min(max(value.location.x, inset), width - inset)
                dragX = at
                pick(nearest(at))
            }.onEnded { _ in
                dragX = nil
            })

            ZStack {
                ForEach(Array(option.choices.enumerated()), id: \.offset) { i, c in
                    label(c, at: i)
                        .fixedSize()
                        .frame(width: width, alignment: i == 0 ? .leading : i == stops - 1 ? .trailing : .center)
                        .offset(x: i == 0 || i == stops - 1 ? 0 : x(i) - width / 2)
                        .allowsHitTesting(false)
                }
                // each label takes the clicks of its share of the width
                HStack(spacing: 0) {
                    ForEach(0..<stops, id: \.self) { i in
                        Color.clear.contentShape(Rectangle()).onTapGesture { pick(i) }
                    }
                }
            }
            .frame(width: width, height: 15)
        }
        .frame(width: width)
        .animation(dragX == nil ? Motion.value : .interactiveSpring(response: 0.1, dampingFraction: 0.9), value: thumbX)
        .animation(Motion.value, value: picked)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder private func label(_ c: Choice, at i: Int) -> some View {
        if i == picked {
            HStack(spacing: 4) {
                PaintedText(text: c.label, paint: c.paint, font: theme.label, bold: true)
                    .foregroundStyle(theme.text)
                if i == 0, let configured {
                    Text("· " + configured).font(theme.label).foregroundStyle(theme.textMuted)
                }
            }
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

/// the permission modes, every one in sight: a row of short names on a track, the picked one on a pill
/// tinted in its colour with claude code's symbol, and under the row what that mode does. the pill
/// slides from mode to mode, the line under it changes with it.
private struct ModePicker: View {
    let option: LaunchOption
    let picked: Int
    let theme: PaletteTheme
    /// the mode ~/.claude/settings.json sets, which "por defecto" falls back to
    let configured: String?
    let pick: (Int) -> Void
    @Namespace private var thumb

    var body: some View {
        let choice = option.choices[picked]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(option.choices.enumerated()), id: \.offset) { i, c in
                    segment(c, on: i == picked)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { pick(i) }
                }
            }
            .padding(2)
            .frame(width: OptionsSection.controlWidth)
            .background(theme.controlTrack, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairlineBorder, lineWidth: 0.5))

            HStack(spacing: 6) {
                if let symbol = choice.symbol {
                    PaintedText(text: symbol, paint: choice.paint, font: .system(size: 10))
                }
                Text(theme.say(line(choice)))
                    .font(theme.label)
                    .foregroundStyle(risky(choice) ? color(choice).opacity(0.85) : theme.textMuted)
            }
            .padding(.leading, 4)
            .id(picked)
            .transition(.opacity)
        }
        .animation(Motion.value, value: picked)
    }

    private func segment(_ c: Choice, on: Bool) -> some View {
        HStack(spacing: 4) {
            Text(theme.say(c.short ?? c.label))
                .font(theme.chip)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(on ? color(c) : theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
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

    /// the full name and what it does: "Aceptar ediciones: edita archivos sin preguntar"
    private func line(_ c: Choice) -> String {
        if c.args.isEmpty, let configured { return "Usa tu configuración: " + configured }
        guard let detail = c.detail else { return c.label }
        return c.short == nil || c.short == c.label ? detail : c.label + ". " + detail
    }

    private func color(_ c: Choice) -> Color {
        if case let .plain(rgb) = c.paint, rgb != CC.inactive { return Color(rgb) }
        return theme.text
    }

    private func isPlain(_ c: Choice) -> Bool {
        if case let .plain(rgb) = c.paint { return rgb == CC.inactive }
        return true
    }

    private func risky(_ c: Choice) -> Bool {
        if case let .plain(rgb) = c.paint { return rgb == CC.error }
        return false
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
