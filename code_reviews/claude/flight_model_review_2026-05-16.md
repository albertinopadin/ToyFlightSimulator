# Code Review — `flight_model` (commits `45f1cd1..e02b284`)

**Branch:** `flight_model`
**Range reviewed:** `45f1cd1` (last simplify pass) → `e02b284` (HEAD)
**Date:** 2026-05-16
**Status:** Substantively correct — the physics fixes are well-targeted and the math is sound. A handful of debug leftovers, dead code, and missing test coverage should be cleaned up before this branch is considered done.

---

## 1. What changed

Six commits, all centered on getting the in-progress F-22 flight model to a stable flying state:

| Commit | Summary |
|---|---|
| `0be27e8` | Add `projectOnPlane` helper to F22 |
| `1f3873f` | Add `AeroCurve` (sine sigmoid) and `ValueCurve` (cubic Hermite) utilities |
| `36fc8e3` | Add `Float3+Extensions` with **zero-safe** `normalize()` and `magnitude` |
| `b094014` | Big one: world-frame lift/drag, realistic mass/thrust/gravity, NaN cleanup, flight-model scaffolding in `F22` |
| `9675484` | Make induced-drag direction and coefficient input rotation-invariant |
| `e02b284` | Add `investigations/claude/dot-vs-cross-product.md` reference doc |

Net diff: **+437 / −26** across 11 files.

The work resolves a multi-day debugging session and lands four interconnected frame-related bugs (lift direction, induced-drag direction, induced-drag coefficient input, parasitic-drag direction) plus a NaN cascade root cause. The commit messages — particularly `b094014` — are exemplary; the "why this lands atomically" footer is worth keeping as a reference for future physics work.

---

## 2. Findings

Sorted by severity. Items marked 🔴 should land before merging; 🟡 is recommended polish; 🟢 is FYI / nice-to-have.

---

### 🔴 F1 — Debug `print()` in `Node.rotationMatrix` setter fires every frame

**File:** `ToyFlightSimulator Shared/GameObjects/Node.swift:51`

**Before:**
```swift
set {
    _rotationMatrix = newValue
}
```

**After:**
```swift
set {
    print("Node \(self._name) got new rotation matrix value: \(newValue)")
    _rotationMatrix = newValue
}
```

The `b094014` commit message acknowledges this:
> Left in from debugging the NaN cascade and useful as a tripwire if any future code bypasses the rotate / setRotation methods. Can be removed once the flight model stabilizes.

**Concern:** every direct write to `rotationMatrix` (including by `Node.rotate` and `setRotationMatrix` internally) logs to stdout. At 60–120 Hz across every aircraft and physics object this becomes a meaningful I/O cost and floods the console. Tripwires are valuable, but they should be behind `#if DEBUG_NAN_TRIPWIRE` (or similar) rather than always-on.

**Suggested fix:**
```swift
set {
    #if DEBUG_FLIGHT_MODEL
    print("Node \(_name) rotationMatrix ←", newValue)
    #endif
    _rotationMatrix = newValue
}
```
Or just drop it now that the cascade is understood and `Float3.normalize()` is zero-safe at the source.

---

### 🔴 F2 — Debug `print()` in `F22.applyForces` and `F22.calculateLiftData`

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:120, 167`

```swift
// applyForces:
print("[applyForces]\n  engine force: \(engineForce)\n  lift vector: \(liftData.liftForceVector)\n  induced drag + drag: \(inducedDrag + drag)")

// calculateLiftData:
print("[calculateLiftData] \n  world velocity: \(worldVelocity)\n  lv2: \(v2)\n  lift coeff: \(liftCoefficient)")
```

Same category as F1 — useful during development, unacceptable at game runtime. The `UpdateThread` calls `doUpdate` per physics step, so each frame produces two multi-line console writes per F-22 in the scene.

**Suggested fix:** gate behind a `Preferences.LogFlightModel` flag, or remove now that the model is stable.

---

### 🔴 F3 — Commented-out dead code blocks in `F22.swift` and `EulerSolver.swift`

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:94-105`

```swift
//    private func applyForces(rigidBody: RigidBody) {
//        let fwd = getFwdVector()
//        let velocity = rigidBody.velocity
//        let fwdVelocity = max(0, dot(velocity, fwd))
//        let fwdVeloSq = pow(fwdVelocity, 2)
//        let angleOfAttack: Float = 2.0  // Constant for now; in degrees
//        let engineForce = fwd * engineThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
//        let lift = fwdVeloSq * getLiftCoefficient(aoa: angleOfAttack) * liftPower
//        let liftForceVector = getUpVector() * lift
//        let dragForceVector = fwdVeloSq * getDragCoefficient() * -fwd
//        rigidBody.force += engineForce + liftForceVector + dragForceVector
//    }
```

This refers to `engineThrust` (removed) and would no longer compile. It's strictly dead.

**File:** `ToyFlightSimulator Shared/Physics/Solver/EulerSolver.swift:125-128`

**After:**
```swift
//                let entityPos: float3 = [entities[i].getPosition().x + entities[i].velocity.x * deltaTime,
//                                         entities[i].getPosition().y + entities[i].velocity.y * deltaTime,
//                                         entities[i].getPosition().z + entities[i].velocity.z * deltaTime]
                let entityPos: float3 = entities[i].getPosition() + entities[i].velocity * deltaTime
```

**Suggested fix:** delete both blocks. Git keeps the history; commented-out alternatives bit-rot and obscure intent.

---

### 🔴 F4 — Two definitions of `projectOnPlane` in `F22.swift`

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:142-153`

```swift
private func projectOnPlane(vector: float3, planeNormal: float3) -> float3 {
    let sqMag = dot(planeNormal, planeNormal)
    guard sqMag > .ulpOfOne else { return vector }
    return vector - (dot(vector, planeNormal) / sqMag) * planeNormal
}

// Google's alternative implementation:
private func projectOnPlaneGoog(vector: float3, planeNormal: float3) -> float3 {
    let normal = planeNormal.normalize()
    let dotProduct = dot(vector, normal)
    return vector - (normal * dotProduct)
}
```

`projectOnPlaneGoog` is unreferenced. Both implementations are mathematically equivalent for non-degenerate normals — the first avoids an `sqrt` (cheaper, and already what the rest of the code uses).

**Suggested fix:** delete `projectOnPlaneGoog`. If the alternative implementation is worth preserving as documentation, move it to a comment block or a markdown note alongside the dot-vs-cross doc.

---

### 🔴 F5 — `AeroCurve` and `ValueCurve` have no test coverage

**Files:**
- `ToyFlightSimulator Shared/Utils/AeroCurve.swift` (new, 40 LOC)
- `ToyFlightSimulator Shared/Utils/ValueCurve.swift` (new, 172 LOC)

Both are pure value types with no dependencies beyond Foundation/simd, no I/O, and well-defined mathematical contracts — ideal unit-test candidates. The project already has a Swift Testing target with `Utils/` and `Math/` suites (`TFSCacheTests`, `MathUtilsTests`, etc.), and the file-level comment block in `ValueCurve.swift` even claims testable properties:

> - `linear()` is exact: with chord-slope tangents on both ends of each segment, the Hermite expression algebraically reduces to (1-u)*p0 + u*p1.
> - `smooth()` for 2 points == `linear()` for 2 points. For 3+ points it produces a continuously differentiable curve.

None of these are verified. Recommended minimum test set:

```swift
// AeroCurveTests
- evaluate at minInput returns minOutput              (clamp low)
- evaluate at maxInput returns maxOutput              (clamp high)
- evaluate at zeroInput returns zeroOutput            (centerpoint)
- monotonic across [minInput, maxInput] when outputs are monotonic
- precondition fires when min.input >= zero.input

// ValueCurveTests
- single-key curve returns that key's output for all inputs
- two-key linear == lerp at midpoint
- linear() equals piecewise-linear interpolation at arbitrary inputs
- smooth() == linear() for n=2
- evaluate clamps below first key / above last key
- precondition fires on non-monotonic input
- precondition fires on empty keys
```

**Suggested fix:** add `AeroCurveTests.swift` and `ValueCurveTests.swift` under `ToyFlightSimulatorTests/Utils/`. Should be ~50 lines each.

---

### 🔴 F6 — Verify new Utils files are in Xcode project membership

**Files:** `Utils/Float3+Extensions.swift`, `Utils/AeroCurve.swift`, `Utils/ValueCurve.swift`

The `1f3873f` commit message explicitly warns:

> Xcode project membership not updated in this commit — files need to be added to the macOS / iOS / tvOS targets in the project navigator before they will compile into the app.

`b094014` clearly relies on these (the F22 references `ValueCurve.smooth` and `AeroCurve` directly), so either membership was added in a follow-up working-tree change that isn't isolated to its own commit, or the build is currently broken on a clean checkout of `e02b284`. Worth confirming with a clean clone + `xcodebuild build` before merging.

---

### 🟡 F7 — Comment unit mismatch: thrust is "kgf", not "kg"

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:25`

```swift
let engineMaxThrust: Float = 31_751  // 31,751 kg,  70,000 lbs of thrust
```

Kilograms is a unit of *mass*; thrust is a *force*. The intended unit is **kilogram-force (kgf)**, which equals ~9.81 N. The number is correct (31,751 kgf ≈ 311 kN ≈ 70,000 lbf), only the label is wrong. The b094014 commit message gets this right ("31_751 kgf").

**Suggested fix:**
```swift
let engineMaxThrust: Float = 31_751  // kgf — ~70,000 lbf, real F-22 afterburning thrust
```

This is more than a pedantic correction: when the `* 10.0` multiplier in `applyForces` eventually moves out into a proper unit conversion (kgf → N is exactly ×9.80665), getting the labels straight makes that translation correct rather than a fudge.

---

### 🟡 F8 — `liftPower` is both a stored property and a parameter

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:26, 113-116, 158`

```swift
let liftPower: Float = 50.0
// ...
let liftData = calculateLiftData(angleOfAttack: pitchAOA,
                                 worldVelocity: worldVelocity,
                                 planeNormal: getRightVector(),
                                 liftPower: liftPower)         // ← passed in
// ...
private func calculateLiftData(angleOfAttack: Float,
                               worldVelocity: float3,
                               planeNormal: float3,
                               liftPower: Float) -> LiftData {  // ← parameter
```

`calculateLiftData` is a private member of `F22` and could read `self.liftPower` directly. The parameter form makes the signature longer without adding flexibility (no caller varies it).

**Suggested fix:** drop the parameter and read `self.liftPower` inside the helper. Same goes for `inducedDragPower` if it's eventually plumbed through.

---

### 🟡 F9 — Ground-clamp hack should leave a TODO marker on the file

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:62-65`

```swift
override func doUpdate() {
    // Hack so jet doesn't go thru ground:
    if getPositionY() < 0 {
        setPositionY(0.0)
    }
    // ...
```

The fix is intentional and called out in `b094014` ("Temporary; proper collision response with the ground plane should replace this once the flight model settles"). The in-file comment is informal; an explicit `// TODO:` would surface it in Xcode's TODO navigator and any project-wide TODO sweeps.

**Suggested fix:**
```swift
// TODO(flight-model): replace with proper ground-plane collision response (see commit b094014)
if getPositionY() < 0 {
    setPositionY(0.0)
    rigidBody?.velocity.y = max(0, rigidBody?.velocity.y ?? 0)  // also kill downward velocity
}
```
Note the velocity clamp: without it, every frame the position resets but downward velocity keeps accumulating, so the next frame's position becomes more negative than the last and the clamp pins harder and harder. Likely not visible at the current parameters but a latent bug.

---

### 🟡 F10 — `yawAOA` is computed and discarded

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:112, 132-140`

```swift
let (pitchAOA, _) = calculateAnglesOfAttack(localVelocity: localVelo)
// ...
private func calculateAnglesOfAttack(localVelocity: float3) -> (pitchAngleOfAttack: Float, yawAngleOfAttack: Float) {
    if localVelocity.magnitude < 0.1 {
        return (0, 0)
    }
    let pitchAOA = atan2(-localVelocity.y, localVelocity.z).toDegrees
    let yawAOA = atan2(localVelocity.x, localVelocity.z).toDegrees
    return (pitchAOA, yawAOA)
}
```

Computing `yawAOA` only to discard it isn't expensive (one `atan2`), but it's a tell that the helper's signature anticipates use that doesn't exist yet. The `b094014` commit message confirms this:

> yawAOA is still computed and thrown away — when sideslip gets modeled, it'll need its own curve.

**Suggested fix:** either drop `yawAOA` from the return tuple until sideslip is modeled (smaller surface area), or leave it but add a `// FIXME: wire sideslip drag curve` comment so the discard reads as deliberate.

---

### 🟢 F11 — `Float3.up` / `.right` aliases risk confusion with body-frame vectors

**File:** `ToyFlightSimulator Shared/Utils/Float3+Extensions.swift:9-10`

```swift
extension float3 {
    static let up = Y_AXIS
    static let right = X_AXIS
    // ...
```

These are **world-frame** axis constants, but in the rest of the codebase "up" and "right" usually mean the **body-frame** vectors returned by `Node.getUpVector()` / `getRightVector()`. A future reader writing `float3.up` thinking they're getting "the aircraft's up vector" will silently get the world Y axis instead.

The flight model itself already conflates these in the (correct, deliberate) `planeNormal: getRightVector()` call vs the (also correct) world-frame `worldVelocity` — so the namespace ambiguity is a real risk in this exact code path.

**Suggested fix:** rename to `worldUp` / `worldRight`, or just drop the aliases — `Y_AXIS` / `X_AXIS` read fine at the call site and avoid the trap entirely.

---

### 🟢 F12 — `Float3+Extensions.swift` recomputes `magnitude` in `normalize()`

**File:** `ToyFlightSimulator Shared/Utils/Float3+Extensions.swift:17-20`

```swift
func normalize() -> float3 {
    let m = magnitude
    return m > 0 ? self / magnitude : .zero  // ← reads `magnitude` twice
}
```

The local `m` is computed but only used in the guard; the division uses `self / magnitude`, which recomputes the sqrt. Tiny ALU win, but trivial to fix:

```swift
func normalize() -> float3 {
    let m = magnitude
    return m > 0 ? self / m : .zero
}
```

---

### 🟢 F13 — `inducedDragCurve` shape is inverted from physical induced drag

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:33`

```swift
let inducedDragCurve = AeroCurve(min: (-1, 0), zero: (0, 0), max: (360, 1))  // 700 knots, 360 m/s
```

Physical induced drag at fixed `Cl` is `D_i = ½·ρ·v²·S·Cd_i` where `Cd_i = Cl²/(π·AR·e)` — so it scales as `v²·Cl²`, which `calculateInducedDrag` already encodes via `liftVelocitySquared * dragForce` (with `dragForce = Cl²`). Multiplying further by a curve that ramps **up** with airspeed double-counts the v-dependence and over-penalizes high-speed flight.

For fixed *lift* (not fixed Cl) it's the opposite: induced drag ∝ `1/v²`, dominating at low speeds, vanishing at high. Either physical interpretation produces a *decreasing* function of airspeed, not increasing.

That said: this is a tuning artifact in an evolving flight model and may be deliberate for stability (suppress induced drag at low speeds where the curve evaluation is most noisy). Flagging because the next person looking at this curve will want context — either a comment explaining the choice, or a fix to the curve shape.

**Suggested action:** drop a comment explaining the rationale, e.g.:
```swift
// Curve ramps 0→1 over airspeed 0..360 m/s as a stability fudge — suppresses
// induced drag at low speeds where Cl² is most noisy. Not physical.
let inducedDragCurve = AeroCurve(min: (-1, 0), zero: (0, 0), max: (360, 1))
```

---

### 🟢 F14 — `Float3+Extensions` doesn't `import simd` or `Foundation`

**File:** `ToyFlightSimulator Shared/Utils/Float3+Extensions.swift`

The file uses `float3`, `sqrt`, and `/` on SIMD types but has no imports. It compiles because some other file in the build transitively imports them (probably via the project umbrella). Adding `import simd` (and `import Foundation` if `sqrt` is needed from there) makes the file self-contained.

Compare to `AeroCurve.swift` and `ValueCurve.swift`, both of which `import Foundation`.

---

### 🟢 F15 — `AeroCurve` name overpromises generality

**File:** `ToyFlightSimulator Shared/Utils/AeroCurve.swift`

The struct is specifically a three-point sine-shaped sigmoid. The name "AeroCurve" suggests something broader (a general aero-coefficient curve), but it's structurally narrower than `ValueCurve` and only fits sigmoid-shaped responses. If you add another aero curve shape later (e.g., a parabola for `Cm-vs-α`, or a polynomial for `Cd-vs-Mach`), the name collides.

**Suggested fix:** consider `SineSigmoid3pt`, `SymmetricSigmoidCurve`, or just keep the name and add a one-liner clarifying its scope:
```swift
/// Sine-shaped sigmoid with a single zero-crossing — useful for symmetric
/// aero responses (Cl-vs-α before stall, Cm-vs-α). For arbitrary keyframe
/// curves, use ValueCurve instead.
```

---

## 3. Things the diff got right (worth keeping in mind for future work)

These aren't actionable, but the review wouldn't be honest without them:

- **The `b094014` commit message is excellent.** Diagnoses both bugs from first principles, explains why each fix is correct in the relevant frame, calls out known remaining issues, and justifies the atomic landing. It would be a useful template for future physics-bug commits.
- **Zero-safe `normalize()` is the right primitive.** The NaN-cascade walkthrough in `36fc8e3` is a textbook example of why returning `.zero` from a degenerate normalize is preferable to returning NaN — the cascade through `setPosition → updateModelMatrix → 0 * NaN = NaN`, contaminating not just translation but the entire model matrix, is exactly the kind of failure mode that justifies the safety guard.
- **Removing the duplicate `float3` extension from `HeckerCollisionResponse.swift` was overdue.** Two definitions of `magnitude`/`normalize` shadowing each other based on import order is a class of bug that takes hours to find. Glad it was cleaned up while in this area of the code.
- **Returning `(Quad, PlaneRigidBody)` from `addGround` (from the previous commit `45f1cd1`) plus bumping the default scale to `1_000_000` in this range** is a small, correct call — the collision plane is mathematically infinite, so only the visual was clipping, and it should match the flight envelope.
- **The `EulerSolver` cleanups** (`+=` and SIMD position update) are mechanical wins. Same behavior, fewer characters.

---

## 4. Suggested merge plan

If you want to land this incrementally rather than as one branch merge:

1. **Pre-merge cleanup commit:** address F1, F2, F3, F4 (debug `print`s and dead code). ~10 minutes.
2. **Pre-merge test commit:** address F5 (AeroCurve / ValueCurve tests). ~30 minutes.
3. **Verification:** address F6 by doing a clean clone + `xcodebuild build` to confirm Xcode project membership is correct on a fresh checkout.
4. **Then merge.** The substantive physics work is good and should ship.

Items F7–F15 are polish that can land in a follow-up — none block correctness or stability.

---

## 5. Out of scope for this review

- Physics correctness beyond surface dimensional analysis (e.g., whether the actual Cl curve matches F-22 wind-tunnel data, whether `liftPower = 50` correctly encodes `½·ρ·S` for the chosen wing area). The `b094014` commit message documents the reasoning; treating this as a calibration target for in-game tuning rather than a wind-tunnel match is the right call for a toy simulator.
- The `investigations/claude/dot-vs-cross-product.md` reference doc — it's well-written and self-contained, no review notes.
- Anything in the `45f1cd1` parent (already covered in `flight_model_simplify_2026-05-15.md`).
