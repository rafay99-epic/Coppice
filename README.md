# Coppice

Your coding agents create a git worktree per task and never clean up. Coppice finds all of them, works out which are genuinely safe to touch, and reclaims the space without eating uncommitted work or a live session.

Free and open source under MIT, Apple Silicon only. It lives in the menu bar and has no Dock icon.

> Coppicing is cutting a tree back to the stump so it regrows. That is the operation: delete the regenerable parts, and one install command brings them back.

## Install

```sh
brew install --cask rafay99-epic/apps/coppice
```

Installs to `/Applications` with no macOS security prompt, and Coppice updates itself after that. Requires macOS 15+ on Apple Silicon.

Living on the edge? The **Nightly** channel installs alongside Stable as a separate app with its own icon and settings, and auto-updates from the newest pre-release:

```sh
brew install --cask rafay99-epic/apps/coppice-nightly
```

Prefer a direct download? Grab the [`.dmg`](https://github.com/rafay99-epic/Coppice/releases/latest/download/Coppice.dmg). It is not notarized (no paid Apple Developer account), so **right-click → Open** the first time to get past Gatekeeper. Homebrew is the smoother path.

## The workflow

Coppice is meant to be ignored until it is useful. Nothing here needs a schedule or a cron job.

**1. It watches, it does not poll.** After launch it registers the agent worktree directories and your own code folders with FSEvents and then does nothing. The kernel wakes it only when one of those directories actually changes, and events coalesce, so an install writing a hundred thousand files arrives as a single callback. Idle cost is 0.0% CPU.

**2. A change triggers a scan.** One `git worktree list --porcelain` per repository builds the inventory in about three seconds. Each worktree then gets a verdict from the eleven rules below. The list is usable at this point.

**3. Sizes stream in afterwards.** A background walk measures each worktree one at a time at low priority, stopping at the first artifact directory rather than descending into it. Rows show a dash until their size lands, and the toolbar shows how many are left. Nothing blocks on measuring 76 GB.

**4. Pull request state fills in last.** If the GitHub CLI is installed, Coppice runs one `gh pr list` per repository and matches PRs to branches. A merged or closed PR is the clearest signal that a worktree is finished.

**5. You act, from the menu bar or the window.** The menu bar item shows reclaimable space once it crosses your threshold. Clicking it offers **Sweep**, which is the reversible one and the only action offered without opening the window. Everything destructive lives in the window behind a selection.

**6. Every deletion re-verifies first.** This is the part that matters. Coppice scans on its own schedule, so a verdict can be minutes old by the time you press a button, and in those minutes an agent may have opened the worktree you picked. Every rule is recomputed at the instant of deletion. If the answer changed, that item is skipped and reported rather than deleted.

**7. Results are reported, not swallowed.** Progress is per worktree with a running freed total. The outcome is a banner that distinguishes success from a partial run from an outright failure, listing every skipped and failed path with its reason. Everything also goes to `~/Library/Application Support/Coppice/activity.log`.

### Three states

Every worktree is **Ready**, **Has work** or **In use**.

| State | Meaning | Remove |
| --- | --- | --- |
| **Ready** | Clean and pushed | Move to Trash |
| **Has work** | Uncommitted files, unpushed commits, local config, a lock or a rebase in progress | Move to Trash, and the dialog lists what goes with it |
| **In use** | An agent, editor or dev server is running inside it | Refused |

Removal moves the folder to the Trash, so uncommitted files come back from there. Commits live in the repository, so they stay on the branch unless you also delete it. Gitignored config like `.env.local` is copied to `~/Documents/Coppice Rescue` first. Your main checkout and paths outside your folders are never touched.

## What it does

Three operations, sorted by what they cost you.

| | What it does | Reversible |
| --- | --- | --- |
| **Sweep** | Deletes build output inside worktrees: `node_modules`, `.next`, `target`, `DerivedData`. Never touches source or git state. | Yes, by reinstalling |
| **Prune** | Clears git metadata for worktrees whose directories are already gone. | Frees no space |
| **Remove** | Moves the worktree to the Trash, prunes the metadata, optionally deletes the branch. | From the Trash |

Sweep is the default and reclaims most of the space. Remove works one worktree at a time. There is no Remove All anywhere in the product.

## Safety

Coppice refuses to remove a worktree for any of eleven reasons:

1. A process is working inside it (an open session, editor or dev server)
2. Uncommitted changes
3. Untracked files
4. Unpushed commits
5. No upstream, and commits missing from the default branch
6. Gitignored config such as `.env.local`
7. The worktree is locked
8. A rebase, merge, cherry-pick or bisect is in progress
9. A submodule has local changes
10. The path is outside your configured roots
11. It is the repository's own working copy

**Rule 6 is the one that matters.** A `.env.local` is gitignored, so `git status` reports the worktree as perfectly clean while it holds live secrets. A cleaner that trusts git alone deletes it with no warning and no copy anywhere.

Eight of these eleven mark a worktree as Has work, as described in [Three states](#three-states). Only a live process, the main worktree and the folder boundary refuse removal.

Every rule is recomputed **at the moment of deletion**, not when the list was built. Coppice scans in the background, so a verdict can be minutes old by the time you press a button, and in those minutes an agent may have opened the very worktree you picked.

Sweeping ignores every rule but the first. `node_modules` is not source and is not tracked, so a dirty worktree still sweeps.

## No polling

A timer re-scanning your worktrees every minute would burn battery all day to learn nothing almost every time. Coppice uses FSEvents, so the kernel wakes it only when a watched directory actually changes, and events coalesce so a 100k-file install arrives as one callback.

Measured on a machine with 52 worktrees across 36 GB: **0.0% CPU idle, 99 MB memory, 3 seconds** to inventory and judge every worktree. The installer is 1.3 MB and the app has zero dependencies.

## Monorepo layout

| App | Path | Stack |
| --- | --- | --- |
| Desktop app | [`apps/desktop`](apps/desktop) | Swift / SwiftUI (Swift Package Manager) |
| Website | [`apps/website`](apps/website) | Next.js + Tailwind |

Tooling: [bun](https://bun.sh) workspaces + [turbo](https://turborepo.com).

## Working in the repo

```sh
bun install              # once, at the root

bun run build            # build everything
bun run build:website    # just the site
bun run build:desktop    # just the app (macOS only)
bun run dmg              # app + DMG installer
bun run test             # swift test
```

For the **desktop app** (macOS, from `apps/desktop`):

```sh
swift build      # compile
swift test       # run the suite
./dev.sh         # build + run "Coppice Dev" locally — your sandbox, never published
./nightly.sh     # build + run "Coppice Nightly" locally
./make-dmg.sh    # package the installer
osascript -l JavaScript Scripts/ui-check.js   # read-only UI check of the running Dev app
```

Building requires full Xcode, not just Command Line Tools, because SwiftUI's macros ship with the full toolchain.

The website dev server: `cd apps/website && bun run dev`.

Website end-to-end tests run in headless Chrome on port 4390, so they never touch a dev server you already have open:

```sh
cd apps/website
bun run test:e2e                                        # builds, serves and tests the static site
E2E_BASE_URL=http://localhost:3000 bun run test:e2e     # same tests against a running dev server, which also catches hydration warnings
```

## Release channels

Coppice ships in three channels that install **side by side** with separate apps, icons, settings and data:

| Channel | Install | Source branch | Updates from |
| --- | --- | --- | --- |
| **Stable** | `brew install --cask rafay99-epic/apps/coppice` | `main` | the latest release |
| **Nightly** | `brew install --cask rafay99-epic/apps/coppice-nightly` | `nightly` | the newest pre-release |
| **Dev** | build locally — `./dev.sh` | any branch | never |

- **`main` is Stable.** A curated release, cut by promoting `nightly → main` as a squash. Each push to `main` publishes a full release (`Coppice.dmg`, version `0.<commit count>`).
- **`nightly` is the integration branch.** Every merge auto-publishes a rolling pre-release ordered by CI build number.
- **Dev is local-only.** `./dev.sh` builds *Coppice Dev*; it never publishes and has no updater.

Releases are signed with a stable self-signed certificate rather than ad-hoc. macOS keys permission grants to the signature, so an ad-hoc build would look like a brand-new app on every update and silently drop the Full Disk Access grant.

## Contributing

1. **Branch from `nightly`** (`feat/…`, `fix/…`, `chore/…`) and open your PR **against `nightly`**. The default branch is `main`, so switch the base when you open it.
2. **`main` is protected.** Stable only moves via the promotion workflow.
3. Build and run your change with **`./dev.sh`**, which installs *Coppice Dev* next to your real app.
4. CI runs `swift test` + SwiftLint + a packaged build on every PR.

If you touch the verdict engine, add a case to `Tests/CoppiceTests/VerdictTests.swift`. Those tests build real git repositories rather than mocks, because the whole safety model is a claim about what git actually reports.

## License

MIT. See [LICENSE](LICENSE).
