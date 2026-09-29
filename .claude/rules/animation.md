---
paths:
  - "ToyFlightSimulator Shared/Animation/**"
---
# Animation system

Moved verbatim from the root `CLAUDE.md` on 2026-09-20 so it loads only when working on the files matched by `paths` above. Keep it current the same way as `CLAUDE.md`.

### Animation System (Animation/)
**AnimationController** protocol with playback state management. **AnimationLayerSystem** manages layers and channels with dirty-flag optimization. Channel→skeleton/mesh affinity AND per-joint resolution happen once at registration: `ChannelMapping.SkeletonEntry` carries the resolved `Skeleton` reference, clip, `(jointIndex, animation)` pairs (clip channels), and joint indices (procedural channels) — the per-frame path does no String/dictionary lookups. `Skeleton` caches `inverseBindTransforms`, the basis conjugation pair, and a `jointIndexByPath` map at init, and `evaluateWorldPoses()` writes `currentPose` in place (allocation-free; bind-inverse + basis conjugation fused). `Animation` keyframe sampling scans for the bracketing pair without materializing a pairs array; procedural channels fill a reused rotation scratch buffer (axes pre-normalized in `ProceduralJointConfig.init`).

**Channel types** (individual animated elements):
- `BinaryAnimationChannel`: Two-state (landing gear up/down). States: inactive → activating → active → deactivating. Progress-based smooth transitions.
- `ContinuousAnimationChannel`: Variable-position (flaps, control surfaces). Value range with `transitionSpeed`.

**AnimationLayer**: Groups related channels that animate together to form a discrete animation (e.g., all the channels needed to extend the landing gear). **AnimationMask** for selective joint targeting. Skeleton/skin palette updates per channel. Layer IDs are typed via `enum AnimationLayerID: String` (cases: `landingGear`, `flaperon`, `aileron`, `horizontalStabilizer`, `rudder`, and the cockpit's `cockpitStick`, `cockpitThrottle`, `cockpitRudderPedals`, `cockpitGearHandle`) defined once in `AircraftAnimator.swift`.

**Skeleton conjugation**: `Skeleton.evaluateWorldPoses` and `TransformComponent` map native-space deltas via `B^T * J * (B^T)^-1` (`Transform.basisConjugationMatrices`). Mesh transform is row-vector (`v_engine = v*B`); shader skins as column-vector (`J*v`) — hence the transpose. Reduces to the old `B^-1 * J * B` for orthonormal permutation bases; with the meterization scale folded in (`B = S·B₀`) it scales joint translations by s, where the inverse form divided them by s (an s² error).

**Aircraft animators**: `AircraftAnimator` base → `F35Animator`, `F22Animator`. `Aircraft` base provides `setupAnimator<A: AircraftAnimator>(_ make: (UsdModel) -> A)` (handles UsdModel cast + warning) and a default `doUpdate()` that runs gear-toggle input and `animator?.update(deltaTime:)`. Subclasses only override `doUpdate` if they need procedural per-frame logic beyond the animator (e.g., `F22_CGTrader` for ailerons/flaperons/horizontal stabs/rudders). `Aircraft.isGearDown` returns `animator?.isGearDown ?? true`.

**Cockpit animator**: `F22CockpitAnimator` (layers in `F22CockpitAnimationConfig`) moves the F-22 cockpit's side-stick, throttles, pedals and gear handle. `Aircraft.attachCockpit` builds it as `Aircraft.cockpitAnimator` (concrete type: one cockpit exists); `Aircraft.doUpdate` sets its targets from the player's `ControlInput` (`updateCockpitControls`, after `handleGearToggle`) and updates it outside the input guard. Setters live on the cockpit animator, not the `AircraftAnimator` base, because only it registers those layers. The throttle maps through the detents with the pure `F22CockpitAnimationConfig.throttleLeverAngle` (MIL at `F22.milPowerThrottleThreshold`, the afterburner threshold). The gear handle follows the exterior animator's `gearState` and stays DN without one (the Sketchfab `F22` has none). **Rotation sign**: `float4x4(rotateAbout:byAngle:)` is the transpose of the right-handed axis-angle matrix (positive = clockwise seen from the axis tip), so derive `inverted` flags from that, not from the right-hand rule; the direction tests in `CockpitAnimatorTests` check each joint through the skin palette.
