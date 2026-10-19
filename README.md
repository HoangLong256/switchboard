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
  - Search, a context menu, and ⌘N for a new session: a tmux session with `claude -n <name>` typed in.
- **Folder sidebar**: the selected session's working directory as a tree.
  - It updates live as the session writes files, marks git changes (M / A / D / U), shows the branch, and
    offers a worktree picker for repositories with linked worktrees (`claude --worktree`).
  - A filter, and a toggle for hidden files.
- **Editor**, with the same rules as VS Code's Explorer and editor:
  - A single click previews a file in an *italic* tab that the next preview replaces, and focus stays in the
    tree. A double click or Return keeps it open and moves focus into the editor. Arrow keys only move the
    selection; Space previews.
  - Editing pins the tab. Unsaved changes show a dot on the tab and a count on the Editor tab ("Editor •2").
  - ⌘S saves, ⌥⌘S saves all. ⌘W closes the editor, asking Save / Don't Save / Cancel when there are changes.
    Quitting with unsaved files asks too.
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
⌘W close editor · ⌘D favorite · ⌘R refresh · ⌘, settings.

## Run

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
