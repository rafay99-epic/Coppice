# Releasing

## Channels

Each channel installs as a separate app, with its own icon, settings and log:

| Channel | Install | Built from | Updates from |
| --- | --- | --- | --- |
| **Stable** | `brew install --cask rafay99-epic/apps/coppice` | `main` | the latest release |
| **Nightly** | `brew install --cask rafay99-epic/apps/coppice-nightly` | `nightly` | the newest pre-release |
| **Dev** | `./dev.sh` | any branch | never |

## Branches

- **`nightly` is where work lands.** Open pull requests against `nightly`. Every merge publishes a Nightly pre-release.
- **`main` is Stable.** It only changes through the promotion workflow. Every push to `main` publishes a full release.

## Versions

A version is `0.<number of commits on the branch>`. It goes up by itself with every merge, and there is nothing to bump by hand. Nightly builds also carry a CI build number.

## Promoting Nightly to Stable

The **Promote nightly to stable** workflow squashes everything on `nightly` into one commit on `main`, then starts the release build.

1. On GitHub, open **Actions**, then **Promote nightly to stable**, then **Run workflow**.
2. Choose the **`main`** branch.
3. Untick **dry run**. It is ticked by default, and a dry run only prints the changelog without promoting anything.

From a terminal:

```sh
gh workflow run promotion.yml --ref main -f dry_run=false
```

The release notes come from the commit titles on `nightly`.

## Signing

Releases are signed with a stable self-signed certificate instead of an ad-hoc signature. macOS ties permissions such as Full Disk Access to the signature, so with an ad-hoc signature every update would look like a new app and lose those permissions.
