# F-22 Procedural Aircraft Animation Research

**Date:** 2026-02-25  
**Scope:** Existing ToyFlightSimulator animation architecture + procedural animation patterns in Unity, Unreal, and Godot.

## 1) Current Project Findings (Code Reading)

### 1.1 The system is currently clip-time centric
- `AnimationLayerSystem` sets a clip automatically when a channel has none (`AnimationLayerSystem.swift:100-104`).
- Per dirty channel, pose update is driven only by `animTime = channel.getAnimationTime()` (`AnimationLayerSystem.swift:218-242`).
- Skeleton pose generation always samples an `AnimationClip` for every joint (`Skeleton.swift:81-119`).

Implication: a channel with no meaningful clip cannot directly produce procedural joint motion.

### 1.2 F-22 flaperon channels exist but are not configured as true procedural channels
- `F22AnimationConfig.createFlaperonLayer` creates `ContinuousAnimationChannel`s with masks and no explicit clip (`F22AnimationConfig.swift:79-100`).
- Because of `registerChannel` fallback behavior, these channels can still end up clip-bound to the model's first clip (`AnimationLayerSystem.swift:100-104`).

### 1.3 There is an input mapping bug for roll -> flaperon value
- `F22_CGTrader` passes raw roll input to `rollFlaperons` (`F22_CGTrader.swift:46-50`).
- `rollFlaperons` calls `setNormalizedValue(value)` (`AircraftAnimator.swift:194-203`).
- `setNormalizedValue` expects `[0, 1]`, but roll input is effectively signed (`[-1, 1]`), and `ContinuousCommand` can also sum multiple devices (`InputManager.swift:301-349`).

Result: neutral `0` maps to channel minimum for a `(-1, 1)` range, and negative values can clamp hard.

### 1.4 Existing channel types already model needed control semantics
- `ContinuousAnimationChannel` already has:
  - signed ranges (`range`)
  - target tracking (`targetValue`)
  - smoothing/rate control (`transitionSpeed`)
  - immediate vs smooth set APIs.

The missing capability is not channel state/value logic; it's the evaluation path that converts a channel value into bone transforms without requiring a clip.

## 2) External Engine Research (Primary Docs)

## Unity (official docs)

### What Unity does
- Uses Animator Layers with **Override/Additive** blending and per-layer masking (`AvatarMask`) for body-part isolation.
- Uses **Blend Trees** where gameplay parameters directly drive blend ratios.
- Supports runtime parameter updates from code via `Animator.SetFloat(...)`, including damping over time.
- Supports procedural post-processing constraints via **Animation Rigging** (`RigBuilder`, constraints).
- Supports low-level custom procedural jobs via Playables (`IAnimationJob`, `AnimationScriptPlayable`) that read/write animation stream data.

### Why this matters here
Unity separates **control signal channels** (parameters like roll/pitch/yaw) from **pose generation strategy** (clip blending, rig constraints, or custom jobs). It does not require a separate semantic concept just because motion is procedural.

## Unreal Engine (official docs)

### What Unreal does
- Animation Blueprint splits logic into:
  - **EventGraph** (update variables each frame)
  - **AnimGraph** (compose final pose)
- Uses blend nodes including **Layered Blend per Bone** to apply partial-body overrides.
- Uses skeletal control nodes in component space to procedurally adjust bones before output pose conversion.
- Uses Control Rig/IK stacks for procedural control layered with clip playback.

### Why this matters here
Unreal’s pattern is also: input variables -> per-frame graph evaluation -> masked bone overrides -> one final pose. Procedural animation is treated as another evaluator node, not fundamentally a distinct “channel category” at API level.

## Godot (official docs)

### What Godot does
- `AnimationTree` parameters are set from script (runtime-driven procedural control inputs).
- Animation nodes support filtering/masking via track filters (`set_filter_path`, `is_path_filtered`).
- `SkeletonModifier3D` is explicitly intended for custom procedural operations after animation blending.
- `Skeleton3D` exposes direct per-bone pose mutation APIs (`set_bone_pose_rotation/position/scale`).
- Blend nodes support signed blends (e.g., `AnimationNodeBlend3` uses `-1..1`).

### Why this matters here
Godot also treats procedural control as runtime parameterized pose modification layered with animation playback. Again, the core pattern is shared.

## 3) Cross-Engine Pattern Synthesis

Across Unity/Unreal/Godot, the common architecture is:
1. Compute input/control variables each frame.
2. Build a base pose from clips/state.
3. Apply masked additive/override procedural bone ops.
4. Output one final skeleton pose for skinning.

This maps cleanly to ToyFlightSimulator with the smallest conceptual change:
- keep existing channel value/state model,
- add a procedural pose-evaluation path in `AnimationLayerSystem`/`Skeleton`.

## 4) Recommended Direction for This Project

## 4.1 Keep `BinaryAnimationChannel` and `ContinuousAnimationChannel`
Use these as the control/value abstraction for all aircraft animation channels.

## 4.2 Add channel evaluation modes (clip vs procedural)
Introduce a way for the runtime to know whether a channel should:
- sample clip time (`clip` mode), or
- apply a value-driven joint transform (`procedural` mode).

This can be implemented via:
- a lightweight `ChannelEvaluationMode` enum,
- and procedural metadata (joint path, axis, angle range, blend mode) either on channel instances or in a side-table keyed by channel ID.

## 4.3 Refactor pose update from per-channel overwrite to per-skeleton compose
Current per-channel `skeleton.updatePose(...)` calls overwrite full skeleton poses. For robust mixed clip+procedural layers, compose once per skeleton per frame:
- start from cached/base clip pose,
- apply all active masked channel contributions,
- update skin palette once.

## 4.4 Add an aircraft control-surface mixer
Before channel writes, compute surface commands from pilot input:
- flaperons (roll + flap schedule)
- ailerons (roll)
- rudders (yaw)
- horizontal stabilizers (pitch, optionally roll coupling)

Then feed resulting signed values into existing continuous channels with rate limiting.

## 5) Direct Answer: New `ProceduralAnimationChannel` Needed?

**Short answer: no, not required.**

`ContinuousAnimationChannel` is already a good fit for procedural control surfaces because it provides the right signal model (signed value, target, smoothing, clamping). The current limitation is evaluation: the runtime assumes channel output is always clip time.

A separate `ProceduralAnimationChannel` could be added later for API readability, but it is optional and not necessary to deliver correct procedural control-surface animation now.

## 6) Notes for Immediate Fixes (when implementation begins)

- Replace `setNormalizedValue(rollValue)` with `setValue(rollValue)` in `AircraftAnimator.rollFlaperons`.
- Clamp aggregated `InputManager.ContinuousCommand(...)` values before driving control surfaces.
- Remove/guard automatic “assign first clip” behavior for procedural channels.

## 7) Sources

### Unity
- [Animation Layers in Animator Controller](https://docs.unity3d.com/Manual/AnimationLayers.html)
- [Blend Trees](https://docs.unity3d.com/Manual/class-BlendTree.html)
- [Animator.SetFloat API](https://docs.unity3d.com/ScriptReference/Animator.SetFloat.html)
- [Animation Rigging package: Rigging workflow](https://docs.unity3d.com/Packages/com.unity.animation.rigging@1.3/manual/RiggingWorkflow.html)
- [IAnimationJob API](https://docs.unity3d.com/ScriptReference/Animations.IAnimationJob.html)
- [AnimationScriptPlayable API](https://docs.unity3d.com/ScriptReference/Animations.AnimationScriptPlayable.html)

### Unreal
- [Animation Blueprints](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprints-in-unreal-engine)
- [Blend Nodes](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-blend-nodes-in-unreal-engine)
- [Layered Animations](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-layered-animations-in-unreal-engine)
- [Skeletal Controls](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-skeletal-controls-in-unreal-engine)

### Godot
- [Using AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html)
- [AnimationNode](https://docs.godotengine.org/en/stable/classes/class_animationnode.html)
- [SkeletonModifier3D](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html)
- [Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html)
- [AnimationNodeBlend3](https://docs.godotengine.org/en/stable/classes/class_animationnodeblend3.html)
