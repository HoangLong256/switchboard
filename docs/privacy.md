# Privacy

Switchboard runs only on your Mac. It has no server and no telemetry. Its code does not connect to the
network: `Sources/` contains no `URLSession` and no other network calls.

## Data that Switchboard reads

- `~/.claude`: sessions, transcripts, handovers, teams, tasks and `settings.json`. Switchboard uses them for the
  session list, usage and teams.
- `~/.claude.json`: only the usage cache (`cachedUsageUtilization`). Switchboard ignores the other data in this
  file.

## Data that Switchboard writes

- `~/.switchboard`: notes and status line data.
- The files that you save in the editor.
- `~/.claude/settings.json`: only when you select *Set Up Live Status Line…* or *Set Up Handover…*. Switchboard
  asks first and makes a backup.
- `~/.claude/CLAUDE.md`: only when you select *Set Up Handover…*. Switchboard adds one marked section and makes a
  backup. *Turn Off Handover* removes the section.
- `~/.claude/handover/<session>.md`: Claude writes these files with `switchboard-task`.

## Programs that Switchboard runs

- `tmux`, on its own server (`tmux -L switchboard`)
- `git`, for status, diffs, stage and commit
- Your login shell, one time, to find your `PATH`

Claude Code runs in the tmux session with your account and settings. Switchboard does not read your
credentials or the Keychain.

## Move into Switchboard

*Move into Switchboard* sends SIGHUP and then SIGTERM to the Claude process in the other app. This has the same
effect as when you close its window. Then Switchboard starts the same conversation in its own terminal.

## Usage figures

Switchboard calculates usage from your local transcripts. The value at API list prices is an estimate. It is
not a bill.

## Remove the data

Delete `~/.switchboard` to remove all data of Switchboard. This does not change the Claude Code data in
`~/.claude`.
