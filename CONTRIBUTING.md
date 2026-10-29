# Contributing

Thanks for helping. Palmo is a plain Swift package, so no Xcode project is needed.

## Setup

```sh
git clone <repo> && cd Palmo
swift build
swift test
scripts/build-app.sh          # signed build/Palmo.app
```

You need macOS 26 or later, Xcode 26 command-line tools and Swift 6.2+. Open the package in Xcode with
`open Package.swift` if you prefer.

## Ground rules

- **Swift 6 language mode with strict concurrency.** No `@preconcurrency` imports or `nonisolated(unsafe)`
  without a comment explaining the invariant.
- **Public APIs only.** No private frameworks and no `dlsym` tricks. Anything that would block a future App Store
  build goes in [docs/APP-STORE-BLOCKERS.md](docs/APP-STORE-BLOCKERS.md).
- **On-device only.** Do not add networking, analytics or third-party SDKs.
- **Keep the language model off the fast path.** Pointer, click, drag, scroll and volume must never await a model.
  Anything that uses the model must have a timeout and a rule-based fallback.
- **Doc comments** (`///`) on every public type and member in `PalmoCore`.
- **No TODOs or placeholders** in merged code. Open an issue instead.

## Tests

Tests use **Swift Testing** (`import Testing`) and live in `Tests/PalmoCoreTests`.

- **Recognition:** build hands with `HandFixture.pose(…)` or its shortcuts (`.openPalm()`, `.pinch()`, …).
  Drive time with `RecognizerDriver` (`hold`, `feed`, `arm`). Fixtures are deterministic, so no camera is needed.
- **Intent and routing:** use `MockSynthesizer` and `StubResolver` from `IntentRouterTests.swift`.
- **Foundation Models:** these tests run only where `SystemLanguageModel.default.isAvailable`. Assert on validity
  (one of the candidate actions), never on a specific model answer.

Every new gesture needs:

- a classifier or recognizer test for when it fires;
- at least one test for when it must *not* fire, such as a near miss, a disabled gesture or the cooldown.

## Commits and pull requests

- Keep commits small and focused, with imperative subjects ("Add volume dial detents").
- Update `CHANGELOG.md` under *Unreleased*.
- If you change a threshold, explain why in the PR and update GESTURES.md.
- Before opening a PR, `swift build`, `swift test` and `scripts/build-app.sh` must pass with no warnings.
