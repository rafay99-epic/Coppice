# Contributing

Thanks for helping. A few rules keep things simple:

1. **Branch from `nightly`**, using a name like `feat/…`, `fix/…` or `chore/…`, and open your pull request **against `nightly`**. The default branch is `main`, so switch the base when you open it.
2. **Use conventional commit titles**, for example `fix(desktop): sweep skips tracked dist folders`.
3. **Run it locally** with `./dev.sh`, which installs Coppice Dev next to your real app.
4. **Keep CI green.** Every pull request runs `swift test`, SwiftLint in strict mode and a packaged build.
5. **If you change a safety rule, add a test for it** in `apps/desktop/Tests/CoppiceTests/VerdictTests.swift`.

See [Development](docs/development.md) for setup and [Releasing](docs/releasing.md) for how changes reach Stable.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
