# Contributing to Switchboard

Thank you for your help. Issues and pull requests are welcome.

## Report a problem

1. Look for the problem in the [issues](https://github.com/HoangLong256/switchboard/issues).
2. If it is not there, open a new issue.
3. Write the steps that cause the problem, the result, and the result that you expected.
4. Write your macOS version and the Switchboard version.

Before you send logs or screenshots, remove private data, for example session names and folder paths.

## Send a change

1. Fork the repository and clone it.
2. Make a branch for your change.
3. Do your change. Read the rules below.
4. Run `swift build` and `swift test`. Make sure that both pass.
5. Push the branch and open a pull request.

CI runs the build and the tests on each pull request. For build commands, see
[docs/development.md](docs/development.md).

## Rules for code

- Put logic in a module without user interface: `SessionCore`, `FolderKit`, `EditorKit`, `TeamKit` or
  `StatusLineKit`. Add tests for it.
- Keep the `Switchboard` target for views and the connections between them.
- Write code like the code near it. Use the same names, comments and style.
- Test with a separate tmux server: `SWITCHBOARD_TMUX=sb-test swift run Switchboard`.
- If you change `SessionCore`, add a line to `Sources/SessionCore/LOCAL_CHANGES.md`. This file records the
  differences from the original code.

## Commit messages

The commit message sets the next release. Start each message with one of these prefixes:

| Prefix | Use it for | Result |
|---|---|---|
| `feat:` | A new feature that users can see | Minor release |
| `fix:` | A bug fix | Patch release |
| `docs:`, `ci:`, `chore:`, `refactor:`, `test:` | Other changes | No release |

For more about releases, see [docs/development.md](docs/development.md#releases).

## License

When you send a change, you agree that it has the [MIT License](LICENSE) of the project.
