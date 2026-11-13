# open claude

A global shortcut (⌥C) opens a palette for Claude Code on your Mac. Each moment has one purpose:

1. **Opened**: every Claude Code session running now, with its state. **↵** goes to it.
2. **Typing**: folders, to start or resume a session in, the best match already highlighted. **↵** opens it; **⌥C** starts a new session there at once, without leaving the field.
3. **A folder**: **New session** first and already highlighted (so **↵ ↵** starts one), then the sessions running there and its past ones, newest first. **↵** starts, goes to or resumes.

While searching and in a folder, where a session starts or resumes, model, effort and permissions sit at the bottom (`claude --resume` takes them too); **⌥↓**, or a click on a value, opens them. Over the running sessions they would mean nothing, so the same bar shows the keys that matter there (**↵** Switch, **⌘↵** New session) and the two crossfade as you start typing.

**esc** backs out one step at a time (the folder, then what is typed, then the palette); **←** also leaves a folder. **⌥C** pressed again, or **⌘↵**, starts a new session at once: in the folder open, else in the highlighted folder or session's folder, else in your home folder. **Tab** with nothing highlighted highlights the first line.

## Running sessions

Read from `~/.claude/sessions` (Claude Code keeps a record there for each live session) and refreshed while the palette is open. Each shows its state with the words and icons Claude's Code view filters by: **Needs input** (a raised hand, in Claude Code's warning yellow), **Working** (a turning arc in Claude's orange, only while Claude itself is working) or **Completed** (a ticked circle, dimmed, once its turn is over), with how long it has been so, its name and its folder. What needs you comes first. Only sessions of the `claude` CLI on this Mac show up; the desktop app and cloud sessions keep no record there.

## Folders

| You type | It lists |
|---|---|
| a name, like `ocl` | folders matching it fuzzily: your home folder's own folders, every folder Claude has run in, the ones opened from here and the git repos under `~/Developer`, best match first and recently used ones a little ahead |
| `projects/my-app`, `~/projects/my-app` or `/Volumes/disk/work` | that path's subfolders, completed with **Tab** |

Each known folder shows its git branch, when it was last used and how many Claude sessions it has, in columns that line up. **↵** (or **→** with the caret at the end) opens the highlighted folder, or what is typed when it is a folder.

## A folder

Past sessions come from `~/.claude/projects`, by their title (the session's own, else its first message); a past one resumes with `claude --resume <id>`. Only the start and end of each session file are read, so even very long sessions list at once.

## Keys

- **↑ ↓** move through the list, and **↑** at the top stays there. Running sessions start with nothing highlighted; a search lights its best match (not when a path ending in `/` lists that folder's subfolders: then **↵** opens the folder itself); a folder lights New session.
- **⌘A ⌘C ⌘V ⌘X ⌘Z** work in the field, through a hidden Edit menu.
- **⌘W** or a click outside close the palette; **⌘Q** quits the app (it starts again at login or from Applications).

## Launch options and plan use

The plan's use sits at the bottom right: the session and the week, each as a small meter with its percentage and the time left until it resets. It is the use as `/usage` gives it: the five-hour session and the week (yellow from 80 %, red from 95 %; hover for when each resets). It is read with the sign-in Claude Code keeps in the keychain, so the first time macOS asks to let Open Claude read "Claude Code-credentials". The sign-in is never refreshed by this app; when it has expired, nothing shows until Claude Code refreshes it.

The line at the bottom says how a new or resumed session is launched: **Model, Effort, Permissions**, each value painted the way Claude Code paints it. **⌥↓** (or a click) opens it into one row per option:

| Row | Control | `claude` flag |
|---|---|---|
| Model | full-width segmented control: Fable, Opus, Sonnet, Haiku, each with its number (Opus 5.5), read from the installed `claude` so it updates on its own. The model Claude starts with (your settings' model, or Opus) is marked *default* | `--model` with the alias (`opus`), which always runs the newest |
| Effort | a track with the five levels, Faster to Smarter: low, medium, high, xhigh, max. The level the chosen model starts with is marked *default* (medium for Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.2), read from the model table inside `claude`; the ball sits there until you pick another. The ball carries a dot of the level's colour and glows in it; dragged, it follows the pointer and settles on the nearest level | `--effort` |
| Permissions | the modes Claude's Code view offers, in its order: Manual, Accept edits, Plan, Auto, Bypass. The mode your settings choose is marked *default*. The picked one is tinted in its colour; hover a mode to see what it does | `--permission-mode` |

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
- **esc** or **⌥↑** fold the options.
- **↵** or **⌥C** launch Claude.

There is no separate "default" value, and every time the palette opens the options start again from the defaults: the value Claude would start with anyway is marked *default*, and picking it adds no flag, so it keeps following Claude and your settings. The `effortLevel` in `settings.json` is a legacy value Claude Code no longer starts sessions with, so it is not used.

The window has a fixed, transparent size and the card grows and shrinks inside it, animated, with its shadow drawn in SwiftUI. The palette comes in with a short fade, the highlight glides from row to row, a folder slides in from the right, the bottom bar crossfades between keys and options, and opening the options brings their rows in one after another.

The shortcut is set in `App.swift` (`openClaudeShortcut`) and applied again on every launch. While the app runs, ⌥C no longer types "©".

Opening the app from Spotlight or Finder also shows the palette. The folder list shows every subfolder, with a thin scroll thumb of its own that appears while scrolling, and edges that fade when there is more above or below. The part of the path already typed is dimmed.

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
  LiveSessions.swift   the claude sessions running now, their state, and bringing one forward
  Terminal.swift       the AppleScript that opens the Terminal window
  LaunchOptions.swift  model, effort, permissions and session, and the claude flags they add
  ModelVersions.swift  the newest model numbers, read from the installed claude
  OptionsView.swift    the summary line, the rows, the effort slider and the painted text
Resources/             Info.plist, entitlements, the claude mark and the aaangelmartin wordmark (svg)
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
