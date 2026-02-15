# Aircraft Animation Channel/Channel-Set Architecture Notes

**Date:** 2026-02-15  
**Scope:** `F35` animation flow (`F35.swift` -> `F35Animator` -> `AircraftAnimator` -> `AnimationLayerSystem`)

## Questions
1. Does the current architecture make sense?
2. How can the code be simplified while keeping the same functionality?

## Short Answer
- **Yes, the core idea makes sense**: independent channels per animatable subsystem, and a logical grouping for aircraft-level controls (like landing gear).
- **Current implementation is overcomplicated for current needs** and is in a half-migrated state (both channel and channel-set systems exist, but only one path is really used).

## What Is Good
- `BinaryAnimationChannel` and `ContinuousAnimationChannel` are clean, reusable primitives with clear state/value transitions:
  - `ToyFlightSimulator Shared/Animation/Channels/BinaryAnimationChannel.swift`
  - `ToyFlightSimulator Shared/Animation/Channels/ContinuousAnimationChannel.swift`
- `AnimationMask` is a useful abstraction for targeting affected joints/meshes:
  - `ToyFlightSimulator Shared/Animation/Channels/AnimationMask.swift`
- `F35AnimationConfig` already separates model-specific binding logic from runtime control:
  - `ToyFlightSimulator Shared/Animation/Aircraft/F35AnimationConfig.swift`

## Main Problems (with evidence)

1. **Dual architecture (channels + channel sets) adds complexity and inconsistency**
- `AnimationLayerSystem` keeps both `channels` and `channelSets`:
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:20`
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:22`
- Update path uses only channel sets:
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:178`
- But several APIs still operate on the old channels dictionary (`channelCount`, `hasDirtyChannels`, debug, `setChannelValue`):
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:40`
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:45`
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:344`
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:365`
- Result: misleading state (e.g. F35 prints `0 channels` despite registering a set):
  - `ToyFlightSimulator Shared/Animation/Aircraft/F35Animator.swift:25`

2. **`AnimationChannelSet` is explicitly hacky and not type-safe**
- It relies on casting and first-element assumptions for state/progress/duration:
  - `ToyFlightSimulator Shared/Animation/Channels/AnimationChannelSet.swift:17`
  - `ToyFlightSimulator Shared/Animation/Channels/AnimationChannelSet.swift:23`
  - `ToyFlightSimulator Shared/Animation/Channels/AnimationChannelSet.swift:28`
- Operations are best-effort casts (`as? BinaryAnimationChannel`) rather than guaranteed capabilities:
  - `ToyFlightSimulator Shared/Animation/Channels/AnimationChannelSet.swift:33`
  - `ToyFlightSimulator Shared/Animation/Channels/AnimationChannelSet.swift:41`
- This works for current F-35 gear, but it is fragile and hard to reason about.

3. **Mask targeting logic currently over-updates meshes**
- In `updatePoses`, this line makes mesh-skeleton matching effectively always true for mapped meshes:
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:253`
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift:254`
- That weakens the intended benefits of per-channel masking.

4. **Dead/legacy paths increase code size and cognitive load**
- Legacy single-channel paths and commented code remain in multiple files:
  - `ToyFlightSimulator Shared/Animation/Aircraft/AircraftAnimator.swift`
  - `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift`
  - `ToyFlightSimulator Shared/Animation/Aircraft/F35AnimationConfig.swift`
- `createLandingGearChannel` appears obsolete given channel-set usage:
  - `ToyFlightSimulator Shared/Animation/Aircraft/F35AnimationConfig.swift:29`

5. **Brittle error handling in config**
- `fatalError` is used for missing clip/skeleton mappings:
  - `ToyFlightSimulator Shared/Animation/Aircraft/F35AnimationConfig.swift:91`
  - `ToyFlightSimulator Shared/Animation/Aircraft/F35AnimationConfig.swift:99`
- Reasonable during bring-up, risky for runtime robustness.

## Recommended Simplification Direction (minimum code, same behavior)

### Recommendation: Use **one runtime abstraction only** in `AnimationLayerSystem` (channels), and keep gear grouping at the animator level.

Why this is the smallest useful simplification:
- Channel primitives are already solid.
- Channel sets currently mostly duplicate behavior with casts/hacks.
- Group orchestration for gear can be a small `[BinaryAnimationChannel]` in `AircraftAnimator` (or a tiny typed helper), with less code than maintaining a second registry path.

### Target shape
1. `AnimationLayerSystem` manages only `[String: AnimationChannel]`.
2. `F35AnimationConfig` returns landing-gear **channels** (one per clip/skeleton mapping as needed).
3. `F35Animator` registers those channels individually.
4. `AircraftAnimator` stores gear channels as a typed list and exposes:
   - `toggleGear()`, `extendGear()`, `retractGear()`
   - aggregate gear state/progress/duration

### Expected net result
- Fewer concepts.
- Fewer casts.
- No split-brain state.
- Same current feature behavior (F-35 gear toggling via grouped channels).

## Guardrails for Refactor
- Preserve initial state behavior (`gear down` at start).
- Preserve discrete input behavior (`ToggleGear` debounce path unchanged).
- Keep per-clip/per-mask support for multi-part gear animation.
- Keep `hasExternalAnimator = true` behavior in `AnimationLayerSystem`.
