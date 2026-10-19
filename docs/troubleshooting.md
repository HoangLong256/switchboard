# Troubleshooting

## macOS does not open the app

**Cause:** The app does not have an Apple Developer ID. It has only an ad-hoc signature.

**Solution:**

1. Open System Settings → Privacy & Security.
2. Click **Open Anyway**.

You can also run this command:

```sh
xattr -dr com.apple.quarantine /Applications/Switchboard.app
```

## The app shows "tmux not installed"

**Cause:** Switchboard cannot find tmux. It looks in `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`.

**Solution:** Install tmux:

```sh
brew install tmux
```

## The Terminal tab shows "Runs in Visual Studio Code" (or iTerm, or Terminal)

**Cause:** The session started outside of Switchboard. Its terminal is in the other app.

**Solution:** Click **Move into Switchboard…**. For an offline session, click **Resume in Switchboard**.
For more, see [Sessions from other apps](features.md#sessions-from-other-apps).

## The plan limits do not change

**Cause:** The live status line is not set up.

**Solution:**

1. Click the usage bars at the bottom of the session list.
2. Click **Set Up Live Status Line…**.

Then make sure that `statusLine` in `~/.claude/settings.json` points to
`~/.switchboard/bin/switchboard-statusline`.

## A button in the folder sidebar does nothing

**Cause:** Some buttons work only in one mode. For example, the hidden files button works only in Explorer.

**Solution:** Click **Explorer** or **Changes** at the top of the sidebar. Hold the pointer on a button to see
what it does.

## Use a session from a different terminal

Run this command. Replace `<name>` with the name of the session:

```sh
tmux -L switchboard attach -t <name>
```

## Remove all data of Switchboard

Delete `~/.switchboard`. This does not change the Claude Code data in `~/.claude`.
