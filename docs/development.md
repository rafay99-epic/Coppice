# Development

## Prerequisites

- macOS 15 or later on Apple Silicon
- Full Xcode 16 or later. The Command Line Tools alone are not enough, because SwiftUI's macros ship with full Xcode.
- [Bun](https://bun.sh) 1.3.14 for the website and the monorepo scripts

## Monorepo

The repo uses Bun workspaces and [Turborepo](https://turborepo.com). From the repository root:

```sh
bun install              # once
bun run build            # build everything
bun run build:desktop    # just the macOS app
bun run build:website    # just the website
bun run dmg              # the app plus a DMG installer
bun run test             # swift test
```

## Desktop app

From `apps/desktop`:

```sh
swift build              # compile
swift test               # run the tests
./dev.sh                 # build and launch "Coppice Dev" next to your real app
./nightly.sh             # build and launch a local Nightly build
./make-dmg.sh            # package the installer
```

Coppice Dev has its own settings, log and icon, so it never touches your installed copy.

To see onboarding again in Coppice Dev:

```sh
defaults delete com.syntaxlabtechnology.coppice.dev hasCompletedOnboarding
```

Then quit and reopen the app.

### UI check

This read-only check inspects the running app through macOS Accessibility. It never clicks, activates or moves anything:

```sh
osascript -l JavaScript Scripts/ui-check.js
```

### Tests

The verdict tests create real git repositories in a temporary folder instead of using mocks, because the safety rules depend on what git actually reports. If you change a rule in `Services/WorktreeScanner.swift`, add a case to `Tests/CoppiceTests/VerdictTests.swift`.

## Website

From `apps/website`:

```sh
bun run dev              # local dev server
bun run build            # static export to out/
bun run test:e2e         # Playwright tests in headless Chrome
```

The end-to-end tests build the site and serve it on port 4390, so they never touch a dev server you already have open. To run the same tests against a running dev server, which also catches hydration warnings:

```sh
E2E_BASE_URL=http://localhost:3000 bun run test:e2e
```

## Code style

- There are no code comments. Names and small functions should explain the code.
- SwiftLint runs in `--strict` mode in CI, so warnings fail the build.
- The app is black and white only. Use the tokens in `Views/Theme.swift` (`Font.display`, `Font.ui`, `Space`, `.mono`, `.quiet`) instead of system fonts or colors.
