# Code Review — `flight_model` branch (composition refactor + force-based F-22)

**Branch:** `flight_model` vs `main`
**Date:** 2026-05-14
**Status:** Pass 1 issues mostly resolved; some residual concerns remain.

This document captures the original review of the `flight_model` branch, the
fixes applied in response, what's still outstanding, and the test coverage
added to guard against regressions.

---

## 1. Overview

The `flight_model` branch reworks the physics subsystem in two intertwined
ways:

1. **Composition over inheritance for physics.** The old
   `Collidable{Sphere,Plane,F22}` subclass tower is removed. Instead,
   `GameObject` now owns an optional `RigidBody`. Two concrete subclasses
   — `SphereRigidBody` and `PlaneRigidBody` — capture the shape-specific
   data (`collisionRadius`, `collisionNormal`) and AABB construction.
2. **Force-based flight for the F-22.** `PhysicsEntity` gains a `force`
   field. `EulerSolver` gets an `applyForces` step that integrates
   `F = m·a + g`. `F22.doUpdate` writes engine thrust and a simplified
   lift to `rigidBody.force` each frame; `Aircraft.doUpdate` continues
   to handle direct rotation and side-step input.

Both directions are correct in principle. The first review pass turned up
seven concrete bugs and a handful of style issues; almost all of those have
been addressed in the follow-up commit. The remainder of this document
walks through each finding.

---

## 2. Original Review — Findings + Resolution

### Pass 1 / 🔴 Bugs / Risks

#### O1 — Retain cycle: `GameObject` ⇄ `RigidBody`

**Files:** `RigidBody.swift:24`, `GameObject.swift:15`

`RigidBody` held a `let gameObject: GameObject` (strong), and its
initializer wrote `gameObject.rigidBody = self` (strong on the other
side). Neither side could ever deallocate. The TODO comment in the
original file acknowledged the risk and deferred it.

**Fix applied:** `gameObject` was changed to `weak let gameObject:
GameObject?`. Swift 6.3 (the project's current toolchain) accepts
`weak let` on class members (an older-Swift caveat noted in §4 below).
The accessor methods were updated to use optional chaining
(`self.gameObject?.setPosition(...)`) with sensible fallbacks
(`?? .zero`, `?? AABB(center: .zero, radius: .zero)`).

**Resolution:** ✅ Fixed. Verified by
`RigidBodyTests.noRetainCycleBetweenGameObjectAndRigidBody()`.

#### O2 — F-22 cannot fly forward in `FlightboxScene`

**Files:** `Aircraft.swift:53-67`, `F22.swift:44-77`, `FlightboxScene.swift:208-211, 233-235`

The original force-path in `Aircraft.doUpdate` removed the
`moveAlongVector(getFwdVector(), …)` call entirely — forward motion now
required physics integration of `force`. But `FlightboxScene` still has
`physicsWorld.setEntities(entities)` and `physicsWorld.update(deltaTime:)`
commented out, so the F-22 had no physics step and was stuck on the
ground.

**Fix applied:** The F-22-specific block was moved out of
`Aircraft.doUpdate` entirely (good — see O7) and into `F22.doUpdate`.
The new F-22 method branches on `if let rigidBody` — force path when a
rigid body is attached, kinematic fall-through to `super.doUpdate()`
when it isn't.

**Resolution:** 🟡 Partially fixed. The branch logic now exists, but
`FlightboxScene.swift:208` still constructs `SphereRigidBody(gameObject:
jet)` on the F-22 unconditionally, while the scene's physics world
remains commented out. With a rigid body attached, the F-22 takes the
force path, accumulates force into `rb.force`, but no integrator ever
consumes it — the jet still can't fly forward in `FlightboxScene`.

**Recommended:** either (a) uncomment `physicsWorld.setEntities(entities)`
and `physicsWorld.update(...)` in `FlightboxScene`, or (b) drop the
`SphereRigidBody` line so the F-22 falls back to the kinematic path in
that scene. (a) is more useful; (b) is a smaller change.

#### O3 — Force-cast cascade if a plain `RigidBody` is used

**File:** `PhysicsWorld.swift:112-167`

`PhysicsWorld.getCollisionData` and `collided` dispatch on
`collisionShape` and force-cast to `SphereRigidBody`/`PlaneRigidBody`.
`RigidBody`'s default `collisionShape` is `.Sphere`, so a developer
constructing a bare `RigidBody(gameObject:)` and adding it to the world
would hit `as! SphereRigidBody` and crash.

**Fix applied:** `RigidBody.init` was changed from default to `internal
init`. This blocks cross-module construction.

**Resolution:** 🟡 Partial. `internal init` does not prevent
construction of a base `RigidBody` from within the same module, which is
where all the call sites live. The risk is reduced (no external module
can hit it) but not eliminated.

**Optional follow-up:** make `RigidBody` formally abstract by trapping
in `init` (e.g., `fatalError("Use SphereRigidBody or PlaneRigidBody")`
in a designated initializer that subclasses bypass), or replace the
force-casts in `PhysicsWorld` with `guard let … as? …` and a graceful
no-op. Lower priority since current code paths only construct
`SphereRigidBody` and `PlaneRigidBody`.

#### O4 — `applyForces` ignores `shouldApplyGravity`

**File:** `EulerSolver.swift:31`

The original `applyForces` added `gravity` unconditionally:
```swift
let acceleration: float3 = entities[i].force / entities[i].mass + gravity
```
The Verlet solver, by contrast, gated gravity on
`if entities[i].shouldApplyGravity`. This meant the protocol field was
respected by one integrator and ignored by the other, and
`HeckerCollisionResponse` (which writes `shouldApplyGravity = false`
after a sphere/plane resting contact) silently lost effect under Euler.

**Fix applied:**
```swift
let appliedGravity: float3 = entities[i].shouldApplyGravity ? gravity : .zero
let acceleration: float3 = entities[i].force / entities[i].mass + appliedGravity
```
Also added the same gate to the legacy `applyGravity` helper.

**Resolution:** ✅ Fixed. Verified by
`EulerSolverTests.applyForcesRespectsShouldApplyGravity()` and
`PhysicsWorldSmokeTests.eulerHonoursShouldApplyGravity()`.

#### O5 — Lift formula uses world-space Z, not forward airspeed

**File:** `F22.swift:49-51`

The original lift formula was:
```swift
let lift: float3 = getUpVector() * (self.rigidBody?.velocity.z ?? 1.0) * 100.0
```
World-`z` is only "forward speed" when the F-22 is in its starting
orientation. As soon as it turns, the lift magnitude tracks an
unrelated axis. The fallback to `1.0` also produced phantom lift when
the rigid body was nil.

**Fix applied:** the magnitude term now uses
`max(0, dot(rigidBody.velocity, getFwdVector())) * 100` — correctly
projecting velocity onto the aircraft's forward axis.

**Resolution:** 🟡 Partially fixed. The magnitude is correct now, but
the lift *vector* is still `[0, lift, 0]` (world up), not
`getUpVector() * lift` (aircraft up). After rolling, lift will still
push the aircraft toward world-up rather than perpendicular to the
wings — a hot-air-balloon-with-thrust model rather than an aircraft.

**Recommended:** `let liftVector = getUpVector() * lift` (or
`rigidBody.gameObject.getUpVector() * lift` for consistency with the
new direction-of-flight projection).

#### O6 — Force was assigned, not accumulated

**File:** `Aircraft.swift:58` (original)

The original `self.rigidBody?.force = engineForce + lift` overwrote any
other force already applied this frame. Not a bug today (nothing else
writes), but the next change to add drag/recoil/gear-thump would
silently break.

**Fix applied:**
- `F22.doUpdate` now uses `self.rigidBody?.force += engineForce + liftVector`.
- A new `PhysicsSolver.zeroForces` extension method was added; both
  `EulerSolver.step` and `VerletSolver.step` call it at the end of each
  step. Forces are therefore the responsibility of the *producer* (game
  code), and the solver clears them between frames.
- `PhysicsEntity` gained a `zeroForce()` extension method to back this.

**Resolution:** ✅ Fixed. Verified by
`PhysicsWorldSmokeTests.forceIsZeroedEveryFrame()`,
`EulerSolverTests.stepClearsForceAfterIntegration()`, and
`EulerSolverTests.consecutiveStepsDoNotDoubleIntegrate()`.

#### O7 — F-22 force logic lived in `Aircraft` base class

**File:** `Aircraft.swift:53` (original)

`if let ac = self as? F22 { … }` in the base class is the exact LSP
violation the composition refactor is trying to clean up elsewhere.

**Fix applied:** the force-path block was moved into `F22.doUpdate`.
`Aircraft.doUpdate` is back to a single uniform kinematic path.

**Resolution:** ✅ Fixed.

### Pass 1 / 🟡 Minor / Style

- ✅ Stale TODOs removed from `PhysicsEntity.swift` and `RigidBody.swift`.
- ✅ `reset()` renamed to `resetCollisions()` (better name, paired with
  new `zeroForce()` extension).
- 🟡 Commented-out `applyGravity` call in `EulerSolver.step` is still
  there; `applyGravity` itself is still defined but unreachable. Either
  delete the helper or restore the call path under a flag.
- 🟡 `print` calls in `EulerSolver.resolveCollisions` (lines 62-65,
  80-81, 95, 108-109) are still present, still per-frame. Not
  introduced by this PR, but applyForces now routes through the same
  loop body every frame.

---

## 3. New Findings (Pass 2)

Surface area was small, so this pass is short.

### N1 — Spammy log inside Verlet hot loop

**File:** `VerletSolver.swift:28`

```swift
if entities[i].shouldApplyGravity {
    newAcc += Self.applyForces(gravity: gravity)
} else {
    print("[VerletSolver step] Entity \(entities[i].id) not applying gravity")
}
```

This fires every frame for every entity with gravity disabled — for
the F-22 sitting on the ground under Hecker-Verlet contact response,
that's 60 prints/sec. Should be gated behind a debug flag (or just
deleted; the case is normal, not exceptional).

### N2 — Mixed access style in `F22.doUpdate`

**File:** `F22.swift:44-52`

```swift
if let rigidBody {
    …
    let lift = max(0, dot(rigidBody.velocity, getFwdVector())) * 100.0
    …
    self.rigidBody?.force += engineForce + liftVector
}
```

Half the block uses the unwrapped `rigidBody` local, half uses
`self.rigidBody?.` optional chaining inside an `if let` that already
unwrapped it. Functionally fine (it's the same class instance) but
inconsistent — use the unwrapped local throughout.

### N3 — `F22.doUpdate` force-branch bypasses base-class side effects

**File:** `F22.swift:44-64`

The new branch structure:
```swift
override func doUpdate() {
    if let rigidBody {
        // …force/rotation/side-step code…
    } else {
        super.doUpdate()
    }
    // afterburner logic
}
```

`Aircraft.doUpdate` does two things besides the kinematic motion:
- Toggles landing gear on `.ToggleGear` (debounced).
- Calls `animator?.update(deltaTime:)` every frame.

In the force-path branch neither of those runs — the F-22 loses its
ability to retract/extend gear and stops advancing its animator state
whenever it has a rigid body attached. Easy fix: extract the
gear-toggle + `animator?.update` calls into a private helper on
`Aircraft` that both `Aircraft.doUpdate` and `F22.doUpdate`'s
force-branch can call, or move those two lines into the F-22 branch
unchanged.

### N4 — `weak let` portability

**File:** `RigidBody.swift:23`

`weak let gameObject: GameObject?` compiles cleanly on the current
Swift 6.3 toolchain (verified locally). It would not have compiled on
Swift 5.x. If this codebase ever targets older Xcode (e.g., a CI runner
pinned below Xcode 26.2), the build will break. Worth a one-line
comment, or change to `weak var`.

### N5 — `RigidBody` init still missing access checks

**File:** `RigidBody.swift:25`

`internal init` is the right direction but, as covered in O3, doesn't
fully prevent base-class instantiation. Lower priority since all
in-tree call sites construct subclasses.

---

## 4. Tests Added

All under `ToyFlightSimulatorTests/Physics/`, written in Swift Testing
(matching the project's newer suite style). The test target uses
`PBXFileSystemSynchronizedRootGroup`, so the new files were
auto-discovered — no `project.pbxproj` edits required. A `.physics`
`Tag` was added to `TestSupport/TestTags.swift`.

### `RigidBodyTests.swift` — 7 tests

Covers the composition refactor, retain-cycle fix, and weak-back-pointer
fallbacks.

| Test | What it checks |
| --- | --- |
| `sphereRigidBodyRegistersBackReference` | `SphereRigidBody.init` writes `self` into `gameObject.rigidBody`, shape/radius defaults correct |
| `planeRigidBodyRegistersBackReference` | Same, for `PlaneRigidBody`, plus collision normal |
| `positionPassThrough` | `setPosition` / `getPosition` round-trip through the attached `GameObject` |
| `sphereAABBMatchesPositionAndRadius` | `SphereRigidBody.getAABB` uses GameObject position + own radius |
| `noRetainCycleBetweenGameObjectAndRigidBody` | After releasing the only outer strong refs, both objects deallocate (catches the original O1 bug) |
| `rigidBodyToleratesNilGameObject` | After GameObject deallocates, RigidBody methods don't crash and return fallback values |
| `f22RigidBodyDidSetAppliesAircraftDefaults` | `F22.rigidBody.didSet` stamps `mass=30, restitution=0.1` when a rigid body is attached |

### `PhysicsSolverTests.swift` — 8 tests, two suites

Uses a lightweight `PhysicsEntityStub` final class that conforms to
`PhysicsEntity` without needing `Engine.Device` or model loading —
keeps these tests pure-Swift and fast.

`EulerSolverTests`:
- `applyForcesIntegratesForceAndGravity` — `a = F/m + g`, integrated into velocity
- `applyForcesSkipsStaticBodies` — static bodies never accelerate
- `applyForcesRespectsShouldApplyGravity` — gates O4 fix
- `zeroForcesClearsAllForces` — clears even static bodies
- `stepClearsForceAfterIntegration` — full-step semantics (O6)
- `consecutiveStepsDoNotDoubleIntegrate` — no force re-application across frames

`VerletSolverTests`:
- `stepClearsForceAfterIntegration` — Verlet path also clears force
- `staticBodiesDoNotFall` — static bodies are stationary under gravity

### `PhysicsWorldSmokeTests.swift` — 4 tests

End-to-end through `PhysicsWorld`. These use real `Sphere`/`Quad`
GameObjects (and so depend on `Engine.Device` being available — same
constraint as `RendererTests`).

- `sphereFallsTowardPlane_Verlet` — sphere starts at y=20, falls under
  gravity, makes contact with the static ground plane within 1 second.
- `staticPlaneDoesNotMove` — ground plane stays put under collisions.
- `forceIsZeroedEveryFrame` — applies a one-frame upward impulse,
  verifies the velocity gained doesn't grow on subsequent frames (the
  failure mode O6 would re-introduce).
- `eulerHonoursShouldApplyGravity` — body with
  `shouldApplyGravity=false` stays at its starting altitude for 60
  steps.

### Verified

All 19 new tests pass under
`xcodebuild test -only-testing:…` against the current `flight_model`
branch. Existing test suites still pass.

---

## 5. Recommended Follow-up

Roughly in priority order:

1. **(High) Resolve O2.** `FlightboxScene` has a rigid body on the
   F-22 but no physics integrator. Either turn physics on in that
   scene or skip the rigid body — pick one.
2. **(High) Resolve N3.** F-22 force-path bypasses gear toggle +
   animator updates. Easy to miss in QA because the symptoms are
   feature-gated (no animation jitter to spot).
3. **(Medium) Resolve O5 fully.** Lift along `getUpVector()`, not
   world-Y. Without this, the flight model produces visibly wrong
   behavior under any roll input.
4. **(Medium) Resolve N1.** Drop the per-frame `print` in
   `VerletSolver.step`.
5. **(Low) Resolve O3 fully.** Make `RigidBody` formally abstract or
   guard the force-casts in `PhysicsWorld`.
6. **(Low) Cleanup.** Delete unused `applyGravity` helper in
   `EulerSolver.swift` if the call site is staying commented out.
   Style-pass `F22.doUpdate` for the optional-chaining inconsistency
   (N2).

---

## 6. Files Changed (this review pass)

```
ToyFlightSimulator Shared/GameObjects/Aircraft.swift
ToyFlightSimulator Shared/GameObjects/F22.swift
ToyFlightSimulator Shared/Physics/Solver/EulerSolver.swift
ToyFlightSimulator Shared/Physics/Solver/PhysicsSolver.swift
ToyFlightSimulator Shared/Physics/Solver/VerletSolver.swift
ToyFlightSimulator Shared/Physics/World/PhysicsEntity.swift
ToyFlightSimulator Shared/Physics/World/PhysicsWorld.swift
ToyFlightSimulator Shared/Physics/World/RigidBody.swift
ToyFlightSimulatorTests/TestSupport/TestTags.swift           (added .physics)
ToyFlightSimulatorTests/Physics/RigidBodyTests.swift          (new)
ToyFlightSimulatorTests/Physics/PhysicsSolverTests.swift      (new)
ToyFlightSimulatorTests/Physics/PhysicsWorldSmokeTests.swift  (new)
code_reviews/claude/flight_model_review_2026-05-14.md         (this file)
```
