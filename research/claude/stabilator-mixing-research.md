# Stabilator/Horizontal Stabilizer Mixing Research

## The Problem

The F-22's horizontal stabilizers (stabilators) need **two types** of procedural animation:
1. **Pitch**: Both stabs deflect in the **same** direction (symmetric)
2. **Roll**: Both stabs deflect in **opposite** directions (differential/antisymmetric)

The question: Should this be implemented as two separate AnimationLayers (a `HorizontalStabilizerPitchLayer` and a `HorizontalStabilizerRollLayer`), or is there a better approach?

## Current Architecture

Currently `F22AnimationConfig.createHorizontalStabilizerLayer()` creates a single layer with one `ProceduralAnimationChannel` containing two `ProceduralJointConfig` entries (left and right stab). Both configs have `inverted: true` and use the same `value`, so they deflect in the same direction — pitch only.

The `AircraftAnimator` has `pitchHorizontalStabilizers(value:)` and a commented-out `rollHorizontalStabilizers(value:)`.

### The Conflict

The current `Skeleton.applyProceduralOverrides()` does:
```swift
localPoses[index] = restTransforms[index] * rotationOverride
```

This is **replacement**, not additive. If two layers both target the same joint (e.g., LeftHorzStablizer), the **last writer wins**. A separate pitch layer and roll layer would overwrite each other — you'd only see whichever executed last.

## Research Findings

### Industry Standard: Mathematical Input Mixing (Not Animation Layers)

Every major flight simulator and game engine flight sim examined uses the same pattern: **mix the inputs mathematically, then apply a single rotation per surface**.

#### The Universal Formula

```
left_stab_deflection  = pitchInput * pitchAuthority + rollInput * rollAuthority
right_stab_deflection = pitchInput * pitchAuthority - rollInput * rollAuthority
```

The sign difference on `rollInput` for the right surface is what creates differential deflection for roll while keeping symmetric deflection for pitch.

This is exactly how real fly-by-wire aircraft work — the flight control computer receives stick inputs and computes individual actuator commands per surface.

### DCS World

Uses numbered "Animation Arguments" per control surface. Each argument receives a single pre-mixed value (-1 to 1). The flight model Lua code computes the final deflection per surface by combining pitch and roll commands. The animation system is just a value-to-rotation mapping — no blending.

Key animation arguments for stabilizers: 15 (right), 16 (left), each independently driven.

### Microsoft Flight Simulator

Uses XML-driven animations where SimVars like `ELEVATOR_DEFLECTION` drive animation percentage. The mixing of pitch + roll into individual surface deflections happens at the **flight model level**, not in the animation system. Each surface gets a single SimVar value.

### Unity Flight Sims

The Vazgriz and gasgiant/Aircraft-Physics projects both use direct procedural rotation. For dual-purpose surfaces, the mixing happens in gameplay code:
```csharp
rightAileron.localRotation = CalculatePose(rightAileron,
    Quaternion.Euler(deflection.z * maxAileronDeflection, 0, 0));
```

The `AircraftController` in gasgiant's project maintains surfaces with input types (Pitch, Yaw, Roll, Flap) and an **input multiplier** for opposite directional responses.

### Unreal Engine

Uses **Transform (Modify) Bone** in Animation Blueprints with "Add to Existing" mode for procedural bone control. For flight sims, the mixing happens in the aircraft Blueprint — computing a single final angle per surface and feeding it to the bone. The animation system doesn't blend two separate "pitch" and "roll" animations.

Unreal's **Aim Offset** (a 2D Blend Space where all samples are additive) is conceptually similar to what you need — it's a 2D input space (pitch, yaw) that produces a blended pose. But even this computes a single output per bone, not two separate layers.

### Godot

Direct mathematical rotation in scripts. No AnimationTree-based blending for control surfaces. Godot 4.3's `SkeletonModifier3D` provides sequential stacking of procedural modifiers, but flight sims don't use it — they just compute the angle.

### What About Additive Animation Layers?

Unity, Unreal, and ozz-animation all support **additive animation blending** where deltas from a reference pose are composed via quaternion multiplication:

```
result_rotation = base_rotation * additive_delta
```

Multiple additive layers can be stacked:
```
pose_after_add1 = base * additive1
pose_after_add2 = pose_after_add1 * additive2
```

This **would** technically work for stabilators — you could have a pitch additive layer and a roll additive layer stacking their rotations. However:

1. **It's overkill** — control surfaces are simple single-axis rotations. Mathematical mixing is simpler and more precise.
2. **Quaternion composition order matters** — `A * B ≠ B * A`. With single-axis rotations that share the same axis this doesn't matter, but it's an unnecessary complication.
3. **No production flight sim uses this approach** — the universal pattern is pre-mixing inputs.
4. **Additive blending is designed for organic character animation** (walking + aiming, idle + breathing) where pre-authored clips need to be combined. Control surfaces are parametric, not pre-authored.

## Recommendation: Input Mixing, Not Separate Layers

### Why Two Layers Is the Wrong Approach

1. **Your current `applyProceduralOverrides` uses replacement semantics** (`localPoses[index] = rest * rotation`). Two layers targeting the same joints would overwrite each other.
2. **Even with additive blending**, you'd be adding unnecessary complexity. You'd need to modify `Skeleton.applyProceduralOverrides` to support additive composition, handle quaternion math correctly, and worry about execution order.
3. **It violates the industry standard pattern** that every flight sim uses.

### The Correct Approach: Single Layer, Pre-Mixed Input

Keep a single `horizontalStabilizer` layer with one `ProceduralAnimationChannel`, but **mix pitch and roll inputs before setting the channel value**. Since the left and right stabs need different mixed values, there are two clean ways to do this:

#### Option A: Two Channels in One Layer (Recommended)

Split into two channels within the same layer — one per surface:

```swift
// Left stab channel — gets pitchInput + rollInput
let leftStabChannel = ProceduralAnimationChannel(
    id: "horizontalStab_left",
    mask: AnimationMask(jointPaths: [leftStabPath]),
    range: (-1.0, 1.0),
    transitionSpeed: 5.0,
    jointConfigs: [ProceduralJointConfig(
        jointPath: leftStabPath,
        axis: horizontalStabRotationAxis,
        maxDeflection: horizontalStabMaxDeflection,
        inverted: true
    )]
)

// Right stab channel — gets pitchInput - rollInput
let rightStabChannel = ProceduralAnimationChannel(
    id: "horizontalStab_right",
    mask: AnimationMask(jointPaths: [rightStabPath]),
    range: (-1.0, 1.0),
    transitionSpeed: 5.0,
    jointConfigs: [ProceduralJointConfig(
        jointPath: rightStabPath,
        axis: horizontalStabRotationAxis,
        maxDeflection: horizontalStabMaxDeflection,
        inverted: true
    )]
)

return AnimationLayer(id: horizontalStabilizerLayerID,
                      channels: [leftStabChannel, rightStabChannel])
```

Then in `AircraftAnimator`, add a method that does the mixing:

```swift
func deflectHorizontalStabilizers(pitchInput: Float, rollInput: Float) {
    guard let layer = horizontalStabilizerLayer else { return }
    for case let channel as ProceduralAnimationChannel in layer.channels {
        if channel.id == "horizontalStab_left" {
            channel.setValue(pitchInput + rollInput)
        } else if channel.id == "horizontalStab_right" {
            channel.setValue(pitchInput - rollInput)
        }
    }
}
```

#### Option B: Mixed Procedural Channel (New Channel Type)

Create a `MixedProceduralAnimationChannel` — a single channel that accepts **multiple named input values** and computes each joint's deflection from a per-joint mixing formula. This encapsulates the mixing logic inside the channel itself rather than in the animator.

**New config struct** — extends `ProceduralJointConfig` with per-input gain coefficients:

```swift
/// Describes how a single joint responds to multiple named inputs.
/// The final deflection is: sum(inputs[name] * gains[name]) * maxDeflection
struct MixedProceduralJointConfig {
    let jointPath: String
    let axis: float3
    let maxDeflection: Float

    /// Maps input name -> gain multiplier.
    /// Example: ["pitch": 1.0, "roll": 1.0]  for left stab
    ///          ["pitch": 1.0, "roll": -1.0] for right stab
    let inputGains: [String: Float]

    init(jointPath: String,
         axis: float3,
         maxDeflection: Float,
         inputGains: [String: Float]) {
        self.jointPath = jointPath
        self.axis = axis
        self.maxDeflection = maxDeflection
        self.inputGains = inputGains
    }
}
```

**The channel** — replaces the single `value`/`targetValue` with a dictionary of named inputs, each smoothed independently:

```swift
/// A procedural channel where each joint's deflection is a weighted mix
/// of multiple named input values. Useful for control surfaces that serve
/// dual functions (stabilators: pitch + roll, elevons: pitch + roll,
/// flaperons: flaps + roll).
final class MixedProceduralAnimationChannel: AnimationChannel {
    // MARK: - AnimationChannel Properties

    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?  // Always nil
    private(set) var isDirty: Bool = false

    // MARK: - Input Properties

    /// Current values per named input, smoothed toward targets each frame
    private var currentValues: [String: Float]

    /// Target values per named input
    private var targetValues: [String: Float]

    /// Speed of value change (units per second), shared across all inputs
    var transitionSpeed: Float

    /// Valid range for each input value
    let range: (min: Float, max: Float)

    // MARK: - Joint Configs

    let jointConfigs: [MixedProceduralJointConfig]

    // MARK: - Initialization

    /// - Parameters:
    ///   - id: Unique identifier
    ///   - mask: Joints this channel controls
    ///   - inputNames: The named inputs this channel responds to (e.g., ["pitch", "roll"])
    ///   - range: Valid range per input (default -1...1)
    ///   - transitionSpeed: Smoothing speed in units/sec
    ///   - jointConfigs: Per-joint mixing configurations
    init(
        id: String,
        mask: AnimationMask,
        inputNames: [String],
        range: (min: Float, max: Float) = (-1.0, 1.0),
        transitionSpeed: Float = 5.0,
        jointConfigs: [MixedProceduralJointConfig]
    ) {
        self.id = id
        self.mask = mask
        self.range = range
        self.transitionSpeed = transitionSpeed
        self.jointConfigs = jointConfigs

        // Initialize all inputs to zero
        self.currentValues = Dictionary(uniqueKeysWithValues: inputNames.map { ($0, Float(0)) })
        self.targetValues = self.currentValues
        self.isDirty = true
    }

    // MARK: - Control Methods

    /// Set a named input's target value (smoothed over time)
    func setInput(_ name: String, value: Float) {
        let clamped = max(range.min, min(range.max, value))
        guard let current = targetValues[name], abs(clamped - current) > 0.001 else { return }
        targetValues[name] = clamped
        isDirty = true
    }

    /// Set a named input's value immediately (no smoothing)
    func setInputImmediate(_ name: String, value: Float) {
        let clamped = max(range.min, min(range.max, value))
        currentValues[name] = clamped
        targetValues[name] = clamped
        isDirty = true
    }

    // MARK: - AnimationChannel Protocol

    func update(deltaTime: Float) {
        var changed = false
        let maxChange = transitionSpeed * deltaTime

        for name in currentValues.keys {
            guard let target = targetValues[name],
                  let current = currentValues[name] else { continue }
            let diff = target - current
            guard abs(diff) > 0.001 else { continue }

            if abs(diff) <= maxChange {
                currentValues[name] = target
            } else {
                currentValues[name] = current + (diff > 0 ? maxChange : -maxChange)
            }
            changed = true
        }

        if changed { isDirty = true }
    }

    func getAnimationTime() -> Float { 0 }
    func clearDirty() { isDirty = false }

    // MARK: - Procedural Pose Computation

    /// Computes per-joint rotation overrides by mixing all named inputs
    /// using each joint's gain coefficients.
    func getJointOverrides() -> [String: float4x4] {
        var overrides: [String: float4x4] = [:]

        for config in jointConfigs {
            // Sum weighted inputs: deflection = sum(input_i * gain_i)
            var mixedValue: Float = 0
            for (inputName, gain) in config.inputGains {
                mixedValue += (currentValues[inputName] ?? 0) * gain
            }

            // Clamp the mixed result to prevent over-deflection
            let clampedValue = max(range.min, min(range.max, mixedValue))
            let angle = clampedValue * config.maxDeflection
            let rotation = float4x4(rotateAbout: normalize(config.axis), byAngle: angle)
            overrides[config.jointPath] = rotation
        }

        return overrides
    }
}
```

**Usage in F22AnimationConfig** — a single layer, single channel, with the mixing formula baked into the joint configs:

```swift
static func createHorizontalStabilizerLayer(for model: UsdModel) -> AnimationLayer {
    let allJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
    let leftPath = allJointPaths.first { $0.hasSuffix("LeftHorzStablizer") }
    let rightPath = allJointPaths.first { $0.hasSuffix("RightHorzStablizer") }

    var jointConfigs: [MixedProceduralJointConfig] = []

    if let left = leftPath {
        jointConfigs.append(MixedProceduralJointConfig(
            jointPath: left,
            axis: horizontalStabRotationAxis,
            maxDeflection: horizontalStabMaxDeflection,
            inputGains: ["pitch": -1.0, "roll": 1.0]  // pitch + roll
        ))
    }

    if let right = rightPath {
        jointConfigs.append(MixedProceduralJointConfig(
            jointPath: right,
            axis: horizontalStabRotationAxis,
            maxDeflection: horizontalStabMaxDeflection,
            inputGains: ["pitch": -1.0, "roll": -1.0]  // pitch - roll
        ))
    }

    let allPaths = jointConfigs.map { $0.jointPath }
    let mask = AnimationMask(jointPaths: allPaths)

    let channel = MixedProceduralAnimationChannel(
        id: "horizontalStabilizers",
        mask: mask,
        inputNames: ["pitch", "roll"],
        range: (-1.0, 1.0),
        transitionSpeed: 5.0,
        jointConfigs: jointConfigs
    )

    return AnimationLayer(id: horizontalStabilizerLayerID, channels: [channel])
}
```

**Usage in AircraftAnimator** — clean API, no mixing math in the animator:

```swift
func deflectHorizontalStabilizers(pitchInput: Float, rollInput: Float) {
    guard let layer = horizontalStabilizerLayer else { return }
    for case let channel as MixedProceduralAnimationChannel in layer.channels {
        channel.setInput("pitch", value: pitchInput)
        channel.setInput("roll", value: rollInput)
    }
}
```

**Required change to AnimationLayerSystem** — the layer system uses `is ProceduralAnimationChannel` type checks to route to the procedural code path. `MixedProceduralAnimationChannel` would need the same treatment. Options:

1. **Make it a subclass** of `ProceduralAnimationChannel` — but the stored properties differ enough (dict vs single Float) that this is awkward.
2. **Add a protocol** (e.g., `ProceduralPoseProvider`) that both channel types conform to, and check for that protocol instead:
   ```swift
   protocol ProceduralPoseProvider: AnimationChannel {
       func getJointOverrides() -> [String: float4x4]
   }
   ```
   Then in `AnimationLayerSystem.updatePoses()`:
   ```swift
   if let proceduralChannel = channel as? ProceduralPoseProvider {
       let overrides = proceduralChannel.getJointOverrides()
       // ... apply overrides (unchanged)
   }
   ```
3. **Add a parallel `else if`** for `MixedProceduralAnimationChannel` in the ~5 places that do `is ProceduralAnimationChannel` checks. Quick but less clean.

**Trade-offs vs Option A:**

| Aspect | Option A (two channels) | Option B (mixed channel) |
|--------|------------------------|-------------------------|
| Infrastructure changes | None | New channel type + protocol or type check changes |
| Mixing logic location | In `AircraftAnimator` | In `MixedProceduralJointConfig.inputGains` |
| Reusability | Pattern repeated per aircraft | Reusable for any multi-input surface |
| Config clarity | Mixing formula spread across animator + config | Mixing formula fully declarative in config |
| Smoothing behavior | Each surface smoothed independently | Each *input axis* smoothed independently (more correct — pitch and roll have independent dynamics) |
| Complexity | Minimal | Moderate — new type, dict-based values |
| Extensibility | Need to update animator mixing code per aircraft | Just change `inputGains` per aircraft |

### Why Option A Is Best for Your System

- **Zero changes to AnimationLayerSystem or Skeleton** — the existing infrastructure handles it perfectly
- **Each channel targets a different joint** — no mask overlap, no last-writer-wins problem
- **The mixing formula matches real F-22 fly-by-wire logic**
- **Extends naturally** to flaperons (which also need roll + flap mixing on the real F-22)
- **Simple, explicit, easy to debug**

### The Same Pattern Applies to Flaperons

On the real F-22, flaperons combine:
- Aileron function (differential deflection for roll)
- Flap function (symmetric deflection for low-speed lift)

```
left_flaperon  = flapPosition + rollInput * aileronAuthority
right_flaperon = flapPosition - rollInput * aileronAuthority
```

If you later want this, the same two-channels-per-layer pattern works.

## Summary Table

| Approach | Pros | Cons | Used By |
|----------|------|------|---------|
| **Two separate layers** (pitch + roll) | Conceptually clean separation | Requires additive blending (not implemented), overwrites with current system | Nobody |
| **Single layer, input mixing** (recommended) | Matches industry standard, zero infra changes, simple | Mixing logic lives in animator, not config | DCS, MSFS, Unity/Unreal flight sims, real FBW aircraft |
| **Additive blending infrastructure** | General-purpose, future-proof | Over-engineered for control surfaces, complex to implement correctly | Unity/Unreal character animation (not flight sims) |

## References

- DCS World Animation Arguments: per-surface parameters driven by pre-mixed flight model values
- MSFS Animation System: SimVar-driven per-surface rotations with mixing in flight model
- Unity gasgiant/Aircraft-Physics: input type + multiplier per AeroSurface
- Unreal Transform (Modify) Bone: single pre-computed angle per surface bone
- ozz-animation additive blending: `result = base * weighted_delta` (for character animation)
- Wikipedia: Elevon, Stabilator — mechanical mixing in real aircraft
- F-22 Raptor: fly-by-wire with stabilator differential for pitch + roll authority

## URLs Visited

### Unity Animation System
- [Unity Manual: Animation Layers](https://docs.unity3d.com/Manual/AnimationLayers.html)
- [Unity Learn: Creating and configuring Animator Layers](https://learn.unity.com/course/the-animator/tutorial/3-7-creating-and-configuring-animator-layers?version=2019.4)
- [Unity Scripting API: AnimationUtility.SetAdditiveReferencePose](https://docs.unity3d.com/ScriptReference/AnimationUtility.SetAdditiveReferencePose.html)
- [Override versus Additive blending - Unity 2018 Cookbook (O'Reilly)](https://www.oreilly.com/library/view/unity-2018-cookbook/9781788471909/ff9efd76-ef0f-41a0-a22b-0fb109234201.xhtml)
- [Unity Manual: Avatar Mask window](https://docs.unity3d.com/Manual/class-AvatarMask.html)
- [Unity Manual: Mask (on imported clips)](https://docs.unity3d.com/Manual/AnimationMaskOnImportedClips.html)
- [Unity Avatar Mask and Animation Layers - Diego Giacomelli](https://diegogiacomelli.com.br/unity-avatar-mask-and-animation-layers/)
- [Avatar mask with root bone in extra animation layer - Unity Discussions](https://discussions.unity.com/t/avatar-mask-with-root-bone-in-extra-animation-layer/678757)
- [Animancer - Layers Documentation](https://kybernetik.com.au/animancer/docs/manual/blending/layers/)

### Unity Animation Blending & Procedural Rotation
- [V Rising's Animation Layering in Unity - 80.lv](https://80.lv/articles/v-rising-s-animation-layering-in-unity)
- [Animation Rigging with Multiple Animator Layers - Unity Discussions](https://discussions.unity.com/t/animation-rigging-with-multiple-animator-layers/845199)
- [Rotating a bone with script - Unity Discussions](https://discussions.unity.com/t/rotating-a-bone-with-script/572881)
- [Bones rotation from script with LateUpdate - Unity Forum](https://forum.unity.com/threads/bones-rotation-from-script-with-lateupdate.482376/)
- [Bones Stimulator - Unity Discussions](https://discussions.unity.com/t/bones-stimulator-make-your-animations-more-fun-with-additive-procedural-animation/709107)
- [Multi-Rotation Constraint - Unity Animation Rigging](https://docs.unity3d.com/Packages/com.unity.animation.rigging@1.1/manual/constraints/MultiRotationConstraint.html)

### Unity Flight Simulators
- [Creating a Flight Simulator in Unity3D Part 1 - Vazgriz](https://vazgriz.com/346/flight-simulator-in-unity3d-part-1/)
- [Translating a Fortran F-16 Simulator to Unity3D - Vazgriz](https://vazgriz.com/762/f-16-flight-sim-in-unity-3d/)
- [GitHub: gasgiant/Aircraft-Physics](https://github.com/gasgiant/Aircraft-Physics)

### Unreal Engine Animation System
- [Unreal Engine 5.7 -- Using Layered Animations](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-layered-animations-in-unreal-engine)
- [Unreal Engine 5.7 -- Animation Blueprint Blend Nodes](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-blend-nodes-in-unreal-engine)
- [Unreal Engine 5.7 -- Blend Masks and Blend Profiles](https://dev.epicgames.com/documentation/en-us/unreal-engine/blend-masks-and-blend-profiles-in-unreal-engine)
- [Aaron Kemner -- Layered Blend Per Bone Reference](https://www.aaronkemner.com/animnode-reference/layeredboneblend/)
- [Unreal Engine 5.7 -- Animation Blueprint Transform Bone](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-transform-bone-in-unreal-engine)
- [Unreal Engine 5.7 -- Aim Offset](https://dev.epicgames.com/documentation/en-us/unreal-engine/aim-offset-in-unreal-engine)
- [Unreal Engine 5.7 -- Bone Driven Controller](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-bone-driven-controller-in-unreal-engine)
- [Unreal Engine 5.7 -- Control Rig](https://dev.epicgames.com/documentation/en-us/unreal-engine/control-rig-in-unreal-engine)
- [Unreal Engine 5.7 -- Skeletal Controls](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-blueprint-skeletal-controls-in-unreal-engine)
- [Unreal Engine 5.7 -- Animation Montage](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-montage-in-unreal-engine)
- [Unreal Engine 5.7 -- Animation Montage Editor](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-montage-editor-in-unreal-engine)
- [UDK -- Additive Animations](https://docs.unrealengine.com/udk/Three/AdditiveAnimations.html)
- [Unreal Engine 4.26 -- Using Layered Animations (Additive)](https://docs.unrealengine.com/4.26/en-US/AnimatingObjects/SkeletalMeshAnimation/AnimHowTo/AdditiveAnimations)
- [Epic Forums -- Apply Additive node changes bones scale](https://forums.unrealengine.com/t/apply-additive-node-changes-bones-scale/1188322)
- [UE5 Blending Animation Montage - Medium](https://medium.com/software-dev-explore/ue5-blending-animation-montage-933f00adaa1e)
- [Animation Blending and Montages - O'Reilly](https://www.oreilly.com/library/view/game-development-projects/9781800209220/B16183_12_Final_SMP_ePub.xhtml)
- [How do you use animation montages and slots - LinkedIn](https://www.linkedin.com/advice/0/how-do-you-use-animation-montages-slots-layer-mix-animations)

### Unreal Engine Flight Simulators
- [Epic Forums -- How to animate control surfaces on a physics driven aircraft?](https://forums.unrealengine.com/t/how-to-animate-control-surfaces-on-a-physics-driven-aircraft/340454)
- [Unreal Engine Marketplace -- Plane And Space Ship Controller](https://www.unrealengine.com/marketplace/en-US/product/plane-and-space-ship-controller)
- [Jay Versluis -- Creating a Control Rig from scratch in Unreal Engine](https://www.versluis.com/2024/03/creating-a-control-rig-from-scratch-in-unreal-engine/)
- [Unreal University -- How To Transform Modify Bones (Complete Guide)](https://www.unreal-university.blog/how-to-transform-modify-bones-in-unreal-engine-5-complete-guide/)

### Godot Engine
- [Godot Engine -- Using AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html)
- [Godot Engine -- AnimationNodeBlendTree](https://docs.godotengine.org/en/stable/classes/class_animationnodeblendtree.html)
- [Godot Forum -- Mixing two animations with bone filters](https://forum.godotengine.org/t/mixing-two-animations-with-bone-filters-for-upper-lower-body-of-armature/117058)
- [Godot Engine -- Design of the Skeleton Modifier 3D](https://godotengine.org/article/design-of-the-skeleton-modifier-3d/)
- [Godot Engine -- SkeletonModifier3D Class Reference](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html)
- [Godot Forum -- Using SkeletonModifier3D](https://forum.godotengine.org/t/using-skeletonmodifier3d/83559)
- [GitHub Issue #87428 -- Cannot override bone Transform with AnimationTree](https://github.com/godotengine/godot/issues/87428)
- [GitHub Issue #37661 -- AnimationTree: Add2 does not seem to be additive](https://github.com/godotengine/godot/issues/37661)
- [GitHub Issue #79963 -- Add2 Blend Node does not Add](https://github.com/godotengine/godot/issues/79963)
- [GitHub Proposal #7907 -- Improve support for additive animation](https://github.com/godotengine/godot-proposals/issues/7907)
- [Godot Forum -- Blend2 vs Add2 difference](https://forum.godotengine.org/t/what-is-the-difference-between-blend2-and-add2-blend3-and-add3-in-animationtree-in-godot-3-1/26801)

### Godot Flight Simulators
- [KidsCanCode -- Arcade-style Airplane (Godot 4)](https://kidscancode.org/godot_recipes/4.x/3d/simple_airplane/index.html)
- [GitHub -- Simplified Flight Simulation library](https://github.com/fbcosentino/godot-simplified-flightsim)
- [Godot Asset Library -- 3D Flight Control Tutorial](https://godotengine.org/asset-library/asset/2272)

### Animation Blending Theory & Math
- [Animation Blending Knowledge Base - chrisdoescoding.com](https://chrisdoescoding.com/kb/game_engine_programming/animation_blending.html)
- [AnimCoding -- Animation Tech Intro Part 3: Blending](https://animcoding.com/post/animation-tech-intro-part-3-blending/)
- [ozz-animation Additive Blending Sample](https://guillaumeblanc.github.io/ozz-animation/samples/additive/)
- [GitHub -- ozz-animation sample_additive.cc](https://github.com/guillaumeblanc/ozz-animation/blob/master/samples/additive/sample_additive.cc)
- [Quaternion and Animation Blending - GameDev.net](https://www.gamedev.net/forums/topic/645242-quaternions-and-animation-blending-questions/5077083/)
- [Rotation Blending - GameDev.net](https://gamedev.net/forums/topic/670357-rotations-blending/5242623/)
- [Accumulating Quaternions - GameDev.net](https://www.gamedev.net/forums/topic/547517-accumulating-quaternions/)
- [Everything you need to know about Quaternions for Game Development - boristhebrave.com](https://www.boristhebrave.com/2022/12/12/everything-you-need-to-know-about-quaternions-for-game-development/)

### DCS World
- [DCS Modding Guideline Wiki -- Animation Arguments for Aircraft](https://dcs-modding-guideline.fandom.com/wiki/Animation_Arguments_for_Aircraft)
- [Hoggitworld Wiki -- External Model](https://wiki.hoggitworld.com/view/External_Model)
- [DCS Forum -- Bone animation constraints](https://forum.dcs.world/topic/99023-bone-animation-constraints-trouble/)
- [DCS Forum -- Bones and skeleton animation](https://forum.dcs.world/topic/83941-bones-and-skeleton-animation)

### Microsoft Flight Simulator
- [MSFS SDK -- Model Animation Definitions](https://docs.flightsimulator.com/html/Content_Configuration/Models/Model_Animation_Definitions.htm)
- [MSFS SDK -- Animations Overview](https://docs.flightsimulator.com/html/mergedProjects/How_To_Make_An_Aircraft/Contents/Modelling/Airframe/Animations_Overview.htm)
- [MSFS SDK -- Model Behaviors](https://docs.flightsimulator.com/html/Content_Configuration/Models/ModelBehaviors/Model_Behaviors.htm)
- [MSFS SDK -- Animation XML Properties (2024)](https://docs.flightsimulator.com/msfs2024/html/5_Content_Configuration/Models/Animation_XML_Properties.htm)

### Other Engines
- [CryEngine V -- Additive Animations](https://docs.cryengine.com/display/CEMANUAL/Additive+Animations)
- [CryEngine 3 -- Animation Layers](https://docs.cryengine.com/display/SDKDOC2/Animation+Layers)
- [Bevy GitHub Issue #14395 -- Layered Blend Per Bone / Additive Blending](https://github.com/bevyengine/bevy/issues/14395)

### Real Aircraft / Aerodynamics
- [Wikipedia -- Elevon](https://en.wikipedia.org/wiki/Elevon)
- [Wikipedia -- Stabilator](https://en.wikipedia.org/wiki/Stabilator)
- [Wikipedia -- Lockheed Martin F-22 Raptor](https://en.wikipedia.org/wiki/Lockheed_Martin_F-22_Raptor)
- [ArduPilot -- Elevon Planes](https://ardupilot.org/plane/docs/guide-elevon-plane.html)
- [Flite Test -- Elevon Mixing](https://www.flitetest.com/articles/Elevon_Mixing_)
- [Airliners.net -- How do elevons work differentially](https://www.airliners.net/forum/viewtopic.php?t=1442825)
- [F-16.net Forum -- F-22 Thrust Vectoring and Roll Control](https://www.f-16.net/forum/viewtopic.php?t=8910)
- [DCS Forum -- F-22 Ailerons act as elevators also](https://forum.dcs.world/topic/24145-f-22-aelerons-act-as-elevators-also/)
- [Fly a Jet Fighter -- Stabilizers and control surfaces on fighter aircraft](https://www.flyajetfighter.com/stabilizers-and-control-surfaces-on-fighter-aircraft/)
