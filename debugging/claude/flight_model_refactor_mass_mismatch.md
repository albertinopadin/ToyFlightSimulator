# Flight-Model Refactor: Mass Mismatch After didSet Reorder

## Summary

Both reported symptoms — the F-22 falling more slowly than before, and NaNs appearing in the force calculation as soon as W is pressed — have a **single root cause**: after the Option-C refactor, `rigidBody.mass` is being set to `10.0` (the fallback) instead of `30_000` (the F-22 mass). The bug is a property-initialization-ordering issue in `F22.swift` combined with the new scene code in `FlightboxWithPhysics.swift`.

The aerodynamic math is fine. The integrator is fine. The mass on the rigid body is wrong by a factor of 3,000.

## Symptoms (verbatim)

1. *"F22 does not fall with gravity as fast as it used to"*
2. *"As soon as I press W to add throttle, I get NaNs in my force calculations"*

## Root cause: didSet fires before `flightModel` is assigned

### The didSet

`ToyFlightSimulator Shared/GameObjects/F22.swift:20-25`:

```swift
override var rigidBody: RigidBody? {
    didSet {
        rigidBody?.restitution = 0.1
        rigidBody?.mass = if let flightModel { flightModel.mass } else { 10.0 }
    }
}
```

This reads `self.flightModel` at the moment the rigid body is assigned. If `flightModel` is nil at that instant, mass becomes **10.0**, not 30,000.

### Where the rigid body gets assigned

`RigidBody.init` (`Physics/World/RigidBody.swift:35-59`) ends with:

```swift
gameObject.rigidBody = self   // line 48
```

That assignment goes through F22's overridden `rigidBody` property, which triggers the `didSet`.

### Scene construction order

`Scenes/FlightboxWithPhysics.swift:21-24`:

```swift
let jet = F22(scale: 0.25)                              // 1. F22 created; flightModel = nil
let jetRigidBody = SphereRigidBody(gameObject: jet)     // 2. didSet runs HERE → mass = 10.0
let flightModel = F22SimpleFlightModel()                // 3. flight model created (too late)
jet.flightModel = flightModel                           // 4. assigned, but didSet does NOT re-fire
```

Steps 1 → 2: F22's `flightModel` is still `nil` when `SphereRigidBody.init` runs, so the `didSet` hits the `else` branch and writes `10.0`.

Steps 3 → 4: assigning `flightModel` does not re-trigger `rigidBody?.didSet` (didSet only fires when `rigidBody` is mutated, not when `flightModel` changes). The mass stays at 10.0 forever.

### Resulting state at runtime

| field                   | value     | source                                |
|-------------------------|-----------|---------------------------------------|
| `rigidBody.mass`        | `10.0`    | F22.didSet else-branch                |
| `flightModel.mass`      | `30_000`  | `F22SimpleFlightModel.mass`           |

`F22SimpleFlightModel.computeForce` computes forces parameterized for a 30,000 kg aircraft (`engineMaxThrust = 31_751`, `throttlePower = 10.0`, `liftPower = 50.0`), but `EulerSolver` divides those forces by `rigidBody.mass = 10`. Every acceleration is **3,000× too large.**

## How that single bug produces Symptom 1 ("falls more slowly")

Gravity itself is unaffected — `EulerSolver.applyForces` (`Physics/Solver/EulerSolver.swift:20`) adds gravity as an **acceleration**, not a force:

```swift
let acceleration: float3 = entities[i].force / entities[i].mass + appliedGravity
```

So mass alone doesn't change `g`. But **drag** becomes catastrophically strong when mass is small:

Once the aircraft has any downward velocity, the lift-coefficient curve in `F22SimpleFlightModel` returns a meaningful Cl for the resulting AoA. Let's trace what happens at a steady fall of `v_y = -22 m/s`, planeNormal = right axis `(1, 0, 0)`, aircraft level:

- `liftVelo = projectOnPlane((0, -22, 0), (1,0,0)) = (0, -22, 0)`
- `v² = 484`
- `localVelo = (0, -22, 0)` (identity rotation)
- `pitchAOA = atan2(-(-22), 0).toDegrees = 90°`
- `liftCoeff = curve.evaluate(at: 90) = 0.4`
- The parasitic-drag term:
  ```swift
  drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()
       = 0.2 * 484 * (0, +1, 0)
       = (0, 96.8, 0)        // points UP, opposing gravity
  ```
- Upward acceleration from drag (mass = 10): `96.8 / 10 = 9.68 m/s²`
- Net downward acceleration: `9.81 - 9.68 ≈ 0.13 m/s²`

That's **terminal velocity at ~22 m/s** — the F-22 caps out at a glacial fall rate. With the correct mass of 30,000, the same drag would produce only `96.8 / 30_000 = 0.0032 m/s²` opposing gravity, so terminal velocity wouldn't be reached until ~1,213 m/s — effectively unobservable on the timescales of normal play. That's why it "used to fall faster": it really did, because the drag term was negligible relative to its 30,000 kg of inertia.

There is also a sideways component you may notice: at the same `v = (0, -22, 0)`:

```swift
liftDirection = cross((0, -1, 0), (1, 0, 0)) = (0, 0, 1)
liftForceVector = (0, 0, 0.4 * 484 * 50) = (0, 0, 9_680)
```

With mass = 10, that's 968 m/s² sideways (in +z, the aircraft's forward axis). Even before the user presses any input, the falling F-22 should be accelerating *forward* very fast. (Whether you've observed this depends on which axis the camera is watching.)

## How that single bug produces Symptom 2 (NaN on W press)

Once W is held, things diverge to infinity within ~7 frames at 60 fps (≈120 ms — "as soon as I press W").

Force from `F22SimpleFlightModel.computeForce:41`:

```swift
let engineForce = state.worldForward * engineMaxThrust * input.throttle * throttlePower
//              = forward * 31_751 * 1.0 * 10.0
//              = forward * 317_510                    // N
```

Translated to acceleration with the *wrong* mass: `317_510 / 10 = 31_751 m/s²`.

Frame-by-frame velocity evolution (assuming dt = 1/60 ≈ 0.016 s, identity orientation, forward = +z), tracking the dominant component:

| frame | dominant velocity component                 | reason                                       |
|-------|---------------------------------------------|----------------------------------------------|
| 1     | `v_z ≈ 508 m/s`                             | thrust / mass × dt                           |
| 2     | `v_y ≈ 6 × 10³`                             | lift = v² · Cl · liftPower / mass            |
| 3     | `v_y ≈ 3 × 10⁵`                             | runaway: lift grows with v²                  |
| 4     | `v_y ≈ 1 × 10⁹`                             |                                              |
| 5     | `v_y ≈ 1 × 10¹⁶`                            |                                              |
| 6     | `v_y ≈ 1 × 10³⁰`                            |                                              |
| 7     | `v² overflows Float (max 3.4 × 10³⁸) → ±Inf` |                                              |
| 8     | `Inf.normalize() = Inf / Inf = NaN`         | division-of-infinities is NaN, not zero      |

The zero-safe `Float3.normalize()` (`Utils/Float3+Extensions.swift:25-28`):

```swift
func normalize() -> float3 {
    let m = magnitude
    return m > 0 ? self / m : .zero
}
```

protects against the `m == 0` case (which is why `applyForces` is currently stable at exact rest). It does **not** protect against `m == Inf` — once velocity overflows, `Inf > 0` is true, so the function returns `Inf/Inf = NaN`, and NaN propagates into `cross()`, `liftForceVector`, and back into `rigidBody.force` and `rigidBody.velocity`.

The user sees NaN in the `DebugLog("[computeForce]...")` output at line 51 of `F22SimpleFlightModel.swift`.

### Why this didn't happen pre-refactor

Pre-refactor, the OLD `F22.swift` had:

```swift
let mass: Float = 30_000
…
override var rigidBody: RigidBody? {
    didSet {
        rigidBody?.restitution = 0.1
        rigidBody?.mass = self.mass     // stored property, always 30_000
    }
}
```

`self.mass` was an F22 stored property that always existed, so `rigidBody.mass` was always 30,000 by the time the didSet ran. The forces and the mass were in agreement. Maximum thrust acceleration was `317_510 / 30_000 ≈ 10.6 m/s²` — perfectly reasonable, no runaway.

## Auxiliary observations (not causes, but worth flagging)

### A. The didSet logic itself is order-fragile

Even if the scene constructs the flight model first, the design is brittle. `rigidBody.mass` is a synced shadow of `flightModel.mass`, but only synced *at the moment rigid body is assigned*. If a future scene assigns `flightModel` after `rigidBody`, or swaps the flight model mid-game, the bug returns. Mass synchronization should not depend on one-shot didSet timing.

### B. F22 already imports MetalKit but no longer references it directly

`F22.swift:8` still has `import MetalKit`. With the lift/drag code moved out, F22.swift may not need it (the parent Aircraft.swift handles the imports it actually uses). Cosmetic only.

### C. Aircraft.doUpdate side-move runs even when there is no rigid body / flight model

`Aircraft.swift:68-70`:

```swift
applyPlayerAttitudeInput(deltaTurn: deltaTurn, controlInput: controlInput)
applyPlayerSideMove(deltaMove: deltaMove)
handleGearToggle()
```

These now run unconditionally (i.e., regardless of which branch the `if let rigidBody, let flightModel` resolves to). That's a behavioral change from the old F22.doUpdate, which gated attitude/sidemove/gear behind `if let rigidBody`. Not the cause of either bug, but a behavior shift you'll want to verify is intentional.

### D. `rigidBody.force += force` mixes with no other producers

There are no other writers to `rigidBody.force` for the F-22, so `+=` vs `=` is currently a no-op difference. If you later add wind/turbulence/gust modules that also push forces, `+=` is the right call — just worth being aware it's accumulating.

### E. EulerSolver runs *before* children update each frame

`FlightboxWithPhysics.doUpdate()` calls `super.doUpdate()` (which traverses children) and then `physicsWorld.update()`. But child updates actually happen inside `Node.update()` *after* `doUpdate()` returns — so the order each frame is:

1. `scene.doUpdate()` → `physicsWorld.update()` (consumes forces from last frame, zeros them)
2. Then `Node.update()` traverses children: `F22.doUpdate()` → `Aircraft.doUpdate()` → appends force for *next* frame

That's a 1-frame lag between when a force is computed and when it's integrated. Pre-existing (not introduced by this refactor) and not the cause here, but worth knowing — once you see physics behaving with a 1-frame phase offset, this is why.

## Recommended fixes (do not implement yet — flagged for the user)

In rough order of effort vs. correctness:

### Fix 1 (minimal): assign `flightModel` before constructing the rigid body

In `FlightboxWithPhysics.swift`:

```swift
let jet = F22(scale: 0.25)
jet.flightModel = F22SimpleFlightModel()                  // ← move up
let jetRigidBody = SphereRigidBody(gameObject: jet)
```

This makes the didSet fire with `flightModel` non-nil. Quickest fix, but leaves the order-fragile didSet logic in place. Future scenes have to remember the order.

### Fix 2 (better): sync mass from `flightModel` rather than from didSet

Add a `didSet` to `flightModel` on `Aircraft` (or `F22`) that pushes its mass into `rigidBody.mass` whenever either changes. Mass becomes one-way derived from the flight model, regardless of construction order.

```swift
var flightModel: FlightModel? {
    didSet {
        if let flightModel { rigidBody?.mass = flightModel.mass }
    }
}

override var rigidBody: RigidBody? {
    didSet {
        rigidBody?.restitution = 0.1
        if let flightModel { rigidBody?.mass = flightModel.mass }
    }
}
```

Then both orderings work, and re-assigning the flight model later updates the rigid body.

### Fix 3 (best, more invasive): make `rigidBody.mass` derived

`RigidBody.mass` is currently a stored property; nothing in the physics pipeline writes to it except construction and these aircraft-class didSets. If it became a computed property reading from a `MassSource` (initially: a closure, or a weak ref back to the entity's flight model), the duplicate field disappears and there's no synchronization to get wrong. This is more design work than the refactor scope warrants right now; flag as future cleanup.

### Verification once fix lands

After fixing, `rigidBody.mass` should be `30_000` after scene construction. To verify before observing flight behavior:

- Add a one-shot `print("F22 rigidBody.mass = \(rigidBody?.mass ?? -1)")` in `FlightboxWithPhysics.buildScene` after the assignments.
- Free fall: terminal velocity should now be ~1,200 m/s (effectively unbounded for the play timescale), so the jet should accelerate at ~9.8 m/s² for several seconds before drag starts mattering. Visually: rapid fall, not the slow drift you're seeing.
- Throttle: pressing W should produce a forward acceleration of ~10.6 m/s² (`engineMaxThrust * throttlePower / mass = 317_510 / 30_000`), which is brisk but not divergent. No NaN.

## Files referenced

- `ToyFlightSimulator Shared/GameObjects/F22.swift:20-25` — the order-fragile didSet
- `ToyFlightSimulator Shared/GameObjects/Aircraft.swift:21,52-74` — flightModel property; new doUpdate that consumes it
- `ToyFlightSimulator Shared/Physics/World/RigidBody.swift:48` — `gameObject.rigidBody = self` which fires the didSet
- `ToyFlightSimulator Shared/Physics/FlightModel/Models/F22SimpleFlightModel.swift:9-19,40-54` — mass/thrust constants and computeForce
- `ToyFlightSimulator Shared/Physics/Solver/EulerSolver.swift:16-25` — `acceleration = force/mass + gravity`
- `ToyFlightSimulator Shared/Scenes/FlightboxWithPhysics.swift:21-24` — scene construction order
- `ToyFlightSimulator Shared/Utils/Float3+Extensions.swift:25-28` — zero-safe normalize (not infinity-safe)
