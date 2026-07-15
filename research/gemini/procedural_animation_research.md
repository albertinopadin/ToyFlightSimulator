# Procedural Animation Research

## 1. Context and Current Architecture
In `ToyFlightSimulator`, the animation system is currently driven by authored `AnimationClip`s. 
- `AnimationLayerSystem` manages layers and channels.
- When a channel is dirty, `AnimationLayerSystem.updatePoses` calls `skeleton.updatePose(at: animTime, animationClip: clip)`.
- `Skeleton.updatePose` calculates the `localPose` for *all* joints by sampling the given clip. If the clip doesn't have an animation for a joint, it defaults to the `restTransform`.
- Finally, `Skeleton.updatePose` calculates the `worldPose` hierarchy and applies bind/basis transforms.

**Current Limitations:**
1. **No Procedural Support:** There is no mechanism to inject dynamic math-based transformations (e.g., rotating a flaperon based on user input). Channels exclusively map their state (progress or value) to an `animTime` and require an `AnimationClip`.
2. **Pose Overwriting:** Because `Skeleton.updatePose` builds the entire pose array from a single clip and defaults to `restTransform` for missing joints, applying two different channels to the same skeleton sequentially will cause the second channel to completely overwrite the first channel's pose. 

## 2. Deep Dive: Procedural Animation in Industry Engines
Modern game engines solve this by decoupling the **Animation Graph (Pose Generation)** from the **Skeleton Evaluation (World Transform Calculation)**.

### Unity
- **LateUpdate Override:** The `Animator` component evaluates authored clips and sets bone transforms during the `Update` loop. Developers can attach a script that runs in `LateUpdate` to fetch a bone's `Transform` and apply a procedural rotation (e.g., `bone.localRotation *= Quaternion.Euler(...)`). This ensures procedural logic happens *after* the base animation.
- **Animation Rigging Package:** Uses a constraint-based system executed in a specific order in the animation pipeline, allowing IK, aim constraints, and procedural bone limits.

### Unreal Engine
- **AnimGraph:** Unreal uses a node-based Animation Blueprint. Authored animations are blended using Blend nodes.
- **Transform (Modify) Bone:** A specific node in the AnimGraph that takes a procedural input (like a variable driven by the player's joystick) and applies a Translation, Rotation, or Scale to a specific bone. The developer can choose to add to the existing pose or replace it in Component Space or Bone Space.

### Godot
- **SkeletonModifier3D:** Nodes that process the skeleton after the `AnimationTree` has evaluated clips.
- **Custom Poses:** Godot allows scripts to call `Skeleton3D.set_bone_custom_pose()`, which acts as an override applied on top of the authored animation track.

## 3. Recommended Approach for ToyFlightSimulator
To support procedural control surfaces (flaperons, ailerons) without breaking the existing clip-based system, we should adopt a simplified version of the "Transform Modify Bone" approach:

1. **Split Skeleton Pose Evaluation:**
   Separate `Skeleton.updatePose` into operations that mutate a persistent `localPose` state, and a final step that evaluates the world transforms.
2. **Introduce Procedural Channels:**
   Create a channel type that generates a transform from a mathematical range rather than sampling an `AnimationClip`.
3. **Pose Layering:**
   Allow the layer system to apply multiple channel updates (both clip-based and procedural) to the skeleton's local pose buffer before evaluating the final world matrices.

## 4. Answering the Question: Do I need a new type of channel?
**Yes.** The current `BinaryAnimationChannel` and `ContinuousAnimationChannel` are intrinsically tied to evaluating an `AnimationClip` using an `animTime`. 
While `ContinuousAnimationChannel` manages a value from -1.0 to 1.0 well, it doesn't know how to turn that value into a `float4x4` rotation matrix. We need a new type (e.g., `ProceduralRotationChannel`) that conforms to `ValuedAnimationChannel` but maps its value to an angle around a specific axis to generate a quaternion/matrix override for its masked joints. Alternatively, we could expand `ContinuousAnimationChannel` to accept a procedural closure `(Float) -> float4x4`, but a dedicated class is cleaner and more explicit.