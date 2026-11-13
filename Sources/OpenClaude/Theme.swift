import AppKit
import CoreText
import LaaabsKit
import SwiftUI

/// how the window looks. claude's quick entry by default; the laaabs. look stays to compare:
///
///     defaults write com.aaangelmartin.open-claude theme laaabs   # or claude
///
/// then reopen the app (⌘Q in the window, open it again).
@MainActor
struct AppTheme {
    /// the bar's ground, top to bottom
    let gradientTop: Color
    let gradientBottom: Color
    /// the 0.5 pt ring around the bar
    let ring: Color
    let mark: Color
    let caret: Color

    let text: Color
    let textRow: Color
    let placeholder: Color
    let textMuted: Color
    let icon: Color
    let divider: Color
    let rowSelected: Color
    let button: Color
    let buttonText: Color
    /// claude's design system (cds): the brand button, ghost buttons, controls, popovers
    let brandFill: Color
    let brandFillHover: Color
    let textSecondary: Color
    let ghostHover: Color
    let ghostSelected: Color
    let controlTrack: Color
    let controlThumb: Color
    let hairlineBorder: Color
    let popover: Color
    let warning: Color

    let input: Font
    let row: Font
    let label: Font
    let chip: Font
    let buttonFont: Font

    /// laaabs. writes every interface word in lowercase; claude writes them in sentence case
    let lowercase: Bool

    func say(_ s: String) -> String { lowercase ? s.lowercased() : s }

    static let current: AppTheme = {
        switch UserDefaults.standard.string(forKey: "theme") {
        case "laaabs": return .laaabs()
        default: return .claude()
        }
    }()

    /// claude desktop's quick entry (⌥space), from its own stylesheet: the dark gradient
    /// #403f3e at 95 % to #292523, a 0.5 px white ring at 20 %, the starburst in #d97757, anthropic
    /// sans 16 in white with a #a6a39b placeholder. rows follow claude's dark tokens (text-200
    /// #c2c0b6, text-500 #9c9a92). the fonts are read from the installed claude app, never copied.
    static func claude() -> AppTheme {
        let hasFonts = ClaudeFonts.register()
        BrandFonts.register() // outfit, for the signature
        let sans: (CGFloat, Font.Weight) -> Font = { size, weight in
            hasFonts ? .custom("Anthropic Sans", size: size).weight(weight) : .system(size: size, weight: weight)
        }
        return AppTheme(
            gradientTop: Color(hex: 0x403F3E).opacity(0.95),
            gradientBottom: Color(hex: 0x292523),
            ring: .white.opacity(0.20),
            mark: Color(hex: 0xD97757),
            caret: .white,
            text: .white,
            textRow: Color(hex: 0xC2C0B6),
            placeholder: Color(hex: 0xA6A39B),
            textMuted: Color(hex: 0x9C9A92),
            icon: Color(hex: 0x9C9A92),
            divider: .white.opacity(0.10),
            rowSelected: .white.opacity(0.09),
            button: Color(hex: 0xD97757),
            buttonText: .white,
            // values from claude desktop's cds stylesheet, dark mode
            brandFill: Color(hex: 0xC6613F),        // --cds-clay-emphasized (fill-brand)
            brandFillHover: Color(hex: 0xD97757),   // --cds-clay
            textSecondary: Color(hex: 0xA5A49A),    // --cds-gray-300 (text-secondary)
            ghostHover: .white.opacity(0.075),      // --cds-fill-ghost-hover
            ghostSelected: .white.opacity(0.15),    // --cds-fill-ghost-selected
            controlTrack: .white.opacity(0.05),     // --cds-alpha-1
            controlThumb: Color(hex: 0x20201F),     // --cds-surface-3 (popover)
            hairlineBorder: .white.opacity(0.10),   // --cds-border
            popover: Color(hex: 0x20201F),
            warning: Color(hex: 0xD97757),
            input: sans(16, .regular),
            row: sans(14, .regular),
            label: sans(12, .regular),
            chip: sans(13, .regular),
            buttonFont: sans(13, .medium),
            lowercase: false
        )
    }

    /// the laaabs. look on the same bar: black, outfit, cyan only as the caret.
    static func laaabs() -> AppTheme {
        BrandFonts.register()
        return AppTheme(
            gradientTop: BrandColors.surfaceElevated.opacity(0.97),
            gradientBottom: BrandColors.surface,
            ring: BrandColors.hairline,
            mark: .white,
            caret: BrandColors.accent,
            text: BrandColors.on,
            textRow: BrandColors.onBody,
            placeholder: BrandColors.onTertiary,
            textMuted: BrandColors.onTertiary,
            icon: BrandColors.onTertiary,
            divider: BrandColors.separator,
            rowSelected: BrandColors.surfaceSelected,
            button: BrandColors.accentTint,
            buttonText: BrandColors.accent,
            brandFill: BrandColors.accentTint,
            brandFillHover: BrandColors.accentStrong,
            textSecondary: BrandColors.onSecondary,
            ghostHover: BrandColors.surfaceHover,
            ghostSelected: BrandColors.surfaceSelected,
            controlTrack: BrandColors.surfaceTrack,
            controlThumb: BrandColors.surfaceHigh,
            hairlineBorder: BrandColors.hairline,
            popover: BrandColors.surfaceElevated,
            warning: BrandColors.accent,
            input: .outfit(16, weight: .medium),
            row: .outfit(14, weight: .medium),
            label: .brandCaption,
            chip: .outfit(12.5, weight: .medium),
            buttonFont: .brandButton,
            lowercase: true
        )
    }
}

/// anthropic sans, registered for this process from the installed claude app.
enum ClaudeFonts {
    private static let folder = "/Applications/Claude.app/Contents/Resources/fonts"
    private static let files = ["AnthropicSans-Romans-Variable-25x258.ttf", "AnthropicSerif-Romans-Variable-25x258.ttf"]

    /// anthropic sans at any size, as claude sets its interface; the system font without it
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        NSFont(name: "Anthropic Sans", size: size) != nil || register()
            ? .custom("Anthropic Sans", size: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    /// anthropic serif's display cut, as claude sets its large headings; the system serif without it
    static func display(_ size: CGFloat) -> Font {
        let name = "AnthropicSerifVariable-DisplayRegular"
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, design: .serif)
    }

    static func register() -> Bool {
        var ok = true
        for file in files {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { ok = false; continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
               let error = error?.takeRetainedValue(),
               CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue {
                ok = false
            }
        }
        return ok
    }
}
