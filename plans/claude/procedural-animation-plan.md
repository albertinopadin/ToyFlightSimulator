# Plan: Procedural Animation for Aircraft Control Surfaces

## Overview

Add procedural (input-driven) bone animation support to the animation system, enabling aircraft control surfaces (flaperons, ailerons, rudders, horizontal stabilizers) to be animated from player input without pre-authored animation clips.

## Architecture

### New Pipeline Branch

```
EXISTING (clip-based):
  BinaryAnimationChannel/ContinuousAnimationChannel
    → getAnimationTime() → Float
    → skeleton.updatePose(at:clip:) → updates ALL joints from clip
    → skin.updatePalette()

NEW (procedural):
  ProceduralAnimationChannel
    → getJointOverrides() → [String: float4x4]
    → skeleton.applyProceduralOverrides(overrides:) → updates ONLY specified joints
    → skin.updatePalette()
```

### Evaluation Order

Clip-based channels are processed first (they call `skeleton.updatePose()` which writes the full pose). Procedural channels are processed second (they call `skeleton.applyProceduralOverrides()` which modifies only targeted joints in-place). This matches the industry standard: clips set the base pose, procedural overrides on top.

The layer system already processes layers in registration order. Landing gear layers are registered before control surface layers, so the natural order is correct.

---

## Step 1: Create `ProceduralAnimationChannel`

**New file**: `Animation/Layers/ProceduralAnimationChannel.swift`

This channel maps a continuous input value to per-joint rotation overrides.

```swift
/// Configuration for a single joint's procedural rotation
struct ProceduralJointConfig {
    /// Joint path in the skeleton (e.g., "/root/Armature/Armature/LeftFlaperon")
    let jointPath: String

    /// Axis of rotation in the joint's local space (e.g., [1, 0, 0] for pitch)
    let axis: float3

    /// Maximum deflection angle in radians when channel value is at max
    let maxDeflection: Float

    /// If true, the deflection is inverted (useful for left/right symmetry)
    let inverted: Bool
}

/// Animation channel for procedural (input-driven) bone animation.
/// Used for control surfaces that are rotated directly by player input
/// rather than sampled from pre-authored animation clips.
final class ProceduralAnimationChannel: AnimationChannel, ValuedAnimationChannel {
    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?  // Always nil for procedural channels

    private(set) var isDirty: Bool = false

    /// Current value (-1.0 to 1.0 typically, maps to deflection)
    private(set) var value: Float

    /// Target value for smooth transitions
    private(set) var targetValue: Float

    /// Transition speed (units per second)
    var transitionSpeed: Float

    /// Value range
    let range: (min: Float, max: Float)

    /// Per-joint rotation configurations
    let jointConfigs: [ProceduralJointConfig]

    init(
        id: String,
        mask: AnimationMask,
        range: (min: Float, max: Float) = (-1.0, 1.0),
        transitionSpeed: Float = 3.0,
        initialValue: Float = 0.0,
        jointConfigs: [ProceduralJointConfig]
    ) {
        self.id = id
        self.mask = mask
        self.range = range
        self.transitionSpeed = transitionSpeed
        self.jointConfigs = jointConfigs
        self.value = max(range.min, min(range.max, initialValue))
        self.targetValue = self.value
        self.isDirty = true
    }

    // MARK: - Control

    func setValue(_ newValue: Float) {
        let clamped = max(range.min, min(range.max, newValue))
        if abs(clamped - targetValue) > 0.001 {
            targetValue = clamped
            isDirty = true
        }
    }

    func setValueImmediate(_ newValue: Float) {
        let clamped = max(range.min, min(range.max, newValue))
        value = clamped
        targetValue = clamped
        isDirty = true
    }

    // MARK: - AnimationChannel Protocol

    func update(deltaTime: Float) {
        guard abs(value - targetValue) > 0.001 else { return }

        let maxChange = transitionSpeed * deltaTime
        let diff = targetValue - value

        if abs(diff) <= maxChange {
            value = targetValue
        } else {
            value += (diff > 0 ? maxChange : -maxChange)
        }
        isDirty = true
    }

    func getAnimationTime() -> Float {
        // Not used for procedural channels, but required by protocol.
        // Return 0 as a sentinel value.
        return 0
    }

    func clearDirty() {
        isDirty = false
    }

    // MARK: - Procedural Pose Computation

    /// Computes joint transform overrides based on current value.
    /// Returns a dictionary of jointPath → local transform matrix.
    func getJointOverrides() -> [String: float4x4] {
        var overrides: [String: float4x4] = [:]

        for config in jointConfigs {
            let deflection = config.inverted ? -value : value
            let angle = deflection * config.maxDeflection
            let rotation = float4x4(rotation: config.axis, angle: angle)
            overrides[config.jointPath] = rotation
        }

        return overrides
    }
}
```

**Key design decisions**:
- `jointConfigs` array lets one channel control multiple joints (e.g., left+right flaperons deflect together for roll, but left inverts)
- `getJointOverrides()` is the procedural equivalent of `getAnimationTime()` — it's what the layer system calls
- `getAnimationTime()` returns 0 as a no-op (protocol requirement)
- The rotation matrix is computed as a pure rotation around the configured axis — this gets multiplied with the joint's rest transform in the skeleton

---

## Step 2: Add Partial Joint Override to `Skeleton`

**Modified file**: `Animation/Skeleton.swift`

Add a new method that applies procedural overrides to specific joints without clobbering the rest of the pose:

```swift
/// Apply procedural transform overrides to specific joints.
/// Overrides are rotation matrices applied ON TOP of the joint's rest transform.
/// Only the specified joints are modified; all other joints retain their current pose.
///
/// - Parameter overrides: Dictionary of joint path → local rotation matrix to apply.
///   The override is combined with the rest transform: restTransform * override
func applyProceduralOverrides(_ overrides: [String: float4x4]) {
    guard !overrides.isEmpty else { return }

    // Build local poses: start from rest, apply overrides
    var localPose = [float4x4](repeating: .identity, count: jointPaths.count)

    for index in 0..<jointPaths.count {
        if let override = overrides[jointPaths[index]] {
            // Procedural joint: rest transform * rotation override
            localPose[index] = restTransforms[index] * override
        } else {
            // Non-overridden joint: use current local pose
            // We need to recover the local pose from currentPose.
            // Since currentPose stores world * bindInverse, and we need local,
            // we reconstruct from parent relationship.
            // HOWEVER: it's simpler and safer to just recompute from scratch
            // using rest transforms for non-overridden joints.
            localPose[index] = restTransforms[index]
        }
    }

    // Compute world poses from parent hierarchy
    var worldPose: [float4x4] = []
    for index in 0..<parentIndices.count {
        let parentIndex = parentIndices[index]
        let localMatrix = localPose[index]
        if let parentIndex {
            worldPose.append(worldPose[parentIndex] * localMatrix)
        } else {
            worldPose.append(localMatrix)
        }
    }

    // Apply bind inverse
    for index in 0..<worldPose.count {
        worldPose[index] *= bindTransforms[index].inverse
    }

    // Apply basis transform if needed
    if let basisTransform {
        let basisInverse = basisTransform.inverse
        for index in 0..<worldPose.count {
            worldPose[index] = basisTransform * worldPose[index] * basisInverse
        }
    }

    currentPose = worldPose
}
```

**Important note**: The naive approach above recomputes the entire skeleton from rest transforms + overrides. This is correct but has a limitation: it doesn't preserve poses set by a previous clip-based `updatePose()` call for non-overridden joints.

A more sophisticated approach (Phase 2 optimization) would be to store `localPose` as persistent state on the Skeleton, so that clip-based updates write to it, and procedural overrides can modify just their joints, then recompute world pose from the combined local poses. See "Future Optimization" at the end.

**Initial simple approach**: Since control surface bones and landing gear bones are non-overlapping, and we process clip-based channels before procedural channels, we can use a simpler design:
- After `updatePose(at:clip:)`, store the computed local poses
- `applyProceduralOverrides()` starts from those stored local poses and replaces only the override joints

```swift
class Skeleton {
    // ... existing properties ...

    /// Stored local poses from the last updatePose() call.
    /// Used by applyProceduralOverrides() to avoid clobbering clip-based poses.
    private var lastLocalPose: [float4x4] = []

    func updatePose(at currentTime: Float, animationClip: AnimationClip) {
        let time = min(currentTime, animationClip.duration)

        var localPose = [float4x4](repeating: .identity, count: jointPaths.count)
        for index in 0..<jointPaths.count {
            let pose = animationClip.getPose(at: time * animationClip.speed,
                                             jointPath: jointPaths[index]) ?? restTransforms[index]
            localPose[index] = pose
        }

        // Store local poses for procedural override support
        lastLocalPose = localPose

        // ... rest of existing code (world pose, bind inverse, basis transform) unchanged ...
    }

    func applyProceduralOverrides(_ overrides: [String: float4x4]) {
        guard !overrides.isEmpty else { return }

        // Start from stored local poses (preserves clip-based animation)
        // Fall back to rest transforms if no clip has been applied yet
        var localPose = lastLocalPose.isEmpty
            ? restTransforms
            : lastLocalPose

        // Apply overrides to targeted joints only
        for (jointPath, override) in overrides {
            guard let index = jointPaths.firstIndex(of: jointPath) else { continue }
            localPose[index] = restTransforms[index] * override
        }

        // Recompute world poses from modified local poses
        var worldPose: [float4x4] = []
        for index in 0..<parentIndices.count {
            let parentIndex = parentIndices[index]
            let localMatrix = localPose[index]
            if let parentIndex {
                worldPose.append(worldPose[parentIndex] * localMatrix)
            } else {
                worldPose.append(localMatrix)
            }
        }

        for index in 0..<worldPose.count {
            worldPose[index] *= bindTransforms[index].inverse
        }

        if let basisTransform {
            let basisInverse = basisTransform.inverse
            for index in 0..<worldPose.count {
                worldPose[index] = basisTransform * worldPose[index] * basisInverse
            }
        }

        currentPose = worldPose
    }
}
```

This way, if landing gear `updatePose()` runs first and sets all joints (including flaperon joints at rest), then `applyProceduralOverrides()` starts from those stored local poses, replaces only flaperon joints with the procedural rotation, and recomputes the full skeleton. Landing gear joint poses are preserved.

---

## Step 3: Modify `AnimationLayerSystem.updatePoses()`

**Modified file**: `Animation/Layers/AnimationLayerSystem.swift`

Add a branch for procedural channels:

```swift
private func updatePoses(for channel: AnimationChannel, model: UsdModel) {
    // Branch: procedural channels use direct joint overrides
    if let proceduralChannel = channel as? ProceduralAnimationChannel {
        updateProceduralPoses(for: proceduralChannel, model: model)
        return
    }

    // Existing clip-based path (unchanged)
    let animTime = channel.getAnimationTime()
    // ... rest of existing code ...
}

/// Update skeleton poses for a procedural channel using direct joint overrides.
private func updateProceduralPoses(for channel: ProceduralAnimationChannel, model: UsdModel) {
    let overrides = channel.getJointOverrides()

    guard let mapping = channelMappings[channel.id] else { return }

    // Apply procedural overrides to affected skeletons
    for entry in mapping.skeletonEntries {
        model.skeletons[entry.path]?.applyProceduralOverrides(overrides)
    }

    // Update affected mesh skins (same as clip-based path)
    for meshIndex in mapping.affectedMeshIndices {
        let mesh = model.meshes[meshIndex]
        if let skeleton = mapping.meshSkeletonLookup[meshIndex] {
            mesh.skin?.updatePalette(skeleton: skeleton)
        } else if let fallback = singleSkeleton {
            mesh.skin?.updatePalette(skeleton: fallback)
        }
    }
}
```

Also modify `buildMapping()` to handle procedural channels that have no animation clip:

```swift
private func buildMapping(for channel: AnimationChannel, model: UsdModel) -> ChannelMapping {
    let mask = channel.mask

    var skeletonEntries: [(path: String, clip: AnimationClip)] = []
    var affectedSkeletonPaths: Set<String> = []

    let isProcedural = channel is ProceduralAnimationChannel

    for (skeletonPath, skeleton) in model.skeletons {
        let hasAffectedJoints = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }

        if hasAffectedJoints || mask.jointPaths.isEmpty {
            affectedSkeletonPaths.insert(skeletonPath)

            if isProcedural {
                // Procedural channels don't need a clip, but ChannelMapping
                // requires one. We store a dummy entry with the path.
                // The updateProceduralPoses() method doesn't use the clip.
                // Alternative: make clip optional in skeletonEntries.
            }

            let clip = channel.animationClip
                ?? model.animationClips[model.skeletonAnimationMap[skeletonPath] ?? ""]
                ?? model.animationClips.values.first

            if let clip = clip {
                skeletonEntries.append((path: skeletonPath, clip: clip))
            } else if isProcedural {
                // For procedural channels, we still need the skeleton path
                // even without a clip. Refactor ChannelMapping to support this.
            }
        }
    }
    // ... rest unchanged ...
}
```

**Note**: `ChannelMapping.skeletonEntries` currently requires a clip. For procedural channels, we have two options:
1. Make the clip optional: `let skeletonEntries: [(path: String, clip: AnimationClip?)]`
2. Create a separate `ProceduralChannelMapping` struct with just skeleton paths

Option 1 is simpler and minimally invasive. The clip-based path would just `guard let clip = entry.clip` and the procedural path ignores it.

---

## Step 4: Modify `ChannelMapping`

```swift
struct ChannelMapping {
    /// Skeleton paths affected by this channel, paired with the clip to use (nil for procedural)
    let skeletonEntries: [(path: String, clip: AnimationClip?)]

    /// Mesh indices that need transform and/or skin updates
    let affectedMeshIndices: [Int]

    /// For each affected mesh index, the skeleton (if any) that drives its skin
    let meshSkeletonLookup: [Int: Skeleton]
}
```

Update the existing `updatePoses()` call site to handle optional clip:

```swift
for entry in mapping.skeletonEntries {
    guard let clip = entry.clip else { continue }  // Skip for procedural
    model.skeletons[entry.path]?.updatePose(at: animTime, animationClip: clip)
}
```

---

## Step 5: Update `F22AnimationConfig`

**Modified file**: `Animation/Configs/F22AnimationConfig.swift`

Replace the ContinuousAnimationChannel-based flaperon layer with ProceduralAnimationChannel:

```swift
static func createFlaperonLayer(for model: UsdModel) -> AnimationLayer {
    // Deflection angle in radians (e.g., 30 degrees)
    let maxDeflection: Float = .pi / 6  // 30 degrees

    // Rotation axis for flaperons (likely X-axis in bone-local space,
    // but verify against the model's bone orientation)
    let rotationAxis: float3 = float3(1, 0, 0)

    let leftConfig = ProceduralJointConfig(
        jointPath: "/root/Armature/Armature/LeftFlaperon",  // Verify exact path
        axis: rotationAxis,
        maxDeflection: maxDeflection,
        inverted: false
    )

    let rightConfig = ProceduralJointConfig(
        jointPath: "/root/Armature/Armature/RightFlaperon",  // Verify exact path
        axis: rotationAxis,
        maxDeflection: maxDeflection,
        inverted: true  // Opposite deflection for roll
    )

    let jointPaths = [leftConfig.jointPath, rightConfig.jointPath]
    let mask = AnimationMask(jointPaths: jointPaths)

    let channel = ProceduralAnimationChannel(
        id: "flaperons",
        mask: mask,
        range: (-1.0, 1.0),
        transitionSpeed: 3.0,  // Fast response for control surfaces
        initialValue: 0.0,
        jointConfigs: [leftConfig, rightConfig]
    )

    return AnimationLayer(id: flaperonLayerID, channels: [channel])
}
```

**Note**: The exact joint paths, rotation axis, and whether left/right inversion is correct will need to be verified against the actual model. The bone local space orientation may differ from expected — you may need to experiment with axis and inversion to get the correct visual result.

---

## Step 6: Update `AircraftAnimator.rollFlaperons()`

**Modified file**: `Animation/Animators/AircraftAnimator.swift`

```swift
func rollFlaperons(value: Float) {
    guard let layer = flaperonLayer else {
        print("[AircraftAnimator] No flaperon layer registered")
        return
    }

    for case let channel as ProceduralAnimationChannel in layer.channels {
        channel.setValue(value)
    }
}
```

---

## Step 7: Add `float4x4(rotation:angle:)` Utility

If not already available, add a convenience initializer for creating a rotation matrix from an axis and angle:

```swift
extension float4x4 {
    /// Creates a rotation matrix from an axis and angle (radians)
    init(rotation axis: float3, angle: Float) {
        let normalizedAxis = normalize(axis)
        let quaternion = simd_quatf(angle: angle, axis: normalizedAxis)
        self = float4x4(quaternion)
    }
}
```

Check if this already exists in the Math utilities before adding.

---

## Summary of Files Changed

| File | Change Type | Description |
|------|------------|-------------|
| `Animation/Layers/ProceduralAnimationChannel.swift` | **NEW** | New channel type for input-driven bone animation |
| `Animation/Skeleton.swift` | MODIFY | Add `lastLocalPose` storage + `applyProceduralOverrides()` method |
| `Animation/Layers/AnimationLayerSystem.swift` | MODIFY | Add procedural branch in `updatePoses()`, update `buildMapping()` |
| `Animation/Layers/AnimationLayerSystem.swift` | MODIFY | Make `ChannelMapping.skeletonEntries.clip` optional |
| `Animation/Configs/F22AnimationConfig.swift` | MODIFY | Replace ContinuousAnimationChannel with ProceduralAnimationChannel for flaperons |
| `Animation/Animators/AircraftAnimator.swift` | MODIFY | Update `rollFlaperons()` to use ProceduralAnimationChannel |
| Math utilities (if needed) | MODIFY | Add `float4x4(rotation:angle:)` if not present |

---

## Future Extensions

Once flaperons work, the same `ProceduralAnimationChannel` pattern can be used for:
- **Ailerons**: Same as flaperons but potentially different joint paths and deflection axis
- **Rudders**: Yaw input → rudder deflection (likely Y-axis rotation)
- **Horizontal stabilizers**: Pitch input → elevator deflection (likely X-axis rotation)
- **Multiple inputs per surface**: Some surfaces respond to multiple inputs (e.g., flaperons respond to both roll AND flap deployment)

For multi-input surfaces, a future enhancement would be an `AdditiveProceduralChannel` that sums contributions from multiple input sources before computing the final rotation.

## Future Optimization: Persistent Local Pose

The current design recomputes the full skeleton hierarchy in `applyProceduralOverrides()`. For models with very large skeletons, a future optimization would be to:
1. Store `localPose` as persistent state on `Skeleton`
2. Have `updatePose()` write to `localPose` and then compute world pose
3. Have `applyProceduralOverrides()` modify just the targeted entries in `localPose` and recompute world pose
4. Add a `recomputeWorldPose()` helper that both methods call

This eliminates redundant rest-transform lookups and makes the two systems truly composable. The current design is simpler and correct for the F-22 use case where the skeleton is small.
