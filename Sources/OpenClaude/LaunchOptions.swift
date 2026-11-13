import Foundation

/// a colour from claude code's dark theme, as rgb 0...255
struct RGB: Equatable, Sendable {
    let r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
}

/// how a value's name is painted, as claude code paints it
enum Paint: Equatable, Sendable {
    case plain(RGB)
    /// the colour with a lighter letter running through it (claude code's xhigh)
    case shimmer(RGB, highlight: RGB)
    /// each letter a colour of the rainbow, moving (claude code's max)
    case rainbow
}

/// claude code's dark theme colours (read from the claude binary's theme table)
enum CC {
    static let inactive = RGB(153, 153, 153)
    static let warning = RGB(255, 193, 7)
    static let success = RGB(78, 186, 101)
    static let permission = RGB(177, 185, 249)
    static let autoAccept = RGB(175, 135, 255)
    static let autoAcceptShimmer = RGB(208, 180, 255)
    static let planMode = RGB(72, 150, 140)
    static let error = RGB(255, 107, 128)
    static let rainbow = [
        RGB(235, 95, 87), RGB(245, 139, 87), RGB(250, 195, 95), RGB(145, 200, 130),
        RGB(130, 170, 220), RGB(155, 130, 200), RGB(200, 130, 180),
    ]
}

/// one value of a launch option and the flags it adds to `claude`.
struct Choice: Equatable, Sendable {
    let label: String
    let args: [String]
    /// an sf symbol (session) or a text symbol such as claude code's ⏸ ⏵⏵ (permissions)
    var icon: String?
    var symbol: String?
    var paint: Paint?
    /// one short line beside the value when its row is open
    var detail: String?
}

/// how an option is drawn when the options are open.
enum OptionStyle: Sendable {
    /// every value side by side, the picked one raised
    case segments
    /// claude code's /effort slider: faster on the left, smarter on the right
    case slider
    /// every mode side by side, each sized to its name, the picked one tinted in its colour
    case modes
}

struct LaunchOption: Identifiable, Sendable {
    let id: String
    let title: String
    let style: OptionStyle
    /// the first value adds no flag. when true it is not offered as a value of its own: the value it
    /// amounts to (the model's default effort, the settings' mode) is marked "default" instead
    var defaultIsMarked = true
    let choices: [Choice]
}

enum LaunchOptions {
    static let model = 0, effort = 1, permissions = 2, session = 3

    /// every value maps to a flag `claude --help` lists; the first value of each adds nothing, so
    /// claude's own default (or settings.json) applies
    static let all: [LaunchOption] = [
        LaunchOption(id: "model", title: "Model", style: .segments, choices: [
            Choice(label: "Default", args: []),
            // the aliases always run the newest model; its number is read from claude (ModelVersions)
            Choice(label: "Fable", args: ["--model", "fable"]),
            Choice(label: "Opus", args: ["--model", "opus"]),
            Choice(label: "Sonnet", args: ["--model", "sonnet"]),
            Choice(label: "Haiku", args: ["--model", "haiku"]),
        ]),
        // the levels and colours of claude code's /effort slider. auto adds no flag: claude picks
        // its own default, medium
        LaunchOption(id: "effort", title: "Effort", style: .slider, choices: [
            Choice(label: "default", args: [], paint: .plain(CC.inactive)),
            Choice(label: "low", args: ["--effort", "low"], paint: .plain(CC.warning)),
            Choice(label: "medium", args: ["--effort", "medium"], paint: .plain(CC.success)),
            Choice(label: "high", args: ["--effort", "high"], paint: .plain(CC.permission)),
            Choice(label: "xhigh", args: ["--effort", "xhigh"], paint: .shimmer(CC.autoAccept, highlight: CC.autoAcceptShimmer)),
            Choice(label: "max", args: ["--effort", "max"], paint: .rainbow),
        ]),
        // the modes claude's code view offers, in its order and with its names, painted in claude
        // code's colours. default adds no flag, so the settings decide.
        LaunchOption(id: "permissionMode", title: "Permissions", style: .modes, choices: [
            Choice(label: "Default", args: [], symbol: "⏸", paint: .plain(CC.inactive), detail: "Whatever your settings say"),
            Choice(label: "Manual", args: ["--permission-mode", "manual"], symbol: "⏸", paint: .plain(CC.inactive), detail: "Asks before every action"),
            Choice(label: "Accept edits", args: ["--permission-mode", "acceptEdits"], symbol: "⏵⏵", paint: .plain(CC.autoAccept), detail: "Edits files without asking"),
            Choice(label: "Plan", args: ["--permission-mode", "plan"], symbol: "⏸", paint: .plain(CC.planMode), detail: "Only reads and proposes a plan"),
            Choice(label: "Auto", args: ["--permission-mode", "auto"], symbol: "⏵⏵", paint: .plain(CC.warning), detail: "Decides on its own what is safe"),
            Choice(label: "Bypass", args: ["--permission-mode", "bypassPermissions"], symbol: "⏵⏵", paint: .plain(CC.error), detail: "Bypasses every permission check"),
        ]),
        LaunchOption(id: "session", title: "Session", style: .segments, defaultIsMarked: false, choices: [
            Choice(label: "New", args: [], icon: "plus"),
            Choice(label: "Continue", args: ["--continue"], icon: "arrow.uturn.forward"),
            Choice(label: "Resume", args: ["--resume"], icon: "clock.arrow.circlepath"),
        ]),
    ]

    /// the flags for the picked value of each option, in the options' order
    static func args(for picks: [Int]) -> [String] {
        zip(all, picks).flatMap { option, pick in option.choices.indices.contains(pick) ? option.choices[pick].args : [] }
    }

    /// what claude itself starts with when a value adds no flag: the user's ~/.claude/settings.json
    private static let settings: (model: String?, mode: String?) = {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        let mode = (json["permissions"] as? [String: Any])?["defaultMode"] as? String
        return (json["model"] as? String, mode)
    }()

    /// the label of the value claude's settings already choose for an option, if any
    static func settingsDefault(of option: Int) -> String? {
        switch option {
        case model:
            guard let m = settings.model else { return nil }
            return all[model].choices.first { $0.args.last == m }?.label ?? m
        case effort:
            // each model has its own (ModelVersions reads it); the settings' effortLevel is a legacy
            // value claude no longer starts sessions with
            return nil
        case permissions:
            guard let mode = settings.mode else { return nil }
            return all[permissions].choices.first { $0.args.last == mode }?.label
        default:
            return nil
        }
    }
}
