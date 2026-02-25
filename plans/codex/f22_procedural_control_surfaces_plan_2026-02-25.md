# F-22 Procedural Control-Surface Animation Plan

**Date:** 2026-02-25  
**Status:** Design only (no runtime code changes yet)  
**Goal:** Support input-driven procedural animation for F-22 control surfaces (flaperons, ailerons, rudders, horizontal stabilizers) while preserving existing clip-driven landing gear.

## Plan Outcome
Implement a mixed animation pipeline where:
- landing gear remains clip-driven via existing binary channels,
- control surfaces are value-driven via existing continuous channels,
- final skeleton pose is composed once per skeleton from both sources.

## Key Decision
**Do not add `ProceduralAnimationChannel` initially.**  
Reuse `ContinuousAnimationChannel` and add a procedural evaluation path + metadata.

## Phase 1: Fix Input-to-Channel Signal Semantics

### Problem
`rollFlaperons` currently calls `setNormalizedValue(value)` with signed roll input.

### Changes (example)
```swift
// AircraftAnimator.swift (example)
func rollFlaperons(value: Float) {
    let clamped = max(-1.0, min(1.0, value))
    for case let channel as ContinuousAnimationChannel in flaperonLayer.channels {
        channel.setValue(clamped) // signed domain, not normalized [0,1]
    }
}
```

### Why first
This is a correctness bug independent of larger architecture and prevents neutral controls from behaving correctly.

## Phase 2: Introduce Procedural Surface Definitions (Data)

### Add new config model
Create a data definition for each procedural surface joint.

```swift
// New file example: Animation/Configs/AircraftProceduralSurface.swift
struct AircraftProceduralSurface {
    let channelID: String
    let jointPath: String
    let axisLocal: float3
    let minAngleDeg: Float
    let maxAngleDeg: Float
    let inputMix: InputMix

    struct InputMix {
        let roll: Float
        let pitch: Float
        let yaw: Float
        let flap: Float
    }
}
```

### F-22 mapping example
Use explicit names from your armature instead of `contains("flaperon")` discovery:
- `LeftAileron`
- `LeftFlaperon`
- `LeftRudder`
- `RightAileron`
- `RightFlaperon`
- `RightRudder`
- `LeftHorzStablizer`
- `RightHorzStablizer`

```swift
// F22AnimationConfig.swift (example)
static let controlSurfaces: [AircraftProceduralSurface] = [
    .init(channelID: "f22.leftFlaperon", jointPath: ".../LeftFlaperon", axisLocal: [1,0,0],
          minAngleDeg: -25, maxAngleDeg: 25,
          inputMix: .init(roll: +1, pitch: 0, yaw: 0, flap: +0.4)),
    .init(channelID: "f22.rightFlaperon", jointPath: ".../RightFlaperon", axisLocal: [1,0,0],
          minAngleDeg: -25, maxAngleDeg: 25,
          inputMix: .init(roll: -1, pitch: 0, yaw: 0, flap: +0.4)),
    // ...rudders, ailerons, horizontal stabilizers
]
```

## Phase 3: Add Channel Evaluation Mode (Clip vs Procedural)

### Goal
Prevent automatic clip fallback for channels intended to be procedural.

### Example shape
```swift
enum ChannelEvaluationMode {
    case clip
    case proceduralRotation(ProceduralRotationSpec)
}

struct ProceduralRotationSpec {
    let jointPath: String
    let axisLocal: float3
    let minAngleRad: Float
    let maxAngleRad: Float
    let additive: Bool
}
```

### Integration example
```swift
// ContinuousAnimationChannel example additions
var evaluationMode: ChannelEvaluationMode = .clip
```

```swift
// AnimationLayerSystem.registerChannel example
if channel.animationClip == nil,
   channel.evaluationMode == .clip,
   let firstClip = model.animationClips.values.first {
    channel.animationClip = firstClip
}
```

## Phase 4: Add Skeleton API for Procedural Joint Overrides

### Problem
Current `Skeleton.updatePose(at:animationClip:)` fully regenerates pose from clip.

### Add API (example)
```swift
// Skeleton.swift example API
func updatePose(
    at time: Float,
    animationClip: AnimationClip?,
    localRotationOverrides: [String: simd_quatf] = [:]
) {
    // Build local pose from clip if available, else rest transforms.
    // Apply overrides on matching joint local transforms.
    // Recompute world pose + bind inverse as today.
}
```

### Important behavior
- If `animationClip` is nil, start from rest pose.
- If clip exists, apply procedural rotations additively to clip local pose.
- Keep current basis transform handling intact.

## Phase 5: Refactor `AnimationLayerSystem` to Compose Per Skeleton Once

### Problem
Current loop updates skeleton per dirty channel, which overwrites full poses repeatedly.

### New flow (example)
1. Update all channels.
2. For each affected skeleton, gather:
- current clip state/time from clip channels,
- procedural overrides from procedural channels.
3. Call `skeleton.updatePose(...)` once per skeleton.
4. Update affected mesh palettes once.

```swift
// AnimationLayerSystem.update example skeleton compose pseudo-code
for skeletonPath in affectedSkeletons {
    let base = cachedBasePoseState[skeletonPath] // clip + time
    let overrides = proceduralOverrides[skeletonPath] ?? [:]

    model.skeletons[skeletonPath]?.updatePose(
        at: base.time,
        animationClip: base.clip,
        localRotationOverrides: overrides
    )
}
```

### State cache needed
Cache per-skeleton base clip time so procedural-only frames keep current gear pose stable.

## Phase 6: Add Aircraft Control Mixer in `F22Animator`

### Goal
Compute per-surface target values from pilot input each frame.

### Example
```swift
// F22Animator example
func setControlInputs(roll: Float, pitch: Float, yaw: Float, flap: Float) {
    for surface in F22AnimationConfig.controlSurfaces {
        let raw = roll * surface.inputMix.roll
                + pitch * surface.inputMix.pitch
                + yaw * surface.inputMix.yaw
                + flap * surface.inputMix.flap
        let target = max(-1.0, min(1.0, raw))
        channel(surface.channelID, as: ContinuousAnimationChannel.self)?.setValue(target)
    }
}
```

### `F22_CGTrader` example callsite
```swift
let roll = InputManager.ContinuousCommand(.Roll)
let pitch = InputManager.ContinuousCommand(.Pitch)
let yaw = InputManager.ContinuousCommand(.Yaw)
animator?.setControlInputs(roll: roll, pitch: pitch, yaw: yaw, flap: currentFlapCommand)
```

## Phase 7: Validation

## Automated checks
- Build:
```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```
- Existing tests:
```bash
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Manual checks
1. Neutral stick (`roll/pitch/yaw = 0`) keeps all control surfaces neutral.
2. Roll left/right deflects left/right surfaces oppositely as expected.
3. Yaw input deflects rudders correctly.
4. Pitch input deflects horizontal stabilizers correctly.
5. Landing gear toggle still works while continuously moving control surfaces.
6. No jitter from mixed input sources (keyboard + controller + HOTAS).

## Optional hardening
- Add deadzone and response curves before mixer.
- Add per-surface rate limits in deg/s.
- Add debug HUD line showing each surface command and resulting channel value.

## Risks and Mitigations
- **Risk:** Joint path mismatches in USD armature names.  
  **Mitigation:** Validate all configured joint paths at startup and warn once per missing joint.

- **Risk:** Procedural channels accidentally fallback to clip.  
  **Mitigation:** Explicit evaluation mode; assert if `procedural` channel has clip-only processing.

- **Risk:** Pose overwrite between clip and procedural updates.  
  **Mitigation:** Per-skeleton compose-once flow + cached base clip state.

## Answer to Channel-Type Question
For this codebase, **Binary + Continuous channels are sufficient**. Add procedural evaluation semantics and control-surface metadata; only introduce a dedicated `ProceduralAnimationChannel` later if you want stricter API typing after the feature is stable.
