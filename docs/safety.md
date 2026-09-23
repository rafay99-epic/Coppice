# Safety

Coppice deletes things, so it is built to refuse whenever it is unsure.

## The three states

| State | Remove | Sweep |
| --- | --- | --- |
| **Ready** | Moves to the Trash | Yes |
| **Has work** | Moves to the Trash, and the dialog lists what goes with it | Yes |
| **In use** | Refused | Refused |

## The rules

Coppice checks eleven things. Three of them refuse removal outright:

1. **A process is running inside the worktree.** Deleting a folder that an agent, editor or dev server is using can corrupt what it is writing.
2. **It is the repository's main checkout.** Removing it would break the repository.
3. **It is outside the folders you chose.** Symlinks are resolved first, so a link cannot point Coppice somewhere else.

The other eight mark a worktree as **Has work**. You can still move it to the Trash, and the dialog lists everything that goes with it:

4. Uncommitted changes
5. Untracked files
6. Unpushed commits
7. No upstream, and commits that are not on the default branch
8. Gitignored config files such as `.env.local`
9. A `git worktree lock`
10. A rebase, merge, cherry-pick or bisect in progress
11. A submodule with local changes

## Why removal is still safe

- **The folder goes to the Trash**, so uncommitted and untracked files can be restored from there.
- **Commits live in the repository**, not the worktree. They stay on the branch unless you also tick **Delete branch too**.
- **Branch deletion uses `git branch -d`**, which refuses unmerged branches. It only uses `-D` when the branch's pull request is merged and its last commit matches the branch tip.
- **Gitignored config is copied first** to `~/Documents/Coppice Rescue/<repo>/<worktree> <time>`. Each rescue gets its own timestamped folder, so a new rescue never overwrites an old one.

## Checks run again when you click

Coppice scans in the background, so the list can be minutes old when you click. Every rule is checked again at that moment. If a worktree became In use in the meantime, Coppice skips it and tells you why.

## Sweep is narrower

Sweep only deletes rebuildable build output, and only the In use rule can stop it. A few extra checks still apply:

- A folder counts as build output only when its manifest sits next to it. For example, `target` needs a `Cargo.toml` beside it.
- A folder that git tracks, such as a committed `dist/` or `vendor/`, is never swept.
- Anything that resolves outside its worktree through a symlink is skipped.

## Errors and crashes

- Failed git commands, unreadable repositories and GitHub CLI errors are logged, and a banner shows which repositories were skipped.
- If Coppice crashes, it writes a `CRASH` line to the activity log before it exits. macOS's own crash report is still created.
