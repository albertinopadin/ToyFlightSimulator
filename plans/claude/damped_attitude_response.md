# Plan: Damped First-Order Attitude Response

**Date:** 2026-05-17
**Status:** Proposal — no code changes yet, awaiting review.
**Related:** `code_reviews/claude/flight_model_review_2026-05-17.md` (item R11)

## Goal

Replace the current instant-response kinematic rotation in `Aircraft.applyPlayerAttitudeInput` with a first-order lag filter on the rotation rate. Same kinematic-rotation backbone (no torque, no moment of inertia, no angular integrator), but the rotation rate smoothly ramps toward the commanded rate instead of snapping to it.

Why: today, full stick deflection produces full rotation rate in a single 60 Hz step (~16 ms). On an F-22 the real roll-rate spool-up is ~150 ms, pitch ~250 ms, yaw ~400 ms. That difference is most of what makes the current flight feel "twitchy" rather than "responsive." This change gets ~80% of the way to proper rotational dynamics for ~30 lines of code and one new state struct, without committing to a full angular integrator.

The longer-term path (return `(force, torque)` from `FlightModel.computeForce`, give `RigidBody` a moment-of-inertia tensor + angular integrator) is documented in the doc comment on `FlightModel.computeForce` and is **not** part of this plan. This is the cheap intermediate step.

---

## Design

### The filter

Continuous form (first-order linear ODE):

```
dω/dt = (ω_cmd - ω) / τ
```

Where:
- `ω` is the current angular rate on one axis (rad/s)
- `ω_cmd` is the rate the pilot is commanding (`controlInput.<axis> * maxRate`)
- `τ` (tau) is the time constant — `ω` reaches `~63%` of `ω_cmd` in one `τ`, ~95% in three.

Discrete form, integrated exactly across a step of size `dt`:

```
α = 1 - exp(-dt / τ)
ω ← ω + (ω_cmd - ω) · α
```

For small `dt`, this matches the standard "lerp by α" exponential-smoothing form used in game code. Using `exp` (rather than `α = dt/τ`) keeps the filter behavior **independent of frame rate** — a 30 Hz frame and a 120 Hz frame converge to the same `ω(t)` trajectory. That's the key correctness property we want.

Per-axis state (`currentPitchRate`, `currentRollRate`, `currentYawRate`) is carried frame-to-frame on the `Aircraft`. The applied rotation per step is `ω · dt`, integrated via the existing `rotateX/Y/Z` helpers.

### Parameter shape

Two numbers per axis — max steady-state rate at full stick deflection, and the time constant for ramping to it. Six numbers total, grouped into one struct so subclasses tune them in init without touching the math.

| Axis | Default max rate | Default τ | Rationale |
|------|------------------|-----------|-----------|
| Pitch | 1.0 rad/s (~57°/s) | 0.25 s | Pitch authority is moderate on most fighters; stab response is medium-fast. |
| Roll  | 4.7 rad/s (~270°/s) | 0.15 s | F-22 spec is >270°/s. Roll response is the fastest axis on a fighter. |
| Yaw   | 0.5 rad/s (~29°/s) | 0.40 s | Rudder authority is weak (most yaw is from coordinated turns); rudder response is slow. |

These are first-cut defaults for fighter-class aircraft. F-16/F-18/F-35 don't need different values for the first pass; tune them later if they don't feel right.

### Where the new state lives

Aircraft owns it. Specifically: a new struct `AttitudeDynamics` on `Aircraft` holds the six parameters, and three `Float` properties on `Aircraft` hold the current per-axis rate.

Why on `Aircraft` and not on `FlightModel`:
- The kinematic rotation already lives on `Aircraft` (`applyPlayerAttitudeInput`). Keeping the lag filter next to the rotation it modulates avoids a round-trip.
- `FlightModel.computeForce` is a pure function of `(state, input) → force`. Adding mutable per-axis state to it would either contaminate that purity or require returning more from the call.
- When/if the proper torque path lands, `AttitudeDynamics` and the current-rate state collapse naturally into the angular integrator on `RigidBody` (rate becomes `rigidBody.angularVelocity`; the lag becomes part of the controller, not the integrator). The current proposal is forward-compatible with that move.

---

## Before / After

### Before — `Aircraft.swift`

```swift
class Aircraft: GameObject {
    public var shouldUpdateOnPlayerInput: Bool

    internal var _moveSpeed: Float = 25.0
    internal var _turnSpeed: Float = 4.0

    // ... other properties ...

    override func doUpdate() {
        super.doUpdate()

        let controlInput = getControlInput()
        let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
        let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
        
        if shouldUpdateOnPlayerInput && hasFocus {
            // ... force / thrust path ...
            applyPlayerAttitudeInput(deltaTurn: deltaTurn, controlInput: controlInput)
            applyPlayerSideMove(deltaMove: deltaMove)
            handleGearToggle()
        }

        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }

    internal func applyPlayerAttitudeInput(deltaTurn: Float, controlInput: ControlInput) {
        rotateZ(-deltaTurn * controlInput.roll)
        rotateX(-deltaTurn * controlInput.pitch)
        rotateY(-deltaTurn * controlInput.yaw)
    }
}
```

Behavior: at full stick deflection on roll, after a single 16 ms frame the aircraft has rotated `4.0 · 1.0 · 0.016 = 0.064 rad ≈ 3.7°`. Steady-state rate is `4.0 rad/s = ~229°/s`. Stick goes from neutral to full in zero time, so does rotation rate.

### After — `Aircraft.swift`

New types and properties:

```swift
/// Per-axis kinematic response parameters for first-order attitude lag.
/// `maxRate` is the steady-state rotation rate at full stick deflection (rad/s).
/// `timeConstant` (τ) is how long it takes the current rate to reach ~63% of
/// commanded; ~95% takes `3·τ`. See `plans/claude/damped_attitude_response.md`.
struct AttitudeDynamics {
    var maxPitchRate: Float   = 1.0   // rad/s (~57°/s)
    var maxRollRate: Float    = 4.7   // rad/s (~270°/s)
    var maxYawRate: Float     = 0.5   // rad/s (~29°/s)

    var pitchTimeConstant: Float = 0.25  // seconds
    var rollTimeConstant: Float  = 0.15
    var yawTimeConstant: Float   = 0.40
}

class Aircraft: GameObject {
    public var shouldUpdateOnPlayerInput: Bool

    internal var _moveSpeed: Float = 25.0
    // _turnSpeed removed — replaced by per-axis maxRate in AttitudeDynamics.

    /// Per-axis response parameters. Subclasses override in init if needed.
    var attitudeDynamics = AttitudeDynamics()

    /// Current angular rates carried across frames. Reset to 0 when control
    /// is lost (see `hasFocus` handling in `doUpdate`).
    private var currentPitchRate: Float = 0
    private var currentRollRate: Float = 0
    private var currentYawRate: Float = 0

    // ... other properties ...
}
```

Updated `doUpdate` (call-site change: pass `deltaTime` instead of `deltaTurn`):

```swift
override func doUpdate() {
    super.doUpdate()

    if shouldUpdateOnPlayerInput && hasFocus {
        let controlInput = getControlInput()
        let dt = Float(GameTime.DeltaTime)
        let deltaMove = dt * _moveSpeed

        if let rigidBody, let flightModel {
            let rigidBodyState = rigidBody.getState()
            let force = flightModel.computeForce(state: rigidBodyState, input: controlInput)
            rigidBody.force += force
        } else {
            moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
        }

        applyPlayerAttitudeInput(deltaTime: dt, controlInput: controlInput)
        applyPlayerSideMove(deltaMove: deltaMove)
        handleGearToggle()
    } else {
        // Lost control — bleed off accumulated rotation rate so we don't
        // snap-resume a tumble next time hasFocus flips back on. Without
        // this the aircraft keeps spinning while not under player control.
        decayAttitudeRates(deltaTime: Float(GameTime.DeltaTime))
    }

    animator?.update(deltaTime: Float(GameTime.DeltaTime))
}
```

New filter math:

```swift
internal func applyPlayerAttitudeInput(deltaTime: Float, controlInput: ControlInput) {
    let dyn = attitudeDynamics

    let cmdPitchRate = controlInput.pitch * dyn.maxPitchRate
    let cmdRollRate  = controlInput.roll  * dyn.maxRollRate
    let cmdYawRate   = controlInput.yaw   * dyn.maxYawRate

    // Frame-rate-independent exponential smoothing. α = 1 - e^(-dt/τ).
    // For dt << τ this approximates dt/τ; using the exact form keeps
    // 30/60/120 Hz steps converging to the same trajectory.
    let pitchAlpha = 1 - exp(-deltaTime / dyn.pitchTimeConstant)
    let rollAlpha  = 1 - exp(-deltaTime / dyn.rollTimeConstant)
    let yawAlpha   = 1 - exp(-deltaTime / dyn.yawTimeConstant)

    currentPitchRate += (cmdPitchRate - currentPitchRate) * pitchAlpha
    currentRollRate  += (cmdRollRate  - currentRollRate)  * rollAlpha
    currentYawRate   += (cmdYawRate   - currentYawRate)   * yawAlpha

    // Sign convention matches the prior code: pitch up = stick back =
    // negative-X rotation; roll right = stick right = negative-Z rotation;
    // yaw right = pedal right = negative-Y rotation. See
    // CLAUDE.md "Coordinate Conventions" for the pilot-perspective
    // sign-flip rationale.
    rotateX(-currentPitchRate * deltaTime)
    rotateZ(-currentRollRate  * deltaTime)
    rotateY(-currentYawRate   * deltaTime)
}

/// Decay accumulated rates toward zero when not under player control.
/// Uses the same time constants as the active path so the bleed-off
/// feels symmetric with the spool-up.
private func decayAttitudeRates(deltaTime: Float) {
    let dyn = attitudeDynamics
    let pitchAlpha = 1 - exp(-deltaTime / dyn.pitchTimeConstant)
    let rollAlpha  = 1 - exp(-deltaTime / dyn.rollTimeConstant)
    let yawAlpha   = 1 - exp(-deltaTime / dyn.yawTimeConstant)

    currentPitchRate += (0 - currentPitchRate) * pitchAlpha
    currentRollRate  += (0 - currentRollRate)  * rollAlpha
    currentYawRate   += (0 - currentYawRate)   * yawAlpha

    rotateX(-currentPitchRate * deltaTime)
    rotateZ(-currentRollRate  * deltaTime)
    rotateY(-currentYawRate   * deltaTime)
}
```

Behavior at full stick deflection on roll, starting from rest, 60 Hz:
- t=0:   ω=0, cmd=4.7. α = 1 - exp(-0.016/0.15) ≈ 0.103. ω ← 0 + (4.7 - 0)·0.103 = 0.48 rad/s
- t=16ms: rotation applied = 0.48 · 0.016 = 0.0077 rad ≈ 0.44° (compare: prior code = 3.7°)
- t=150ms (~1τ): ω ≈ 0.63 · 4.7 = 2.96 rad/s
- t=450ms (~3τ): ω ≈ 0.95 · 4.7 = 4.47 rad/s — essentially at steady state
- t→∞: ω → 4.7 rad/s = 270°/s

Stick centered from full deflection (release): symmetric decay, ω → 0 with same τ.

---

## Touch list

Files that change:

1. **`ToyFlightSimulator Shared/GameObjects/Aircraft.swift`**
   - Add `AttitudeDynamics` struct (file-private — only Aircraft and subclasses need to see it; can be promoted to its own file if a third type starts using it)
   - Add `attitudeDynamics` property (default values)
   - Add private `currentPitchRate` / `currentRollRate` / `currentYawRate`
   - Remove `_turnSpeed`
   - Rewrite `applyPlayerAttitudeInput` per "after" above
   - Add `decayAttitudeRates`
   - Update `doUpdate` call site (pass `deltaTime` not `deltaTurn`)

Files that **don't** change:

- `F22.swift`, `F22_CGTrader.swift`, `F35.swift`, `F16.swift`, `F18.swift`, `F18_usdz.swift` — none of them override `applyPlayerAttitudeInput` or read `_turnSpeed`. The new defaults apply uniformly until per-subclass tuning is added.
- `FlightModel.swift`, `F22SimpleFlightModel.swift`, `ControlInput.swift`, `LiftData.swift`, `RigidBody.swift` — out of scope. Force math is unaffected.

Files that **may** want updates afterward but aren't part of this plan:

- `F22_CGTrader.swift` overrides `doUpdate` to call `self.animator?.deflectHorizontalStabilizers(pitchInput:, rollInput:)` using raw `controlInput.pitch` / `.roll`. After this change, you'd ideally drive control-surface deflection from the commanded rate, but the animator is already a kinematic-display layer — passing raw stick input is fine. Re-evaluate if surfaces start looking out-of-phase with the aircraft body.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Net behavior change at the default settings — current `_turnSpeed = 4.0` produced 4 rad/s instant rate on all three axes; new defaults are 1.0 / 4.7 / 0.5 rad/s with lag. Anyone who'd memorized the current feel will notice. | Acceptable — that's the point. If the new feel is wrong, the parameters are six numbers in one struct. |
| F-22 in `FlightboxWithPhysics` is the only player-flown aircraft right now, so testing is one config. Other aircraft (`F-35` in any scene that uses it as player, `F-22_CGTrader`) inherit `Aircraft`'s defaults. | All current scenes flying non-F22 aircraft pass `shouldUpdateOnPlayerInput: false` (wingmen). The first real test of an alternate config is when a different aircraft becomes the player. |
| The `decayAttitudeRates` branch in `doUpdate` adds a tiny per-frame cost when control is inactive. | Three `exp` calls and three multiplies per non-controlled frame. Negligible. |
| Subclasses might want to disable the filter entirely for testing (e.g., to confirm a rendering bug isn't caused by attitude lag). | Set all `timeConstant`s to a very small value (e.g., 0.001) — `α → 1`, behavior matches snap-to-target. No explicit disable flag needed. |
| `currentPitchRate` etc. are stored mutable state — `Aircraft` is on the update thread (single owner), so no synchronization needed. | Documented invariant; relies on `Aircraft.doUpdate` running on UpdateThread (see `CLAUDE.md` Threading section). No change to threading model. |

---

## Open questions for you

1. **Per-aircraft defaults or shared defaults?** I'm proposing shared defaults on `Aircraft` (so F-16, F-18, F-22, F-35 all start at the same numbers) with subclasses tuning in init. Alternative: bake type-specific values into each subclass from the start. The shared-defaults route is easier to walk back if defaults are wrong; the subclass-specific route is more honest about real aerodynamic differences.

2. **Should `AttitudeDynamics` live in `Physics/FlightModel/` or `GameObjects/`?** Conceptually it's a flight-model concern (aerodynamic response is a property of the airframe), but the *application* of it is kinematic (`rotateX/Y/Z`) so it lives where the rotation lives — on `Aircraft`. If the proper torque path lands later, this struct migrates into `FlightModel` (or into `RigidBody` as an `AngularDynamics` sibling). For now: stay on `Aircraft` next to the rotation code.

3. **Should we keep `_turnSpeed` as a back-compat shim?** Nothing else in the codebase reads it (grep confirms — only Aircraft.swift references it). Cleaner to delete and update the call site than to keep an unused stored property. Proposed: delete.

4. **Should the decay path also apply rotation, or just bleed off the rate?** I have it applying rotation (so a player who releases control mid-roll sees the roll continue and damp out — physical). Alternative: bleed off without applying, so loss of control freezes attitude. The applying version feels right for a flight sim; the freezing version is what arcade games do. Proposed: apply.

5. **Future-proofing for an angle-of-attack-dependent gain schedule** — at high AoA, real fighters lose pitch/roll/yaw authority (especially yaw). Want a hook for that now (e.g., `maxRate` becomes a function of `state.aoa`), or wait until the FlightModel grows torque and that scheduling moves there naturally? Proposed: wait. The current proposal is forward-compatible — `maxRate` could become a computed property later without touching the filter math.

---

## Out of scope for this plan

- Moving rotation into the rigid-body integrator (full torque path). That's the option-2 follow-up in the doc comment on `FlightModel.computeForce`.
- Per-axis G-loading limits (the F-22's flight-control system caps pilot inputs at 9 G).
- Pilot-induced oscillation (PIO) protection — the filter inherently smooths sudden inputs, which is itself a form of PIO suppression, but a real FCS does more.
- Modeling angular damping from aerodynamic surfaces — that's a different physics term (`τ_damp = -k_damp · ω`) that lives in the torque path, not the kinematic-rotation path.
- Force-feedback / haptics — current input system doesn't have output capabilities; not affected.
