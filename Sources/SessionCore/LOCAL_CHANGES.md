# Local changes

SessionCore started as a copy of the core module of an MIT-licensed app (see `LICENSE-upstream`; upstream
commit in `UPSTREAM_COMMIT`). Changes since:

- Renamed the module; removed files the app doesn't use (dock layout, phone push, keep awake, …).
- `StateBuilder.swift`: `Session.sessionId` (from the registry), passed by `StateBuilder.build`, decoded if
  present. `HiveState` renamed to `SessionsState`.
- `UsageStats.swift`: `UsageStats.bySessionId` and `bySessionIdToday`, filled in `aggregate`, so usage can be
  shown per session even when the transcript has no title (sessions started without `-n`).
- `Util.swift`: `AppData.dir` (`~/.switchboard`); `ContextUsage`, `Notes` and `PlanLimits` read from it.
- `Registry.swift`, `StateBuilder.swift`, `TmuxMatch.swift`: `tmuxSession` from the registry's `tmux` field; a
  pane id only matches when the tmux session name agrees (pane ids restart at %0 on every tmux server).
- `Transcript.swift`, `StateBuilder.swift`, `UsageLimit.swift`: `LimitHit` (the conversation stopped at a usage
  limit) and its reset time, for continuing sessions when the limit resets.
- Comments and identifiers no longer refer to the upstream app.
