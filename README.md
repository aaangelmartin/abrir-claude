# abrir claude

A global shortcut (⌥C) opens a palette that asks which folder to open Claude Code in. Confirm, and it opens a new Terminal window, `cd`s into that folder and runs `claude`.

## Usage

| You type | It opens in |
|---|---|
| nothing | your home folder |
| `projects/my-app` | `~/projects/my-app` |
| `~/projects/my-app` | same as above |
| `/Volumes/disk/work` | that absolute path |
| a folder that does not exist | Terminal shows the `cd` error and claude does not start |

Keys:
- **⌥C** opens the palette. With the palette open, pressing it again acts as Enter: **⌥C ⌥C** opens Claude straight in your home folder.
- **↵** opens what is typed, or the highlighted row once you have moved with the arrows.
- **tab** completes with the highlighted row or the first suggestion, and lists that folder's subfolders.
- **↑ ↓** move through the suggestions. The list only scrolls when it has to, and keeps the next row peeking. Past the last one you reach the options.
- **⌘A ⌘C ⌘V ⌘X ⌘Z** work in the field, through a hidden Edit menu.
- **esc**, **⌘W** or a click outside close the palette.
- **⌘Q** with the palette open quits the app. It starts again at login or from Applications.

### Model, effort, permissions and session

At the bottom, one line says how Claude will be launched: **Model · Effort · Permissions · Session**, each value painted the way Claude Code paints it. **↓** past the last folder (or **⌘↓**, or a click) opens it into one row per option:

| Row | Control | `claude` flag |
|---|---|---|
| Model | full-width segmented control: Default, Fable, Opus, Sonnet, Haiku, each with its number (Opus 5.5). The number is read from the installed `claude` itself, so it updates on its own when Claude Code updates | `--model` with the alias (`opus`), which always runs the newest |
| Effort | an **Auto** pill and a track with the five real levels, Faster to Smarter: low, medium, high, xhigh, max. The ball carries a dot of the level's colour and glows in it; dragged, it follows the pointer and settles on the nearest level. On Auto the track steps back and a hollow ball marks the level Claude will use, "medium · default" | `--effort` |
| Permissions | the modes Claude's Code view offers, in its order: Default, Manual, Accept edits, Plan, Auto, Bypass. The picked one is tinted in its colour; hover a mode to see what it does | `--permission-mode` |
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
- **← →** change the value. On effort, **←** from low goes back to Auto.
- **esc** folds the options; a second **esc** closes the palette.
- **↵** or **⌥C** launch Claude.

Default and Auto add nothing to the command, so Claude's own defaults and your settings apply. Picks are remembered, by name, so reordering values never changes what was picked.

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
defaults write com.aaangelmartin.abrir-claude theme laaabs   # or claude
pkill -x AbrirClaude; open ~/Applications/"Abrir Claude.app"
```

## Install

Requirements:
- macOS 14 or later and Xcode (Swift 6.2 or later)
- the laaabs. kit at `~/Desktop/laaabs/marca/ui-swift`. If it lives elsewhere, change the `path:` in `Package.swift`
- `claude` on a login shell's PATH (`zsh -lic 'command -v claude'`)

```sh
cd ~/Developer/abrir-claude
./scripts/install.sh
```

The script:
1. Builds for arm64 and x86_64.
2. Assembles `build/Abrir Claude.app` and makes the icon from `Resources/claude.svg` (white mark on Claude's orange).
3. Signs with the first valid "Developer ID Application" certificate in the keychain. `SIGN_IDENTITY=-` signs ad hoc.
4. Installs it in `~/Applications` and opens it.

On first launch it adds itself to the login items and shows the palette once.

## macOS permissions

- **Control Terminal** (Automation): asked the first time you open a folder. If you deny it, the palette says so and offers a button to System Settings → Privacy & Security → Automation.
- **Login item**: macOS posts a notification that it was added. Manage it in System Settings → General → Login Items.

The global shortcut needs no Accessibility permission, since it uses `KeyboardShortcuts` (Carbon hotkeys).

## Layout

```
Sources/AbrirClaude/
  App.swift            launch, global shortcut, login item
  PalettePanel.swift   floating panel that never activates the app, keys, position
  PaletteView.swift    the palette in SwiftUI
  Theme.swift          the two styles (claude and laaabs.) and loading Claude's fonts
  PaletteModel.swift   text, rows, selection, notices, options
  FolderPath.swift     from what is typed to an absolute path and a shell command
  Suggestions.swift    folder completion and recents
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
pkill -x AbrirClaude
rm -rf ~/Applications/"Abrir Claude.app"
```

Then remove it from System Settings → General → Login Items if it is still listed.
