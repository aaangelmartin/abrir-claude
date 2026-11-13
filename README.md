# open claude

A global shortcut (⌥C) opens a palette that asks which folder to open Claude Code in. Confirm, and it opens a new Terminal window, `cd`s into that folder and runs `claude`.

## Usage

| You type | It opens in |
|---|---|
| nothing | your home folder |
| `projects/my-app` | `~/projects/my-app` |
| `~/projects/my-app` | same as above |
| `/Volumes/disk/work` | that absolute path |
| a folder that does not exist | Terminal shows the `cd` error and claude does not start |

### Projects

With nothing typed, the palette lists the folders used last, here or in Claude Code itself (from its sessions in `~/.claude/projects`). Type a name rather than a path and it searches fuzzily, like a command palette: the letters in order, anywhere, so `ocl` finds `Developer/open-claude`. It searches your home folder's own folders, every folder Claude has run in, the folders opened from here and the git repos under `~/Developer`, best match first and recently used ones a little ahead. Type a `/` and it goes back to completing the path, folder by folder.

Each known project shows, on the right, its git branch, how long ago it was used and how many Claude sessions it has.

### Sessions

**→** on a highlighted project (with the caret at the end of the text), or a click on its session count, lists its Claude sessions in place of the folders: a new session first, then each one newest first, by its title (or its first message) and how long ago it ran. **↵** opens the highlighted one, a past one with `claude --resume <id>`. **←** or **esc** go back to the folders. Only the start and end of each session file are read, so even very long sessions list at once.

Keys:
- **⌥C** opens the palette. With the palette open, pressing it again acts as Enter: **⌥C ⌥C** opens Claude straight in your home folder.
- **↵** opens what is typed, or the highlighted row once you have moved with the arrows.
- **tab** completes with the highlighted row or the first suggestion, and lists that folder's subfolders.
- **→** at the end of the text opens the highlighted project's sessions.
- **↑ ↓** move through the suggestions. The list only scrolls when it has to, and keeps the next row peeking. Past the last one you reach the options.
- **⌘A ⌘C ⌘V ⌘X ⌘Z** work in the field, through a hidden Edit menu.
- **esc**, **⌘W** or a click outside close the palette.
- **⌘Q** with the palette open quits the app. It starts again at login or from Applications.

### Model, effort, permissions and session

On the right of the summary line sits the plan's use, as `/usage` gives it: the five-hour session and the week (yellow from 80 %, red from 95 %; hover for when each resets). It is read with the sign-in Claude Code keeps in the keychain, so the first time macOS asks to let Open Claude read "Claude Code-credentials". The sign-in is never refreshed by this app; when it has expired, nothing shows until Claude Code refreshes it.

At the bottom, one line says how Claude will be launched: **Model, Effort, Permissions, Session**, each value painted the way Claude Code paints it. **↓** past the last folder (or **⌘↓**, or a click) opens it into one row per option:

| Row | Control | `claude` flag |
|---|---|---|
| Model | full-width segmented control: Fable, Opus, Sonnet, Haiku, each with its number (Opus 5.5), read from the installed `claude` so it updates on its own. The model Claude starts with (your settings' model, or Opus) is marked *default* | `--model` with the alias (`opus`), which always runs the newest |
| Effort | a track with the five levels, Faster to Smarter: low, medium, high, xhigh, max. The level the chosen model starts with is marked *default* (medium for Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.2), read from the model table inside `claude`; the ball sits there until you pick another. The ball carries a dot of the level's colour and glows in it; dragged, it follows the pointer and settles on the nearest level | `--effort` |
| Permissions | the modes Claude's Code view offers, in its order: Manual, Accept edits, Plan, Auto, Bypass. The mode your settings choose is marked *default*. The picked one is tinted in its colour; hover a mode to see what it does | `--permission-mode` |
| Session | segmented control: New, Continue, Resume | `--continue`, `--resume` |

The colours come from the dark theme table inside `claude` itself:

| Value | Colour |
|---|---|
| effort low | `warning`, yellow |
| effort medium | `success`, green |
| effort high | `permission`, lavender |
| effort xhigh | `autoAccept`, purple, with a moving shimmer |
| effort max | moving rainbow |
| Manual | grey, `⏸` |
| Plan | `planMode`, teal, `⏸` |
| Accept edits | `autoAccept`, purple, `⏵⏵` |
| Auto | `warning`, yellow, `⏵⏵` |
| Bypass | `error`, pink red, `⏵⏵` |

Keys in the options:
- **↑ ↓** move between rows, and **↑** from the first goes back to the folders.
- **← →** change the value.
- **esc** folds the options; a second **esc** closes the palette.
- **↵** or **⌥C** launch Claude.

There is no separate "default" value, and every time the palette opens the options start again from the defaults: the value Claude would start with anyway is marked *default*, and picking it adds no flag, so it keeps following Claude and your settings. The `effortLevel` in `settings.json` is a legacy value Claude Code no longer starts sessions with, so it is not used. Every time the palette opens, the options start again from the defaults.

The window has a fixed, transparent size and the card grows and shrinks inside it, animated, with its shadow drawn in SwiftUI. That is why opening and folding the options is smooth: the rows come in one after another.

The shortcut is set in `App.swift` (`openClaudeShortcut`) and applied again on every launch. While the app runs, ⌥C no longer types "©".

Opening the app from Spotlight or Finder also shows the palette. The list shows every subfolder, with a thin scroll thumb of its own that appears while scrolling, and edges that fade when there is more above or below. The part of the path already typed is dimmed.

## Look

By default it copies **Claude's quick entry** (⌥Space in the desktop app). The values come from its own stylesheet (`quick-window.html` inside `app.asar`):
- a transparent, shadowed panel 606 px wide, centred on the main display
- draggable, and it remembers where you left it
- a 56 px bar with a 16 radius
- a gradient from `#403F3E` (at 95 %) to `#292523`, with a 0.5 px white ring at 20 %
- the starburst in `#D97757` at 18 px, in a 56×56 cell
- Anthropic Sans 16 px in white, placeholder `#A6A39B`, white caret
- no field border, no focus ring, no fade when it appears

Folders use Claude's dark tokens: text `#C2C0B6`, icons `#9C9A92`, and white at 9 % for the highlighted row.

Anthropic Sans is loaded at launch from `/Applications/Claude.app`; it is not copied into this project. Without the Claude app the system font is used.

The **laaabs.** style uses the same bar in black, with Outfit and a cyan caret. To switch:

```sh
defaults write com.aaangelmartin.open-claude theme laaabs   # or claude
pkill -x OpenClaude; open ~/Applications/"Open Claude.app"
```

## Install

Requirements:
- macOS 14 or later and Xcode (Swift 6.2 or later)
- the laaabs. kit at `~/Desktop/laaabs/marca/ui-swift`. If it lives elsewhere, change the `path:` in `Package.swift`
- `claude` on a login shell's PATH (`zsh -lic 'command -v claude'`)

```sh
cd ~/Developer/open-claude
./scripts/install.sh
```

The script:
1. Builds for arm64 and x86_64.
2. Assembles `build/Open Claude.app` and makes the icon from `Resources/claude.svg` (white mark on Claude's orange).
3. Signs with the first valid "Developer ID Application" certificate in the keychain. `SIGN_IDENTITY=-` signs ad hoc.
4. Installs it in `~/Applications` and opens it.

On first launch it adds itself to the login items and shows the palette once.

## macOS permissions

- **Control Terminal** (Automation): asked the first time you open a folder. If you deny it, the palette says so and offers a button to System Settings → Privacy & Security → Automation.
- **Login item**: macOS posts a notification that it was added. Manage it in System Settings → General → Login Items.

The global shortcut needs no Accessibility permission, since it uses `KeyboardShortcuts` (Carbon hotkeys).

## Layout

```
Sources/OpenClaude/
  App.swift            launch, global shortcut, login item
  PalettePanel.swift   floating panel that never activates the app, keys, position
  PaletteView.swift    the palette in SwiftUI
  Theme.swift          the two styles (claude and laaabs.) and loading Claude's fonts
  PaletteModel.swift   text, rows, selection, notices, options
  FolderPath.swift     from what is typed to an absolute path and a shell command
  Suggestions.swift    folder completion and recents
  Projects.swift       known projects, claude's sessions, git branches and fuzzy matching
  Usage.swift          the plan's session and weekly use
  Terminal.swift       the AppleScript that opens the Terminal window
  LaunchOptions.swift  model, effort, permissions and session, and the claude flags they add
  ModelVersions.swift  the newest model numbers, read from the installed claude
  OptionsView.swift    the summary line, the rows, the effort slider and the painted text
Resources/             Info.plist, entitlements, claude svg
scripts/               install.sh, make-icon.swift
Tests/                 paths, suggestions, selection, options and model versions (swift test)
                       SNAPSHOT_DIR=/path swift test --filter Snapshot renders the palette to png off screen
```

## Uninstall

```sh
pkill -x OpenClaude
rm -rf ~/Applications/"Open Claude.app"
```

Then remove it from System Settings → General → Login Items if it is still listed.
