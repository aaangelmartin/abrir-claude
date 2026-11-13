import AppKit
import KeyboardShortcuts
import SwiftUI

/// the first-run window, in the palette's own look: what the app does, a check of what it needs,
/// the shortcut, and off you go. ⌘, in the palette opens it again.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// called when it is done (or closed): the palette opens
    var onFinish: () -> Void = {}

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = OnboardingView(finish: { [weak self] in self?.finish() })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = KeyWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        window?.orderOut(nil)
        window = nil
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        onFinish()
    }

    func windowWillClose(_ notification: Notification) { window = nil }

    static let doneKey = "didOnboard"
    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }
}

/// borderless windows do not take the keys unless they say so
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, checks, shortcut, done }

    var finish: () -> Void = {}
    @State var step: Step = .welcome
    private let theme = PaletteTheme.current

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: WelcomeStep(theme: theme)
                case .checks: ChecksStep(theme: theme)
                case .shortcut: ShortcutStep(theme: theme)
                case .done: DoneStep(theme: theme)
                }
            }
            .id(step)
            .transition(.opacity.combined(with: .offset(x: 10)))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 330, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 30)

            Rectangle().fill(theme.divider).frame(height: 0.5)
            footer
        }
        .frame(width: 560)
        .background(LinearGradient(colors: [theme.gradientTop, theme.gradientBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: PaletteView.radius))
        .overlay(RoundedRectangle(cornerRadius: PaletteView.radius).strokeBorder(theme.ring, lineWidth: 0.5))
        .animation(.easeOut(duration: 0.18), value: step)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Color.white.opacity(0.85) : Color.white.opacity(0.18))
                        .frame(width: s == step ? 16 : 6, height: 6)
                }
            }
            Spacer()
            if step != .welcome {
                Button(theme.say("Back")) { move(-1) }
                    .buttonStyle(QuietButtonStyle(theme: theme))
                    .keyboardShortcut(.cancelAction)
            }
            Button(theme.say(step == .done ? "Open the palette" : "Continue")) {
                if step == .done { finish() } else { move(1) }
            }
            .buttonStyle(BrandButtonStyle(theme: theme))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    private func move(_ by: Int) {
        if let next = Step(rawValue: step.rawValue + by) { step = next }
    }
}

// MARK: steps

private struct StepTitle: View {
    let title: String
    let line: String
    let theme: PaletteTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(theme.say(title)).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.text)
            Text(theme.say(line)).font(theme.row).foregroundStyle(theme.textSecondary)
        }
    }
}

private struct WelcomeStep: View {
    let theme: PaletteTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                ClaudeMark(color: theme.mark).frame(width: 34, height: 34)
                StepTitle(title: "Open Claude", line: "Your Claude Code sessions, one shortcut away.", theme: theme)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("circle.dashed", "Running sessions", "Every session at a glance, and what it needs from you. ↵ takes you to its window.")
                feature("folder", "Any folder", "Type a folder to start a new session there, or to resume one of its past ones.")
                feature("slider.horizontal.3", "Your way", "Model, effort and permissions, right before a session starts.")
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 34)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(theme.say(title)).font(theme.row).foregroundStyle(theme.text)
                Text(theme.say(line)).font(theme.label).foregroundStyle(theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ChecksStep: View {
    let theme: PaletteTheme
    @State private var claude = Setup.claudeCode()
    @State private var terminal = Setup.terminal()
    @State private var signIn = Setup.signIn()
    @State private var claudeApp = Setup.claudeApp()
    @State private var atLogin = Setup.startsAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                StepTitle(title: "Check your setup", line: "What Open Claude needs, and what it is better with.", theme: theme)
                Spacer()
                Button(theme.say("Check again")) { refresh() }
                    .buttonStyle(QuietButtonStyle(theme: theme))
            }
            VStack(spacing: 2) {
                row("Claude Code", claude) {
                    if case .missing = claude {
                        Link(theme.say("Get it"), destination: URL(string: "https://claude.com/claude-code")!)
                            .font(theme.label)
                    }
                }
                row("Control Terminal", terminal) {
                    if case .ok = terminal {} else {
                        Button(theme.say("Allow")) { terminal = Setup.askForTerminal() }
                            .buttonStyle(QuietButtonStyle(theme: theme))
                    }
                }
                row("Claude Code sign-in", signIn) { EmptyView() }
                row("Claude app", claudeApp) { EmptyView() }
                row("Start at login", atLogin ? .ok("Ready whenever you log in") : .optional("Open it yourself after logging in")) {
                    Toggle("", isOn: Binding(get: { atLogin }, set: { Setup.setStartsAtLogin($0); atLogin = Setup.startsAtLogin }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
        }
    }

    private func refresh() {
        claude = Setup.claudeCode()
        terminal = Setup.terminal()
        signIn = Setup.signIn()
        claudeApp = Setup.claudeApp()
        atLogin = Setup.startsAtLogin
    }

    private func row<Action: View>(_ name: String, _ state: Setup.State, @ViewBuilder action: () -> Action) -> some View {
        let (icon, colour, line): (String, Color, String) = switch state {
        case let .ok(l): ("checkmark.circle.fill", Color(CC.success), l)
        case let .missing(l): ("exclamationmark.circle.fill", Color(CC.warning), l)
        case let .optional(l): ("minus.circle", theme.textMuted, l)
        case let .later(l): ("clock", theme.textMuted, l)
        }
        return HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(colour).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.say(name)).font(theme.row).foregroundStyle(theme.text)
                Text(theme.say(line)).font(theme.label).foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShortcutStep: View {
    let theme: PaletteTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            StepTitle(title: "Your shortcut", line: "Press it anywhere to open the palette. Press it again to start a session at once.", theme: theme)
            HStack {
                Spacer()
                KeyboardShortcuts.Recorder(for: .openClaude)
                    .controlSize(.large)
                Spacer()
            }
            .padding(.vertical, 26)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            Text(theme.say("Click the field and press the keys you want. ⌥C works well with one hand."))
                .font(theme.label)
                .foregroundStyle(theme.textMuted)
        }
    }
}

private struct DoneStep: View {
    let theme: PaletteTheme

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            ClaudeMark(color: theme.mark).frame(width: 38, height: 38)
            Text(theme.say("You're set")).font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.text)
            HStack(spacing: 6) {
                ForEach(Array(shortcutKeys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.text)
                        .frame(minWidth: 40, minHeight: 40)
                        .padding(.horizontal, 6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                }
            }
            Text(theme.say("Press it anywhere. ⌘, in the palette brings this back."))
                .font(theme.row)
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
    }

    /// the shortcut, a cap per key: "⌥", "C"
    private var shortcutKeys: [String] {
        let text = KeyboardShortcuts.getShortcut(for: .openClaude)?.description ?? "⌥C"
        return text.map(String.init)
    }
}

// MARK: buttons

private struct BrandButtonStyle: ButtonStyle {
    let theme: PaletteTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonFont)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(configuration.isPressed ? theme.brandFillHover : theme.brandFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    let theme: PaletteTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(theme.buttonFont)
            .foregroundStyle(theme.textRow)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
