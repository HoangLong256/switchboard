# Development

This document tells you how to build Switchboard, how the code is organized, and how releases work.
To send a change, also read [CONTRIBUTING.md](../CONTRIBUTING.md).

## Requirements

- macOS 14 or later
- Xcode, or the Swift 5.10 toolchain
- tmux (`brew install tmux`)

## Build and run

```sh
git clone https://github.com/HoangLong256/switchboard.git
cd switchboard
swift run Switchboard
```

| Command | Result |
|---|---|
| `swift run Switchboard` | Builds and runs a debug version. |
| `swift run Switchboard --select blog.01 --open ~/x.swift` | Selects a session and opens a file at start. |
| `swift test` | Runs the tests. |
| `sh scripts/bundle.sh --install` | Builds a release version into `~/Applications/Switchboard.app`. |
| `sh scripts/release.sh` | Builds the universal app (arm64 and x86_64) into `dist/` as a `.dmg` and a `.zip`. |

> [!TIP]
> Use a separate tmux server to test your changes. Then your real sessions do not change:
> `SWITCHBOARD_TMUX=sb-test swift run Switchboard`

## Data and environment variables

| Location or variable | Purpose |
|---|---|
| `~/.switchboard` | The data of Switchboard: status line output, notes, `bin/switchboard-statusline` |
| `~/.claude` | The data of Claude Code. Switchboard only reads it, with one exception: *Set Up Live Status Line…* changes `settings.json`. |
| `SWITCHBOARD_TMUX` | The name of the tmux server. The default is `switchboard`. |
| `SWITCHBOARD_DATA` | A different folder for `~/.switchboard` |
| `SWITCHBOARD_HOME` | A different home folder that contains `.claude`, for tests |

## Project structure

Switchboard is one Swift package. The user interface is in one target. The logic is in modules without user
interface. Each of these modules has a test target.

| Target | Contents |
|---|---|
| `Switchboard` | The SwiftUI app: session list, terminal, editor, diffs, themes, settings |
| `SessionCore` | Reads the Claude Code registry, transcripts, handovers and usage |
| `FolderKit` | Folder listing, tree, filter, git status, git changes, worktrees |
| `EditorKit` | Editor tabs and documents, with the preview, unsaved and save conflict rules of VS Code |
| `TeamKit` | Agent teams from `~/.claude/teams` and `~/.claude/tasks` |
| `StatusLineKit` | The data that the status line command keeps for the app |
| `switchboard-statusline` | The status line command that Claude Code runs |

Dependencies:

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for the terminal
- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) for formatted Markdown

Other folders:

- `Tests/`: one test target for each module
- `.github/workflows/`: `ci.yml`, `release.yml`, `auto-tag.yml`
- `scripts/`: `bundle.sh`, `release.sh`, `next-version.sh`

## Releases

Releases are automatic. When CI passes on `main`, the **Auto Tag** workflow reads the commit messages since
the last tag. It then pushes the next version tag and starts the **Release** workflow. The Release workflow
builds the universal app and attaches the `.dmg` and the `.zip` to a GitHub release.

The commit message sets the version:

| Commit message | Version change | Example |
|---|---|---|
| `feat: …` or `feature: …` | Minor | v0.2.1 → v0.3.0 |
| `fix: …` or `bug: …` | Patch | v0.2.1 → v0.2.2 |
| Other (`docs:`, `ci:`, `chore:`, …) | No release | |

- A scope is permitted, for example `feat(editor): …`.
- If there are many commits, the largest change applies.
- `sh scripts/next-version.sh` shows the next version. It shows nothing if no release is necessary.
- To release a major version, push a tag: `git tag v1.0.0 && git push --tags`.
- To only build the app, start the Release workflow manually (Actions ▸ Release ▸ Run workflow). The app is
  then an artifact of the run.

> [!WARNING]
> A `feat:` or `fix:` commit on `main` publishes a public release.
