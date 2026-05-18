# F22SimpleFlightModel: CI build failure on `Float*Float*float3` chain

## Summary

The CI workflow `.github/workflows/test_macOS.yml` started failing on `main`
with two Swift compiler errors at the same line in
`F22SimpleFlightModel.computeForce`:

```
Cannot convert value of type 'float3' (aka 'SIMD3<Float>')
to expected argument type 'Float'
```

The expression compiled cleanly locally with Xcode 26.5 / Swift 6.3.2 but
failed on the `macos-26` GitHub Actions runner (older Xcode 26.x). Root cause
is a Swift type-checker overload-resolution issue on a three-term `*` chain
mixing `Float` and `SIMD3<Float>`. Fix is a pure refactor: split the chain
into a scalar product followed by a scalar×vector multiply.

## Symptoms (verbatim from xcresult)

From `debugging/TestResults/TestResults_5_17_26_1.xcresult` (build-results):

```
errorCount: 3
- "Testing cancelled because the build failed."
- Swift Compiler Error: Cannot convert value of type 'float3'
  (aka 'SIMD3<Float>') to expected argument type 'Float'
  at F22SimpleFlightModel.swift line 52 col 73
- Swift Compiler Error: Cannot convert value of type 'float3'
  (aka 'SIMD3<Float>') to expected argument type 'Float'
  at F22SimpleFlightModel.swift line 52 col 88
```

Note: line 52 on the runner is line 53 locally — the diff between the runner
checkout and the local checkout is identical, the line number shift is just
how the diagnostic was rendered into the xcresult.

`testNodes` was empty: the build failed before any tests could be staged.

## Investigation steps

1. **Read the offending file.** Opened
   `ToyFlightSimulator Shared/Physics/FlightModel/Models/F22SimpleFlightModel.swift`
   and looked at the cited line:

    ```swift
    // F22SimpleFlightModel.swift:53
    let drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()
    ```

    Operand types:
    - `getDragCoefficient()` → `Float` (`F22SimpleFlightModel.swift:134-136`)
    - `liftData.liftVelocitySquared` → `Float` (stored on `LiftData`,
      computed as `dot(liftVelo, liftVelo)` in `calculateLiftData`)
    - `-worldVelocity.normalize()` → `float3` (`Float3+Extensions.swift:25-28`
      returns `float3`; unary `-` on SIMD returns SIMD)

   So the expression is `Float * Float * float3`.

2. **Confirmed the expression is well-typed in principle.** `SIMD3<Float>`
   has the standard `*` overloads (`SIMD×SIMD`, `Scalar×SIMD`, `SIMD×Scalar`),
   and `*` is left-associative, so `(Float * Float) * float3` reduces cleanly
   to `Float * float3 → float3`. No project-level operator overloads on `*`
   exist that could interfere (grep confirmed).

3. **Reproduced locally — and failed to reproduce.** Ran the project's
   documented Debug build command:

    ```bash
    xcodebuild build -project ToyFlightSimulator.xcodeproj \
        -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug ...
    ```

    Result: `** BUILD SUCCEEDED **`. Local toolchain: Xcode 26.5 / Swift
    6.3.2. Runner toolchain: whatever ships as default on `macos-26` (the
    workflow doesn't pin a version), reported as macOS 26.3 in the xcresult,
    almost certainly an Xcode 26.2/26.3 with the Swift 6.x compiler at a
    slightly earlier patch.

4. **Cross-checked the diagnostic columns.** The two error columns (73 and
   88 on the runner line) bracket the `-worldVelocity.normalize()` operand:

    ```
                                            ↓ col 73 (space after second *)
            let drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()
                                                                              ↑ col 88 (the '.' before normalize())
    ```

    Both diagnostics point into the vector operand and demand `Float`. The
    solver picked an overload chain where the trailing operand had to be a
    scalar.

5. **Concluded this is a type-checker overload-resolution regression.** With
   `*` overloaded ~4 ways for SIMD and a chain of three operators plus a
   unary `-` on the last operand, the older solver explores the wrong branch
   first and exhausts its solver budget on the conjunctive constraints
   rather than backtracking to the SIMD-trailing branch. Newer compilers
   handle this fine. Pure compiler-side issue, no logic bug.

## Root cause

Operator-overload resolution in `Float * Float * float3` chains is
ambiguous enough that older Swift 6.x type-checkers (as shipped with the
default Xcode on the `macos-26` runner image) fail to resolve it within the
solver's budget and emit a "expected `Float`" error on the trailing SIMD
operand. The newer Xcode 26.5 type-checker resolves it correctly. The
expression itself is valid Swift.

## Fix

Split the offending chain into two statements so each `*` has exactly one
unambiguous overload to bind. No behavior change — same operands, same
left-to-right associativity.

`ToyFlightSimulator Shared/Physics/FlightModel/Models/F22SimpleFlightModel.swift:53-54`:

```swift
// Before:
let drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()

// After:
let dragScale = getDragCoefficient() * liftData.liftVelocitySquared   // Float * Float → Float
let drag = dragScale * -worldVelocity.normalize()                      // Float * float3 → float3
```

Local `xcodebuild build` still passes (`** BUILD SUCCEEDED **`). The fix is
the minimum surface area needed to disambiguate; it does not introduce a
helper, comment, or named constant beyond `dragScale`, and matches the
existing style of the function (which already factors named intermediates
for `engineForce`, `liftData`, `inducedDrag`).

Committed as `1bd42ef` — "Flight-model: split Float\*Float\*float3 chain in
drag calc".

## Verification

1. Local: `xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme
   "ToyFlightSimulator macOS" -sdk macosx -configuration Debug ...` →
   `** BUILD SUCCEEDED **`.
2. CI: push to `main` and confirm `.github/workflows/test_macOS.yml` runs
   the full test suite to completion (not just the build) and the
   `TestResults.xcresult` artifact is no longer produced on failure.

## Follow-up worth considering (not done here)

The workflow uses `runs-on: macos-26` with no explicit Xcode pin. The
runner image's default Xcode can drift independently of the local
development environment, which is exactly the failure mode this incident
hit. Two options:

1. Pin Xcode in the workflow:

    ```yaml
    - uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '26.5'   # or whatever matches local dev
    ```

   Trade-off: requires the chosen version to actually be installed on the
   runner image — if it isn't, the step fails fast (which is still better
   than a silent overload-resolution drift). Worth checking
   [runner-images](https://github.com/actions/runner-images) for the
   currently-installed Xcodes on `macos-26`.

2. Keep the workflow version-agnostic but treat compiler-version-sensitive
   expressions (heavily-overloaded operator chains, especially with SIMD)
   as a code-smell to avoid in the first place — i.e., prefer the split
   form everywhere.

Option 1 is the durable fix; option 2 is the cheap habit.
