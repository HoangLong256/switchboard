# Switchboard

A macOS app for running several Claude Code sessions side by side. You get every session at a glance, the
selected session's terminal, a **folder sidebar** with a VS Code-style editor, usage and plan limits, and
Claude Code's **agent teams**.

```
┌ Sessions ─────────┬ Folder ───────────┬ Terminal │ Editor │ Team │ Handover │ Notes │ Info ┐
│ ● shop.lead       │ switchboard ⑂ main│                                                    │
│    ● api  working │ ▸ Sources       • │   tmux terminal, open files as tabs (preview /     │
│    ● ui   working │   Package.swift U │   pinned, dirty dot, ⌘S), the agent team, …        │
│ ● blog.01         │   README.md     M │                                                    │
│ 5h 24% · Week 24% │                   │                                                    │
└───────────────────┴───────────────────┴────────────────────────────────────────────────────┘
```

## Features

- **Sessions**: every Claude Code session on this Mac, read from `~/.claude/sessions`, the transcripts and
  handovers.
  - Sorted by what needs you first, with favorites on top. Each row has a status dot (needs you / working /
    ready / offline) and its tokens.
  - Search, a context menu, and ⌘N for a new session: a tmux session that runs `claude -n <name>` right away
    (or only types it in, if you turn off *Start Claude right away*). The name defaults to the folder's name.
  - **Grouping**: group the sessions by parent folder (the folder their working folder is in, e.g. all
    sessions under `~/Workplace/Personal Projects`) or by status (the group button in the toolbar, or Settings).
    Each group is a section you can fold, with its size and how many sessions need you.
  - **Sessions started elsewhere** (in VS Code, iTerm or Terminal) are listed too, but their terminal belongs to
    that app. **Move into Switchboard…** (in the Terminal tab or the row's context menu) ends the session there,
    as closing its window would, and continues the same conversation in Switchboard's terminal
    (`claude --resume <id>`). Offline sessions have **Resume in Switchboard**.
  - The model and effort the selected session runs with ("Opus 5.5 · High") show next to its tabs; click for
    context and cost. They come from the live status line, else the model of the transcript's last response.
- **Folder sidebar**: the selected session's working directory as a tree.
  - It updates live as the session writes files, marks git changes (M / A / D / U), shows the branch, and
    offers a worktree picker for repositories with linked worktrees (`claude --worktree`).
  - A filter, and a toggle for hidden files.
  - **File icon themes** like VS Code's: Seti (colored glyphs per language), Material (colored folders) or
    Minimal. In Settings or View ▸ File Icon Theme. File names take their git color.
- **Source Control**, like VS Code's: switch the folder sidebar from Explorer to Changes.
  - Merge Changes, Staged Changes and Changes, with Stage (+), Unstage (−), Discard (to the Trash for new files)
    per file or for all, and a commit box (⌘↩).
  - A click opens the file's changes in a diff tab: side by side or inline, unchanged regions folded, in the
    theme's colors. Staged changes compare HEAD with the index, the others the index with the file.
- **Editor**, with the same rules as VS Code's Explorer and editor:
  - A single click previews a file in an *italic* tab that the next preview replaces, and focus stays in the
    tree. A double click or Return keeps it open and moves focus into the editor. Arrow keys only move the
    selection; Space previews.
  - Editing pins the tab. Unsaved changes show a dot on the tab and a count on the Editor tab ("Editor •2").
  - ⌘S saves, ⌥⌘S saves all. ⌘W closes the editor, asking Save / Don't Save / Cancel when there are changes.
    Quitting with unsaved files asks too.
  - Right-click a tab, or use the "…" at the end of the tab bar: Close, Close Others (⌥⌘T), Close to the Right,
    Close Saved, Close All (⌥⌘W). Unsaved files are asked about once, with Save All / Don't Save / Cancel.
  - **Themes** for the whole app (sidebars, editor, and the terminal with its 16 ANSI colors), with the palettes
    of the VS Code themes: Light / Dark Modern (Automatic keeps the macOS look), Dracula, One Dark Pro, Monokai,
    GitHub Dark / Light, Nord, Solarized Dark / Light. A theme is light or dark by itself, so it takes over from
    Appearance. Pick one from the palette button above the file, View ▸ Theme, or Settings. Code gets simple
    syntax colors (comments, strings, numbers, keywords, types, calls).
  - Files a session changes on disk reload by themselves while you have no unsaved changes. If you do, saving
    stops with **Compare / Overwrite / Revert** instead of overwriting the session's work.
  - Binary, oddly encoded and very large files show a notice with **Open Anyway**. Markdown has a preview;
    images are shown directly.
  - Drag a file onto the terminal, or use *Insert @Path into Terminal*, to hand it to Claude.
- **Agent teams** (Claude Code's experimental `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`):
  - Turn on *Agent team* in New Session to enable it for that session only.
  - Teammates appear under their lead in the session list, with their color, state and current task.
  - The lead's **Team** tab shows the members, the shared task board (pending / in progress / done, with
    blockers), and the messages between them.
  - Read from `~/.claude/teams/<team>/` and `~/.claude/tasks/<team>/`. Split-pane teammates run as panes of
    the lead's tmux session, so they show in its terminal.
- **Usage**:
  - **Per session**: tokens over 31 days, including subagents, and their value at API list prices. The Info
    tab breaks it down, plus cost, context, model and effort as Claude Code reports them.
  - **Plan limits**: 5-hour and weekly bars at the bottom of the sessions column, colored by whether you'll
    last until the reset. Click them for details: pace, model-specific limits, tokens per day, and the top
    sessions and projects. Works on individual Pro and Max plans.
  - Live limits come from Claude Code's status line. **Set Up Live Status Line…** in the usage popover copies
    `switchboard-statusline` to `~/.switchboard/bin` and sets `statusLine` in `~/.claude/settings.json`,
    after asking and with a backup.
- **Keep awake**: while any session works, Switchboard holds a power assertion (like `caffeinate`) and lets go
  as soon as none does. It shows in `pmset -g assertions` as "Switchboard: 2 sessions working". There are
  options to keep the display on, and to stay awake while a session waits to be continued. Use the **Awake**
  switch at the bottom of the sessions column, or Settings (⌘,). Closing the lid still sleeps a MacBook on
  battery.
- **Continue after usage limits**:
  - When a session stops with Claude Code's "You've hit your session limit · resets 3:10pm" (in the
    transcript: `apiError: usage_limit_reached`), Switchboard types `continue` into it a minute after the
    reset, once per hit.
  - The reset time comes from the message, or from the live 5-hour and weekly windows.
  - The row shows "limit · continues 3:10pm". The Info tab has Continue Now and a per-session switch.
  - Only for sessions in Switchboard's tmux server, and only if nothing was said since the limit.
  - New sessions can instead start with Claude Code's own unattended retry (`CLAUDE_CODE_RETRY_WATCHDOG=1`,
    with a maximum wait). It waits at the limit inside the request and carries on by itself.
- **Terminal / Handover / Notes / Info**:
  - Terminal: the session's real terminal, from Switchboard's own tmux server (`tmux -L switchboard`).
  - Handover: `~/.claude/handover/<name>.md`, rendered.
  - Notes: a notepad per session, in `~/.switchboard/notes`.
  - Info: folder, branch, PID, context, the "Now" line, and the last messages.

Shortcuts: ⌘N new session · ⇧⌘H next waiting session · ⌘J focus terminal · ⌘1–6 tabs · ⌘S / ⌥⌘S save ·
⌘W close editor · ⌥⌘T close others · ⌥⌘W close all · ⌘D favorite · ⌘R refresh · ⌘, settings.

## Download

1. Get `Switchboard-<version>.dmg` from [Releases](../../releases/latest). It runs on Apple silicon and Intel, macOS 14+.
2. Open it and drag Switchboard to Applications.
3. The first time only: macOS blocks the app because it isn't signed with an Apple Developer ID. Open it once,
   choose Done, then go to System Settings → Privacy & Security and click **Open Anyway**. You can also run
   `xattr -dr com.apple.quarantine /Applications/Switchboard.app` in Terminal instead.

It needs `brew install tmux` and Claude Code (`claude`) on the Mac.

New versions are tagged by themselves: when CI passes on `main`, **Auto Tag** looks at the commit messages since the
last tag and releases the next version, with the app built on GitHub Actions and attached to the release.

| Commit message | Version | Example |
|---|---|---|
| `feat: …` or `feature: …` | minor | v0.2.1 → v0.3.0 |
| `fix: …` or `bug: …` | patch | v0.2.1 → v0.2.2 |
| anything else (`docs:`, `ci:`, `chore:`, …) | no release | |

A scope works too (`feat(editor): …`), and with several commits the biggest bump wins. `sh scripts/next-version.sh`
prints what would be released. A tag pushed by hand (`git tag v1.0.0 && git push --tags`) still releases, e.g. for a
major version. `sh scripts/release.sh` makes the same .dmg and .zip locally, in `dist/`.

## Run from source

Needs macOS 14+, Xcode or the Swift toolchain, and `brew install tmux`.

```sh
swift run Switchboard                                    # debug
swift run Switchboard --select blog.01 --open ~/x.swift  # preselect a session / open a file
sh scripts/bundle.sh --install                           # release build → ~/Applications/Switchboard.app
swift test                                               # folder tree, editor rules, teams, status line, tmux matching
SWITCHBOARD_TMUX=sb-test swift run Switchboard           # another tmux server, for trying things out
```

Data: `~/.switchboard` (status line output, notes). Environment: `SWITCHBOARD_TMUX`, `SWITCHBOARD_DATA`,
`SWITCHBOARD_HOME` (read `.claude` from another home folder, for tests).

## Structure

- `SessionCore`: reads the Claude Code registry, transcripts, handovers and usage.
- `FolderKit`: folder listing, tree and filter, git status, worktrees.
- `EditorKit`: editor tabs and documents with VS Code's preview, dirty and save-conflict rules.
- `TeamKit`: agent teams from `~/.claude/teams` and `~/.claude/tasks`.
- `StatusLineKit`, `switchboard-statusline`: the status line command (plan limits, context, cost per session).
- `Switchboard`: the SwiftUI app. It uses SwiftTerm for the terminal and MarkdownUI.

## Credits

`SessionCore` is based on MIT-licensed code by TBIMYR. See `Sources/SessionCore/LICENSE-upstream` and
`LOCAL_CHANGES.md`.
