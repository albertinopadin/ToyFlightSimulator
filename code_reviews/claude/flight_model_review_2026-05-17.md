# Code Review — `flight_model` (commits `1ce0543` & `645a73e`)

**Branch:** `flight_model`
**Range reviewed:** `1ce0543` (FlightModel extract + mass-sync fix) → `645a73e` (commented-code cleanup) — current HEAD
**Date:** 2026-05-17
**Status:** Substantive refactor is well-shaped and matches the research-doc plan. A few correctness footguns (debug-log flip, force-unwraps, brittle mass-sync) should land before merge; the rest is polish.

---

## 1. What changed

Two commits, one substantive + one cleanup:

| Commit | Summary |
|---|---|
| `1ce0543` | Extract `FlightModel` protocol + `F22SimpleFlightModel` from `F22.swift`; add `RigidBody.State` snapshot; mirror mass-sync didSets on both `Aircraft.flightModel` and `F22.rigidBody`; flip `DEBUG_FORCES` / `DEBUG_LIFT` on while validating |
| `645a73e` | Delete a residual commented-out single-arg `applyPlayerAttitudeInput(deltaTurn:)` in `Aircraft.swift` |

Net diff: **+1098 / −163** across 11 files (most of which is two new docs totalling ~830 LOC under `debugging/` and `investigations/`; the Swift change is ~270 lines net).

**New types** under `ToyFlightSimulator Shared/Physics/FlightModel/`:

- `FlightModel.swift` — protocol: `mass: Float` + `computeForce(state:input:) -> float3`
- `ControlInput.swift` — `(throttle, pitch, roll, yaw)` value struct
- `LiftData.swift` — moved out of `F22.swift`
- `Models/F22SimpleFlightModel.swift` — concrete implementation; owns thrust/lift/induced-drag math and the curves they evaluate

**Other touched code**:

- `Aircraft.swift` — adds `flightModel: FlightModel?` with mass-sync `didSet`; rewrites `doUpdate` to build a `ControlInput`, ask the flight model for a force, and apply it to `rigidBody.force`; adds a fallback path (`moveAlongVector`) when either `rigidBody` or `flightModel` is missing; threads `controlInput` through `applyPlayerAttitudeInput`.
- `F22.swift` — gutted: aero math, curves, constants, and `applyForces`/helpers all moved out. F22 now only carries identity, afterburner objects, scene-graph init, ground clamp, and a `rigidBody.didSet` that mirrors mass-sync + sets restitution.
- `RigidBody.swift` — adds public `struct State` (mass, velocity, acceleration, worldForward, worldRight, rotationMatrix) and `getState()` snapshot accessor.
- `FlightboxWithPhysics.swift` — constructs `F22SimpleFlightModel` and assigns it to `jet.flightModel`.
- `Preferences.swift` — flips `DEBUG_FORCES` and `DEBUG_LIFT` to `true`.

The refactor cleanly matches the canonical Unity `AircraftPhysics` / Unreal `MovementComponent` pattern described in the new `investigations/claude/rigid-body-force-application-patterns.md` — sibling component, value-type state snapshot, normalized control input. No ECS rewrite, no scene-graph disruption.

The commit message on `1ce0543` is, as with `b094014` before it, exemplary: it explains the architectural choice, the mass-sync bug it bundles in, the symptoms (terminal velocity ≈ 22 m/s, NaN within ~7 frames), and the Fix-3 follow-up plan.

---

## 2. Findings

Sorted by severity. 🔴 should land before merging; 🟡 is recommended polish; 🟢 is FYI / nice-to-have.

Letter prefix is `R` (refactor) to avoid colliding with `F1–F15` from `flight_model_review_2026-05-16.md`.

---

### 🔴 R1 — `DEBUG_FORCES` and `DEBUG_LIFT` flipped to `true` in `Preferences.swift`

**File:** `ToyFlightSimulator Shared/Core/Preferences.swift:49-50`

```swift
public let DEBUG_FORCES:        Bool = true  // F22.applyForces summary per frame
public let DEBUG_LIFT:          Bool = true  // F22.calculateLiftData per frame
```

The commit message acknowledges this:

> DEBUG_FORCES / DEBUG_LIFT left enabled in Preferences.swift while
> the new flight model is being validated in play; flip back to false
> on a follow-up commit once satisfied.

This is exactly the F2 finding from the 2026-05-16 review re-introduced — two multi-line `print()` calls per F-22 per `UpdateThread` step. `DebugLog` uses an `@autoclosure` so the string is only built when the flag is true, but with the flag *true* this is identical to a raw `print`, and `UpdateThread` calls `doUpdate` at full physics rate.

**Suggested fix:** flip to `false` as the commit message promises, in a follow-up commit, before the branch merges. The flag plumbing is already correct — only the constants need flipping.

Bonus: the per-flag comments still reference `F22.applyForces` / `F22.calculateLiftData`, which no longer exist (the functions live on `F22SimpleFlightModel.computeForce` / `calculateLiftData` now). Update the comments to track the rename.

---

### 🔴 R2 — Three `gameObject!` force-unwraps in `RigidBody.getState()`

**File:** `ToyFlightSimulator Shared/Physics/World/RigidBody.swift:73-80`

```swift
func getState() -> RigidBody.State {
    return RigidBody.State(mass: self.mass,
                           velocity: self.velocity,
                           acceleration: self.acceleration,
                           worldForward: self.gameObject!.getFwdVector(),
                           worldRight: self.gameObject!.getRightVector(),
                           rotationMatrix: self.gameObject!.getRotationMatrix())
}
```

`gameObject` is declared `weak let gameObject: GameObject?` (line 33), so it can be `nil` if the GameObject is deallocated. Three back-to-back force-unwraps will crash hard if that ever happens.

In the current call path (`Aircraft.doUpdate` → `rigidBody.getState()`), the GameObject is *necessarily* alive — `doUpdate` is the GameObject's own method, so `self` exists and `self.rigidBody?.gameObject === self`. So no crash today. But the rest of the file is careful about this: `setPosition`, `getPosition`, and `getAABB` all use `self.gameObject?` with `??` defaults.

The force-unwraps are inconsistent with the rest of the file's idiom and a footgun if `getState` is ever called from somewhere else (e.g., a deferred force application, an unowned solver thread, a snapshot taken before scene teardown).

**Suggested fix:** either match the file's existing idiom (guard let or `??` defaults), or — cleaner — change `getState()` to return `RigidBody.State?` and have `Aircraft.doUpdate` do `guard let state = rigidBody.getState() else { return }`. Tradeoff: nullable return is more honest about the dependency but adds one unwrap at every call site (currently one, so cheap).

---

### 🔴 R3 — Mass-sync via mirrored `didSet`s is fragile across subclasses

**Files:**
- `ToyFlightSimulator Shared/GameObjects/Aircraft.swift:47-53`
- `ToyFlightSimulator Shared/GameObjects/F22.swift:20-30`

The pattern:

```swift
// Aircraft.swift
var flightModel: FlightModel? {
    didSet {
        if let flightModel {
            rigidBody?.mass = flightModel.mass
        }
    }
}

// F22.swift
override var rigidBody: RigidBody? {
    didSet {
        rigidBody?.restitution = 0.1
        if let flightModel {
            rigidBody?.mass = flightModel.mass
        }
    }
}
```

The fix is correct — mass converges to `flightModel.mass` regardless of which property is assigned first. The Fix-3 doc comment in `Aircraft.swift` is a thorough acknowledgment of the technical debt. So as a hotfix, this is fine.

**The fragility:** the mass-sync clause in `F22.rigidBody.didSet` is per-subclass convention, not enforced by `Aircraft`. The next aircraft subclass that overrides `rigidBody.didSet` (to set its own `restitution`, or hook into a custom collision shape) will silently lose mass-sync unless the dev remembers to copy the four-line `if let flightModel { ... }` clause. The default `RigidBody.init` mass is `1`, so the failure mode is exactly the one this commit fixes: thrust-on-mass = 31_751 / 1 → instant NaN runaway within a few frames.

**Suggested fix (without doing Fix 3):** move the `rigidBody.didSet` override into `Aircraft` itself, so the mass-sync is inherited by every aircraft subclass. `F22.rigidBody.didSet` then collapses to just `rigidBody?.restitution = 0.1`, but it would need to invoke the parent observer — Swift fires both parent and child `didSet` automatically when the property is overridden (storage stays in `GameObject`), so this works:

```swift
// Aircraft.swift
override var rigidBody: RigidBody? {
    didSet {
        if let flightModel {
            rigidBody?.mass = flightModel.mass
        }
    }
}

// F22.swift
override var rigidBody: RigidBody? {
    didSet {                              // Aircraft.didSet still fires
        rigidBody?.restitution = 0.1     // F22-specific tweak
    }
}
```

Cleaner: one source of truth for mass-sync, subclasses only do their own thing. Real Fix-3 (computed `RigidBody.mass` backed by `MassSource`) can come later.

---

### 🔴 R4 — Commented-out `projectOnPlaneGoog` migrated forward unresolved

**File:** `ToyFlightSimulator Shared/Physics/FlightModel/Models/F22SimpleFlightModel.swift:79-87`

```swift
// Alternative implementation kept here for reference. Mathematically
// equivalent to projectOnPlane above but requires a sqrt via normalize().
// The form above avoids the sqrt by using dot(n, n) directly:
//
//     private func projectOnPlaneGoog(vector: float3, planeNormal: float3) -> float3 {
//         let normal = planeNormal.normalize()
//         let dotProduct = dot(vector, normal)
//         return vector - (normal * dotProduct)
//     }
```

This is F4 from the 2026-05-16 review. That review suggested deleting it ("delete `projectOnPlaneGoog`. If the alternative implementation is worth preserving as documentation, move it to a comment block or a markdown note alongside the dot-vs-cross doc"). The refactor moved it from `F22.swift` to the new file (and added some clarifying preamble) but didn't resolve the underlying objection — commented-out code in production source bit-rots.

**Suggested fix:** delete the comment block. The active `projectOnPlane` directly above already speaks for the chosen implementation (no sqrt). If the sqrt-based form is worth keeping as a teaching artifact, move it to `investigations/claude/dot-vs-cross-product.md`.

---

### 🟡 R5 — `RigidBody.State.mass` and `.acceleration` are unused by any flight model

**File:** `ToyFlightSimulator Shared/Physics/World/RigidBody.swift:11-19`

```swift
public struct State {
    let mass: Float
    let velocity: float3
    let acceleration: float3
    let worldForward: float3
    let worldRight: float3
    let rotationMatrix: matrix_float4x4
}
```

`F22SimpleFlightModel.computeForce` reads `state.velocity`, `state.worldForward`, `state.worldRight`, `state.rotationMatrix` — but never `state.mass` or `state.acceleration`. The flight model already has its own `mass: Float = 30_000`, and acceleration is integrator state that the flight model shouldn't generally read (it's downstream of forces).

YAGNI: drop both until a flight model actually needs them. If/when a model wants mass-aware logic (e.g., specific thrust = thrust/mass to budget control authority), it can ask via `state.mass` at that point.

Counter-argument: `RigidBody.State` is a snapshot intended for any future flight model, so over-providing the snapshot is cheap (six floats + a 4x4 matrix). Reasonable to leave for forward compatibility — but then at least document the intent ("snapshot of kinematic + pose state; not all fields are required by every flight model").

---

### 🟡 R6 — Visibility inconsistency across the new FlightModel module

**Files:**
- `Physics/FlightModel/FlightModel.swift` — `protocol FlightModel` (internal)
- `Physics/FlightModel/ControlInput.swift` — `struct ControlInput` (internal)
- `Physics/FlightModel/LiftData.swift` — `struct LiftData` (internal)
- `Physics/FlightModel/Models/F22SimpleFlightModel.swift` — `public final class F22SimpleFlightModel` (public)

`F22SimpleFlightModel` is the only one with an explicit `public`. Its conformance to `FlightModel` (internal protocol) means it can never be useful outside this module — the protocol is unreachable, so the public class can't be referenced through it from outside. The `public` doesn't buy anything.

Inversely, `RigidBody` *is* `public class RigidBody: PhysicsEntity`, but `RigidBody.State` is implicitly internal — which means an external module can hold a `RigidBody` reference but can't read the snapshot type returned by `getState()`.

**Suggested fix:** pick one tier. If the whole module is app-internal (which it appears to be — no Swift Package boundaries), drop `public` everywhere for consistency. If there's a future external consumer in mind, raise the protocol and the state type to `public` as well so the surface is coherent.

---

### 🟡 R7 — `LiftData.worldVelocity` is redundant with caller-scope data

**File:** `ToyFlightSimulator Shared/Physics/FlightModel/Models/F22SimpleFlightModel.swift:40-54, 102-106, 125-128`

```swift
return LiftData(worldVelocity: worldVelocity,        // ← passed in, returned back
                liftForceVector: liftForceVector,
                liftVelocityVector: liftVelo,
                liftVelocitySquared: v2,
                liftCoefficient: liftCoefficient)
```

`worldVelocity` is parameter into `calculateLiftData`, stored on `LiftData`, and then read back out via `liftData.worldVelocity` in `calculateInducedDrag` → `getInducedDragCoefficient` — but the only caller (`computeForce`) already has `worldVelocity` in scope, having just passed it in.

The round-trip serves no purpose. Either:
1. Drop `LiftData.worldVelocity` and have `calculateInducedDrag` take `worldVelocity` as a parameter alongside `worldForward`.
2. Or pass `worldVelocity` once at the top of `computeForce` and let downstream helpers read from local scope.

Either way, `LiftData` shrinks to four fields that are genuinely *outputs* of the lift calculation, which makes the type's role clearer.

---

### 🟡 R8 — `Aircraft.doUpdate` builds `ControlInput` unconditionally

**File:** `ToyFlightSimulator Shared/GameObjects/Aircraft.swift:84-106`

```swift
override func doUpdate() {
    super.doUpdate()

    let controlInput = getControlInput()
    let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
    let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
    
    if shouldUpdateOnPlayerInput && hasFocus {
        // ... uses controlInput, deltaTurn, deltaMove
    }

    animator?.update(deltaTime: Float(GameTime.DeltaTime))
}
```

For aircraft constructed with `shouldUpdateOnPlayerInput: false` (the wingmen / static F-16s in `FlightboxScene`, `FlightboxWithPhysics`, `FlightboxWithTerrain`, plus the F18 path that wraps `super.doUpdate()` in its own `shouldUpdateOnPlayerInput` check), all three locals are computed and discarded each frame.

Tiny cost (`ControlInput` is 16 bytes, four `InputManager.ContinuousCommand` reads, two float multiplies) and the four wingmen × 60 Hz isn't measurable. But it's a free move:

```swift
override func doUpdate() {
    super.doUpdate()
    
    if shouldUpdateOnPlayerInput && hasFocus {
        let controlInput = getControlInput()
        let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
        let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
        // ... same body
    }

    animator?.update(deltaTime: Float(GameTime.DeltaTime))
}
```

Same shape, no unused work.

---

### 🟡 R9 — `F22.doUpdate` ground-clamp condition allows climbing through y=0

**File:** `ToyFlightSimulator Shared/GameObjects/F22.swift:54-59`

```swift
if getPositionY() < 0 {
    setPositionY(0.0)
    if let rigidBody, rigidBody.velocity.y < 0 {
        rigidBody.velocity.y = 0
    }
}
```

The fix from `flight_model_review_2026-05-16.md` (F9, "zeroing downward velocity") landed correctly. One small edge: if the aircraft is *climbing* (upward `velocity.y > 0`) but currently below y=0 due to an integrator step landing slightly negative, the position is clamped to 0 but the upward velocity is preserved — fine. If the aircraft is *descending* below 0 and the clamp pins it to 0 with `velocity.y = 0`, the next frame the gravity integration will push `velocity.y` negative again, so the clamp pins again, and again — this is the standard "infinitely-bouncing-on-the-floor at zero velocity" pattern. Not catastrophic (the aircraft just sits at y=0 without sinking), but it's the marker that this is a placeholder for actual contact resolution.

Already TODO'd in the file. Worth re-flagging that the proper fix is to land a ground collision/restitution path through `PhysicsWorld`, not to bandaid the clamp further.

---

### 🟢 R10 — `// TODO:` in `FlightModel.swift` would be more useful as a `///` doc comment

**File:** `ToyFlightSimulator Shared/Physics/FlightModel/FlightModel.swift:11-12`

```swift
protocol FlightModel {
    var mass: Float { get }
    
    // TODO: This just computes the force at the rigid body center, need to implement torque at later time:
    func computeForce(state: RigidBody.State, input: ControlInput) -> float3
}
```

Promoting to a doc comment makes the limitation visible in autocomplete / quick-help for callers, not just for someone who opens the file:

```swift
/// Compute the net world-frame force to apply at the rigid body's center
/// for this physics step. Does not currently return torque — attitude is
/// still kinematic (see `Aircraft.applyPlayerAttitudeInput`). When torque
/// arrives, this signature will change or a sibling method will be added.
func computeForce(state: RigidBody.State, input: ControlInput) -> float3
```

---

### 🟢 R11 — Architectural: thrust is force, attitude is still kinematic

**File:** `ToyFlightSimulator Shared/GameObjects/Aircraft.swift:91-103`

```swift
if shouldUpdateOnPlayerInput && hasFocus {
    if let rigidBody, let flightModel {
        let rigidBodyState = rigidBody.getState()
        let force = flightModel.computeForce(state: rigidBodyState, input: controlInput)
        rigidBody.force += force
    } else {
        moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
    }
    
    applyPlayerAttitudeInput(deltaTurn: deltaTurn, controlInput: controlInput)
    applyPlayerSideMove(deltaMove: deltaMove)
    handleGearToggle()
}
```

Engine thrust + lift + drag now flow through `rigidBody.force` → physics integrator → updated position. Good.

But `applyPlayerAttitudeInput` still calls `rotateX/Y/Z` directly on the node (kinematic rotation, no torque, no inertia), and `applyPlayerSideMove` still calls `moveAlongVector` directly (kinematic translation). So the aircraft has a hybrid model: force-integrated forward motion, but pose changes that snap instantly per frame.

Behaviorally this matches what F22 had before the refactor (same hybrid), so the refactor isn't a regression. But two flight artifacts likely come from this and will need addressing:

1. **No rotational inertia / control-stick feel** — full deflection produces an instant rotation rate, not a torque that ramps into rotation. The F-22 in particular has very high pitch authority but should still take ~0.5s to roll 90°. The current model rolls in 1/60s.
2. **Lift direction can lag the aircraft body** — `liftData` is computed from `state.worldRight` (snapshot at start of step), but then the aircraft is rotated by `applyPlayerAttitudeInput` *after* `computeForce` has used the snapshot. Next frame's lift then aligns to the new body — a one-frame lag. At 60 Hz it's invisible; at lower update rates or higher rotation rates it could become a divergent oscillation.

The `// TODO:` in `FlightModel.swift` notes the torque gap. Worth thinking about whether the right next step is:
- (a) Move attitude into the flight model as `computeForceAndTorque` returning `(float3, float3)` and let the rigid body integrate angular velocity from torque.
- (b) Keep attitude kinematic but provide damped first-order response (instant `controlInput` → exponential ramp on `rotateX/Y/Z` rate). Cheaper than (a), gives most of the feel.

Not for this commit. Marker for the next one.

---

### 🟢 R12 — `let mass: Float = 30_000` satisfies the protocol but visibility is implicit

**File:** `ToyFlightSimulator Shared/Physics/FlightModel/Models/F22SimpleFlightModel.swift:9`

```swift
public final class F22SimpleFlightModel: FlightModel {
    let mass: Float = 30_000  // 30,000 kg, ~66,000 lbs
```

The `FlightModel.mass: Float { get }` requirement is internal. `F22SimpleFlightModel` is `public` (see R6). The stored `let mass` has no explicit modifier, so it inherits internal-by-default for class members — which matches the protocol but mismatches the class. Swift accepts this because the protocol is internal too.

If R6 is taken (drop the `public`), this naturally resolves. If `public` stays, the stored property should also be `public` for consistency with the class's public surface.

---

### 🟢 R13 — Debugging doc location

**File:** `debugging/claude/flight_model_refactor_mass_mismatch.md`

The doc is a thorough post-mortem of a bug that was fixed in the same commit that wrote the doc. It belongs in `investigations/` (a record of work done) more than `debugging/` (an in-progress diagnosis). The other docs in `investigations/claude/` follow this pattern — `material_color_bleeding_bug.md` is the analogous case there.

Mechanical, harmless either way. Mentioned because the naming distinction (debugging = open, investigations = closed) is worth keeping deliberate.

---

## 3. Things the diff got right

Worth recording so they don't get lost in the noise above.

- **Sibling-component shape matches the research-doc plan.** The new `FlightModel` protocol + `F22SimpleFlightModel` impl + `Aircraft.flightModel` property is a faithful realization of the Unity `AircraftPhysics` / Unreal `MovementComponent` pattern that the research write-up landed on. No premature ECS rewrite, no scene-graph contortions — the existing `Aircraft : GameObject : Node` hierarchy stays intact.
- **`RigidBody.State` as a value snapshot is the right shape.** Passing a struct snapshot instead of a reference to the rigid body prevents the flight model from mutating physics state mid-step, and makes `computeForce` trivially testable (build a `RigidBody.State` literal, pass a `ControlInput`, assert on the returned vector). The mass / acceleration / pose fields are over-provisioned (R5) but the principle is sound.
- **Throttle is now parameterized.** `F22SimpleFlightModel.computeForce` reads `input.throttle` instead of querying `InputManager.ContinuousCommand(.MoveFwd)` directly. The flight model no longer depends on `InputManager`, which means it can be unit-tested in isolation and reused by autopilot / AI / replay code that synthesizes its own `ControlInput`. Same goes for the rest of the channels.
- **`SymmetricSigmoidCurve` rename addresses F15 from the prior review.** "AeroCurve" was overpromising generality; "SymmetricSigmoidCurve" honestly describes the shape.
- **Lift coefficient curve gained post-stall keyframes.** The new `(input: 90, output: 0.4)` and `(input: 120, output: 0.0)` keys give the curve a proper drop-off past the stall AoA, instead of the previous extrapolation past 30° behaving as a runaway linear ramp.
- **`throttlePower: 10.0` as a named constant.** The previous `* 10.0` magic in `F22.applyForces` is now an explicit `let throttlePower: Float = 10.0`. Clearer intent, single place to tune.
- **`645a73e` does what it says on the tin.** Deletes a stale commented-out method that referenced no-longer-existent helpers. Tiny commit, exactly the right scope.
- **The Fix-3 doc comment on `Aircraft.flightModel` is a model for capturing tech debt in-line.** Names the problem, explains why the current fix is a hotfix not a solution, sketches the long-term shape (`MassSource`), explains why that shape isn't being built yet (need to design for non-aircraft bodies first), and points at the debugging doc. Exactly the right amount of context for a future reader who hits the comment cold.

---

## 4. Suggested merge plan

If landing this incrementally rather than as one branch merge:

1. **Pre-merge cleanup commit:** R1 (flip `DEBUG_FORCES` / `DEBUG_LIFT` back to `false`, fix the stale comment references to `F22.applyForces`) and R4 (delete the commented `projectOnPlaneGoog` block). ~5 minutes.
2. **Pre-merge robustness commit:** R2 (replace the three `gameObject!` force-unwraps in `RigidBody.getState()` with the file's existing `?` / `??` idiom) and R3 (move `rigidBody.didSet` mass-sync up to `Aircraft` so subclasses inherit it). ~15 minutes — also touches `F22.swift`.
3. **Then merge.** The substantive refactor is good and should ship.

R5–R13 are polish that can land in a follow-up — none block correctness or stability.

---

## 5. Out of scope for this review

- **Physics correctness of the values** — `mass = 30_000`, `engineMaxThrust = 31_751`, `throttlePower = 10.0`, the lift coefficient keyframes. The 2026-05-16 review noted these are a calibration target rather than a wind-tunnel match; that judgment stands. The new post-stall keyframes are physically plausible but not validated against F-22 data.
- **The research and debugging docs** (`investigations/claude/rigid-body-force-application-patterns.md`, `debugging/claude/flight_model_refactor_mass_mismatch.md`). Both read as thorough self-contained work products; no review notes.
- **Anything in the `flight_model` parent commits** (`e02b284` and earlier) — already covered in `flight_model_review_2026-05-14.md`, `flight_model_simplify_2026-05-15.md`, and `flight_model_review_2026-05-16.md`.
