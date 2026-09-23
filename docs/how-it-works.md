# How it works

Coppice does nothing until something changes. Nothing needs a schedule or a cron job.

## 1. It watches instead of polling

At launch, Coppice asks macOS (FSEvents) to watch your code folders and each agent's worktree folder. It only rescans when a worktree is created or removed, not when an agent edits files inside one. Automatic rescans happen at most once a minute. Idle CPU use is 0%.

## 2. A scan builds the list

For each repository, one `git worktree list --porcelain` call finds its worktrees. Coppice then gives each worktree a state (Ready, Has work or In use) using the rules in [Safety](safety.md). A full scan of about 50 worktrees takes around three seconds.

Repositories are found two ways:

- Folders up to two levels deep inside your code folders (for example `~/Code/app` or `~/Code/org/app`).
- Each agent worktree's `.git` link, which points back to its repository at any depth.

## 3. Sizes arrive afterwards

A low-priority background task measures each worktree one at a time, so the list is usable before sizing finishes. Rows show `…` until their size is known.

## 4. Pull requests fill in last

If the GitHub CLI is installed, Coppice runs `gh pr list` once per repository and matches pull requests to branches. The results are cached for ten minutes. A merged pull request counts only when its last commit is exactly the branch tip, so commits made after the merge still show as your work.

## 5. You decide what to clean

The menu bar shows how much space a Sweep would free. Sweep asks once to confirm. Everything else happens in the main window, one worktree at a time.

## 6. Everything is logged

Every sweep, removal, rescue, error and crash is written to:

```
~/Library/Application Support/Coppice/activity.log
```

Nightly and Dev builds use `Coppice Nightly` and `Coppice Dev` folders instead. Warning banners in the app have an **Open log** button.

## Supported agents

| Agent | Where its worktrees live |
| --- | --- |
| Claude Code | `~/.claude/worktrees` and `<repo>/.claude/worktrees` |
| Codex | `~/.codex/worktrees` and `<repo>/.codex/worktrees` |
| T3 Code | `~/.t3/worktrees` |
| Cursor | `~/.cursor/worktrees` and `<repo>/.cursor/worktrees` |
| Command Code | `~/.commandcode/worktrees` |
| OpenCode | `~/.local/share/opencode/worktree` |
| Manual | anything else git knows about |

You can hide any agent in **Settings › Scanning**. New agents appear by default.

## Full Disk Access

Coppice only needs Full Disk Access if one of your code folders is in a protected place such as Documents or Desktop. When it can't read a folder, a banner tells you which one and opens the right System Settings page.
