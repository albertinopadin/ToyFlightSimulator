# Procedural Animation for Aircraft Control Surfaces - Research

## Problem Statement

The F-22 CGTrader model has an armature with bones for control surfaces (LeftFlaperon, RightFlaperon, LeftAileron, RightAileron, LeftRudder, RightRudder, LeftHorzStablizer, RightHorzStablizer). These need to be animated **procedurally** based on player input (roll, pitch, yaw), not from pre-authored animation clips. The current `AnimationLayerSystem` only supports clip-based animation via `Skeleton.updatePose(at:animationClip:)`.

## Current System Analysis

### Data Flow (Clip-Based - Landing Gear)
```
Player toggles gear
  → BinaryAnimationChannel.toggle()
  → channel.isDirty = true
  → AnimationLayerSystem.update(deltaTime)
  → channel.update(deltaTime) advances progress 0.0→1.0
  → channel.getAnimationTime() maps progress to clip time
  → skeleton.updatePose(at: animTime, animationClip: clip)
  → clip.getPose(at:jointPath:) returns keyframed transform for EVERY joint
  → skeleton.currentPose updated (ALL joints)
  → skin.updatePalette(skeleton:) pushes to GPU
```

### Why Flaperons Don't Work Currently

The `ContinuousAnimationChannel` for flaperons is configured with:
- Range: -1.0 to 1.0 (mapping to player roll input)
- No animation clip (no flaperon keyframes exist in the USDZ)
- Mask targeting flaperon joint paths

When `AnimationLayerSystem.updatePoses()` processes a flaperon channel:
1. `channel.getAnimationTime()` returns a normalized value (0.0-1.0) — **meaningless without a clip**
2. `skeleton.updatePose(at: animTime, animationClip: clip)` uses whatever clip was auto-assigned (the landing gear clip!)
3. The landing gear clip has no keyframes for flaperon joints, so they fall back to `restTransforms`
4. **Worse**: This call updates ALL joints from the landing gear clip time, potentially clobbering the correct landing gear pose

### Fundamental Issue: `Skeleton.updatePose()` is All-or-Nothing

`Skeleton.updatePose(at:animationClip:)` (Skeleton.swift:81-119) replaces the **entire** `currentPose` array. It iterates ALL joints, gets a pose from the clip (or rest transform), computes world-space transforms, and writes the full array. There is no concept of:
- Updating only specific joints
- Overlaying procedural transforms on top of clip-based transforms
- Preserving some joints while changing others

---

## How Other Game Engines Solve This

### Unity
**Two separate systems**, connected by evaluation order:
- **Clip-based**: Animator state machine evaluates first
- **Procedural**: Either direct `Transform.localRotation` in `LateUpdate()` (override) or Animation Rigging constraints (weight-blended)
- **Bone partitioning**: Avatar Masks exclude procedural bones from clip evaluation
- Common aircraft pattern: landing gear in Animator clips, control surfaces via `bone.localRotation = restRotation * Quaternion.Euler(0, 0, deflectionAngle)` in LateUpdate

### Unreal Engine
**Unified pipeline** via AnimGraph:
- Both clip nodes and Skeletal Control nodes (Transform Bone) are peers in the same graph
- **Transform (Modify) Bone** node has three modes per axis:
  - **Ignore**: Keep existing transform
  - **Replace Existing**: Override with procedural value
  - **Add to Existing**: Add procedural offset to clip result
- Alpha property (0.0-1.0) controls blend between input pose and procedural modification
- Aircraft pattern: Control surface angles stored as Blueprint variables, read by AnimBP, fed to Transform Bone nodes in Bone Space

### Godot (4.3+)
**Explicit separation** with guaranteed processing order:
- AnimationMixer (clips) evaluates first
- **SkeletonModifier3D** nodes execute after, in child-list order
- Each modifier has `influence` (0.0-1.0) for blending
- **Pose rollback**: After modifiers run and skin is computed, pose resets to pre-modification state (ephemeral overrides)
- Purpose-built solution created in Godot 4.3 specifically because the old system (direct `set_bone_pose_rotation`) conflicted with AnimationTree

### Microsoft Flight Simulator
**Percentage-based interpolation** system where all animations work on a 0-100% scale. Both clip-based (gear) and procedural (ailerons) use the same mechanism — the distinction is in the data source (discrete state vs. continuous input variable), not in the animation system architecture.

### Common Pattern Across All Engines

```
1. Clip-Based Pass (landing gear, canopy, weapon bays):
   - Full skeleton update from animation clip at current time
   - Result: base pose for all joints

2. Procedural Override Pass (ailerons, elevators, rudder, flaps):
   - For each procedural bone:
     - Take rest transform (or current clip-derived transform)
     - Apply rotation: restPose * RotationMatrix(axis, angle_from_input)
   - Only modifies targeted joints; all others preserved

3. Skin Update:
   - Compute final joint palette from combined pose
   - Upload to GPU
```

**Key design principle**: Clip-based and procedural animation target **non-overlapping bone sets** (bone partitioning). When they do overlap, evaluation order determines priority: procedural runs after clips and can override or add to them.

---

## Analysis of Current Architecture's Gap

The current architecture has a single pose pathway:

```
channel.getAnimationTime() → float → skeleton.updatePose(at:clip:) → ALL joints from clip
```

For procedural animation, we need a second pathway:

```
channel.value → rotation angle → skeleton.applyJointOverride(jointPath, transform) → SPECIFIC joints
```

### What ContinuousAnimationChannel Gets Right
- Value range (-1.0 to 1.0) appropriate for control surface deflection
- Smooth transitions via `transitionSpeed`
- Dirty flag optimization
- AnimationMask targeting specific joints

### What ContinuousAnimationChannel Gets Wrong
- `getAnimationTime()` maps value to a clip time — meaningless without a clip
- No knowledge of rotation axis or deflection limits
- Designed around the assumption that `value → time → clip → pose` is the only pathway

### What AnimationLayerSystem.updatePoses() Gets Wrong
- Hardcoded to call `skeleton.updatePose(at:clip:)` for all channels
- No branch for "this channel provides direct transforms, not clip times"
- Calls `mesh.transform?.setCurrentTransform(at:)` which also assumes time-based sampling

### What Skeleton Gets Wrong
- `updatePose()` replaces ALL joints — no partial update support
- No method to override individual joint transforms
- No separation between "base pose computation" and "per-joint override application"

---

## Answer: Do We Need a New Channel Type?

**Yes, a new `ProceduralAnimationChannel` is the cleanest approach.**

The `ContinuousAnimationChannel` could theoretically be extended with a "procedural mode" flag, axis config, and max deflection angle. But this would be poor design for several reasons:

1. **Different output semantics**: ContinuousAnimationChannel produces a `Float` (animation time). A procedural channel needs to produce `[String: float4x4]` (per-joint transform overrides). These are fundamentally different outputs that the layer system must handle differently.

2. **Single Responsibility**: ContinuousAnimationChannel's job is mapping a continuous value to a clip time range. A procedural channel's job is mapping a continuous value to a bone rotation. Mixing both responsibilities would make the class harder to understand and maintain.

3. **Pipeline branching**: `AnimationLayerSystem.updatePoses()` must handle clip-based and procedural channels differently. Having a distinct type makes the branching clean (`if let procedural = channel as? ProceduralAnimationChannel`) rather than checking a mode flag on ContinuousAnimationChannel.

4. **Configuration clarity**: A procedural channel needs different config (rotation axis, max deflection angle per joint, optional inversion for left/right symmetry). This doesn't belong on ContinuousAnimationChannel which is configured with clip time ranges.

5. **Follows industry practice**: All three major engines treat procedural bone manipulation as a distinct system from clip-based animation, even if they share a common pipeline. Unity has Animation Rigging vs Animator, UE has Transform Bone vs Animation Sequence, Godot has SkeletonModifier3D vs AnimationMixer.

The existing `ContinuousAnimationChannel` remains valuable for future use cases where a continuous value maps to an animation clip time (e.g., flap deployment from 0-100% using a pre-authored flap animation clip).
