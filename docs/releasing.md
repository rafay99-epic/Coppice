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

The **Promote nightly to stable** workflow adds one commit to `main` whose files match `nightly` exactly, then starts the release build. It never merges, so it can't conflict. The commit lists every change since the previous promotion and records the promoted `nightly` commit in a `Promoted-from` trailer, which is where the next changelog starts.

1. On GitHub, open **Actions**, then **Promote nightly to stable**, then **Run workflow**.
2. Choose the **`main`** branch.
3. Untick **dry run**. It is ticked by default, and a dry run only prints the changelog without promoting anything.

From a terminal:

```sh
gh workflow run promotion.yml --ref main -f dry_run=false
```

The release notes come from the commit titles on `nightly`.

## Signing

Stable and Nightly DMGs are signed with the Syntax Labs **Developer ID Application** certificate (team `MGH5K382YN`), notarized by Apple and stapled in CI, so they open without a Gatekeeper warning. macOS ties permissions such as Full Disk Access to the signing team, so they survive every update.

The release jobs read five repository secrets, shared with Vitals:

| Secret | Value |
| --- | --- |
| `MACOS_SIGN_CERT_P12` | base64 of the Developer ID Application `.p12` |
| `MACOS_SIGN_CERT_PASSWORD` | its password |
| `APPLE_API_KEY_P8` | the App Store Connect API key (`.p8` contents) |
| `APPLE_API_KEY_ID` | its Key ID |
| `APPLE_API_ISSUER_ID` | its Issuer ID |

Without them a release fails instead of shipping an unsigned build. There is no ad-hoc fallback. Notarization usually takes a few minutes; the build waits up to two hours.

To build a signed, notarized DMG locally with the same keys (kept in `~/.vitals-signing`). It signs from a throwaway keychain, so it never stops on a keychain password prompt:

```sh
cd apps/desktop
./sign.sh            # Nightly
./sign.sh stable     # Stable
./sign.sh status     # recent notarizations
```

Plain `./build.sh` and `./dev.sh` sign with the same Developer ID from your keychain and fail if it is missing; there is no ad-hoc signing. PR CI packages with `UNSIGNED=1`, since PR jobs have no secrets, and that DMG never ships.
