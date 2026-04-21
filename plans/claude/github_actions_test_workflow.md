# Plan: GitHub Actions test workflow

## Context

The repo has two build workflows today:

- `.github/workflows/macOS.yml` — builds `ToyFlightSimulator macOS` on push to `main`. Tests are commented out.
- `.github/workflows/swift6StrictConcurrency_macOS.yml` — builds with `SWIFT_STRICT_CONCURRENCY=complete` on push to the `swift6` branch.

We just added 35+ Swift Testing tests (commit `0bd85d0` — `MathTests`, `TransformTests`, `MathUtilsTests`, `TFSCacheTests`, `LockTests`, `MDLMaterialSemanticTests`, `TimeItTests`) alongside the existing `NodeTests`/`RendererTests`. They need to run on every push to `main`.

Scope: add a separate **test workflow** (not folding tests into the existing build workflow) and swap the Swift 6 strict-concurrency badge on line 3 of `README.md` for the new test badge. The `swift6StrictConcurrency_macOS.yml` file itself stays on disk — only its README badge is replaced.

User pre-emptively handled two side fixes in their working tree: upgraded `actions/checkout@v3` → `@v5` in both existing workflows, and corrected the `SWIFT_STRICT_CONCURRENCY=complete` typo in `macOS.yml`. Those diffs are out of scope for this change.

## Design decisions

- **Runner**: `macos-26` (default Xcode 26.2 supports Swift Testing — no `setup-xcode` action needed).
- **Trigger**: `push` to `main`, matching the existing `macOS.yml` pattern.
- **Single `xcodebuild test` invocation** rather than split build/test — simpler, no sharding needed.
- **`xcbeautify --renderer github-actions`** for clean console output and inline `::error::` annotations. Pre-installed on `macos-26`.
- **`-resultBundlePath TestResults.xcresult`** + **upload on failure** so `.xcresult` bundles are downloadable from the Actions UI to debug in Xcode. Skipped on success to avoid artifact noise.
- **`actions/checkout@v5`** (current stable).
- **No caching**: no SPM deps; build is small.
- **No code-signing**: `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` — matches existing build workflow.

## Files to create / modify

### New: `.github/workflows/test_macOS.yml`

```yaml
name: ToyFlightSimulator macOS Tests > main

on:
  push:
    branches: [main]

jobs:
  test:
    name: Test macOS App ToyFlightSimulator
    runs-on: macos-26
    steps:
      - name: Check out code
        uses: actions/checkout@v5

      - name: Verify Xcode version
        run: xcodebuild -version

      - name: Verify Swift version
        run: swift --version

      - name: Run tests
        run: |
          set -o pipefail
          xcodebuild test \
            -project ToyFlightSimulator.xcodeproj \
            -scheme "ToyFlightSimulator macOS" \
            -sdk macosx \
            -configuration Debug \
            -resultBundlePath TestResults.xcresult \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify --renderer github-actions

      - name: Upload xcresult on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: TestResults.xcresult
          path: TestResults.xcresult
```

### Modify: `README.md` line 3

Replace:

```markdown
[![ToyFlightSimulator macOS Build (with complete strict concurrency checking) > swift6](https://github.com/albertinopadin/ToyFlightSimulator/actions/workflows/swift6StrictConcurrency_macOS.yml/badge.svg)](https://github.com/albertinopadin/ToyFlightSimulator/actions/workflows/swift6StrictConcurrency_macOS.yml)
```

With:

```markdown
[![ToyFlightSimulator macOS Tests > main](https://github.com/albertinopadin/ToyFlightSimulator/actions/workflows/test_macOS.yml/badge.svg)](https://github.com/albertinopadin/ToyFlightSimulator/actions/workflows/test_macOS.yml)
```

Line 1 (build badge) and everything from line 5 onward stay unchanged.

## Critical files

- New file: `.github/workflows/test_macOS.yml`
- Modify: `README.md` (line 3 only)
- Reference (untouched): `.github/workflows/macOS.yml`, `.github/workflows/swift6StrictConcurrency_macOS.yml`

## Verification

1. Commit + push to `main` → new workflow appears under the **Actions** tab on GitHub.
2. Workflow runs `xcodebuild test` and all 42 tests (16 existing XCTest + 26 new Swift Testing) pass.
3. README badges render correctly on github.com with live status.
4. If a test fails in the future, the xcresult artifact is downloadable from the failed run's summary page.

## Out of scope (flagged for later)

- Adding `pull_request` triggers to the test workflow.
- Converting `.xcresult` to JUnit XML for aggregated dashboards.
