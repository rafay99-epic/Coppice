# Coppice

Coding agents create a git worktree for every task and never clean up. Coppice is a macOS menu bar app that finds those worktrees, tells you which ones are safe to clean, and frees the space without touching uncommitted work or a session that is still running.

Free and open source under the [MIT license](LICENSE).

## Why

Every agent task gets its own copy of your repository, usually with its own `node_modules`. After a few weeks one laptop can hold dozens of forgotten worktrees and tens of gigabytes. Deleting them by hand is risky, because some still hold uncommitted edits, local `.env` files or a running agent. Coppice checks all of that before it lets you delete anything.

## What it does

| Action | What happens | How you undo it |
| --- | --- | --- |
| **Sweep** | Deletes rebuildable output such as `node_modules`, `.next`, `target` and `DerivedData`. Source and git history stay. | Run your install command |
| **Move to Trash** | Moves a whole worktree to the Trash and clears its git metadata. | Restore it from the Trash |
| **Prune** | Clears git records for worktrees whose folders are already gone. | Nothing to undo |

It finds worktrees from Claude Code, Codex, T3 Code, Cursor, Command Code, OpenCode and ones you made by hand.

## Install

```sh
brew install --cask rafay99-epic/apps/coppice
```

Coppice updates itself after that. To test upcoming changes, install the Nightly channel next to it:

```sh
brew install --cask rafay99-epic/apps/coppice-nightly
```

You can also download the [`.dmg`](https://github.com/rafay99-epic/Coppice/releases/latest/download/Coppice.dmg). It is not notarized, so right-click it and choose **Open** the first time.

## Requirements

- macOS 15 or later on Apple Silicon
- `git`, which comes with the Xcode Command Line Tools
- Optional: the [GitHub CLI](https://cli.github.com) (`gh`). With it, Coppice can see which branches already have a merged pull request.

Coppice has no third-party dependencies.

## Safety at a glance

Every worktree is in one of three states:

| State | Meaning | Remove |
| --- | --- | --- |
| **Ready** | Clean and pushed | Moves to the Trash |
| **Has work** | Uncommitted files, unpushed commits, local config and similar | Moves to the Trash, and the dialog lists what goes with it |
| **In use** | An agent, editor or dev server is running inside it | Refused |

- Every check runs again at the moment you click, not when the list was built.
- Gitignored config such as `.env.local` is copied to `~/Documents/Coppice Rescue` before anything moves.
- Your main checkout and folders outside the ones you chose are never touched.
- Nothing is ever deleted unless you click.

The full rules are in [Safety](docs/safety.md).

## Repository layout

```
apps/
  desktop/              macOS app (Swift, SwiftUI, Swift Package Manager)
    Sources/Coppice/
      App/              app entry, menu commands, menu bar icon
      Models/           app state, worktree verdicts, scan scheduling
      Services/         git, scanning, sweeping, file watching, logging
      Updates/          self-updater
      Views/            windows, menu bar panel, onboarding, settings
    Tests/              unit tests, plus tests that run against real git repositories
    Scripts/            icon generator and UI check
    Resources/          Info.plist and bundled fonts
  website/              landing page (Next.js, Tailwind)
docs/                   the guides linked below
.github/workflows/      CI, nightly builds, promotion, website deploy
```

## Documentation

- [How it works](docs/how-it-works.md): scanning, file watching, supported agents, logs
- [Safety](docs/safety.md): every rule Coppice checks before it deletes anything
- [Development](docs/development.md): building, testing and running locally
- [Releasing](docs/releasing.md): release channels, versioning and promoting Nightly to Stable
- [Contributing](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md)

## License

MIT. See [LICENSE](LICENSE).
