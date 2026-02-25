# Procedural Animation Implementation Plan

## Overview
This plan outlines the steps to implement procedural animation (driven by player input) for aircraft control surfaces like flaperons, ailerons, and rudders in `ToyFlightSimulator`.

## The Problem
Currently, `Skeleton.updatePose` is destructive and monolithic. It reads from a single `AnimationClip` and calculates the full world-space pose hierarchy in one go. If a joint isn't in the clip, it defaults to the `restTransform`. This prevents blending or layering multiple channels (e.g., animating landing gear with a clip, and flaperons procedurally on the same skeleton) because the second update will overwrite the first.

## Phase 1: Skeleton Refactoring (Pose Accumulation)
To support multiple channels affecting the same skeleton, we must decouple local pose accumulation from world pose evaluation.

**Changes to `Skeleton.swift`:**
1. **Add Persistent Local State:**
   ```swift
   var localPoses: [float4x4] = []
   
   // In init, initialize it to restTransforms:
   self.localPoses = self.restTransforms
   ```

2. **Split `updatePose` into applying clips and evaluating hierarchy:**
   ```swift
   /// Applies an animation clip to the local poses, optionally filtered by a mask
   func apply(animationClip: AnimationClip, at time: Float, mask: AnimationMask) {
       let clampedTime = min(time, animationClip.duration)
       
       for index in 0..<jointPaths.count {
           let jointPath = jointPaths[index]
           if mask.contains(jointPath: jointPath) {
               // Only apply if the clip actually has an animation for this joint
               if let pose = animationClip.getPose(at: clampedTime * animationClip.speed, jointPath: jointPath) {
                   localPoses[index] = pose
               }
           }
       }
   }
   
   /// Applies a direct procedural rotation to specific joints
   func applyProceduralRotation(jointPathsToUpdate: [String], rotation: simd_quatf) {
       for index in 0..<jointPaths.count {
           if jointPathsToUpdate.contains(jointPaths[index]) {
               // We can either override or multiply with the restTransform
               let translation = Transform.translationMatrix(restTransforms[index].columns.3.xyz)
               let procRotation = float4x4(rotation)
               // Simple override assuming the rest transform just provides the pivot
               localPoses[index] = translation * procRotation
           }
       }
   }
   
   /// Calculates the final world matrices (called once per frame after all channels apply their poses)
   func evaluateWorldPoses() {
       var worldPose: [float4x4] = []
       for index in 0..<parentIndices.count {
           let parentIndex = parentIndices[index]
           let localMatrix = localPoses[index]
           if let parentIndex {
               worldPose.append(worldPose[parentIndex] * localMatrix)
           } else {
               worldPose.append(localMatrix)
           }
       }
       
       // ... existing bind and basis transform logic ...
       currentPose = worldPose
   }
   ```

## Phase 2: Create `ProceduralRotationChannel`
A new channel type is needed because the current channels are hardcoded to fetch a pose from an `AnimationClip` by time.

**`ProceduralRotationChannel.swift`:**
```swift
final class ProceduralRotationChannel: AnimationChannel, ValuedAnimationChannel {
    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip? = nil // Not used
    private(set) var isDirty: Bool = false
    
    // Value properties (-1.0 to 1.0 representing stick input)
    private(set) var value: Float
    private(set) var targetValue: Float
    var transitionSpeed: Float
    let range: (min: Float, max: Float)
    
    // Procedural specific properties
    let axis: float3
    let angleRange: (min: Float, max: Float) // In radians
    
    init(id: String, mask: AnimationMask, axis: float3, angleRange: (Float, Float), ...) {
        // Initialization...
    }
    
    func setValue(_ newValue: Float) {
        // Clamping and updating targetValue
    }
    
    func update(deltaTime: Float) {
        // Interpolate value towards targetValue
    }
    
    // Maps the normalized value to a specific rotation angle
    func getProceduralRotation() -> simd_quatf {
        let normalized = (value - range.min) / (range.max - range.min)
        let angle = angleRange.min + normalized * (angleRange.max - angleRange.min)
        return simd_quatf(angle: angle, axis: axis)
    }
    
    func getAnimationTime() -> Float { return 0 }
    func clearDirty() { isDirty = false }
}
```

## Phase 3: Update `AnimationLayerSystem`
Modify how `AnimationLayerSystem` processes channels so it supports the new accumulation logic.

**Changes to `AnimationLayerSystem.swift`:**
1. In `updatePoses(for:model:)`, check the channel type:
   ```swift
   if let clipChannel = channel as? BinaryAnimationChannel /* or Continuous */,
      let clip = channel.animationClip {
       model.skeletons[entry.path]?.apply(animationClip: clip, at: animTime, mask: channel.mask)
   } else if let procChannel = channel as? ProceduralRotationChannel {
       let rotation = procChannel.getProceduralRotation()
       model.skeletons[entry.path]?.applyProceduralRotation(
           jointPathsToUpdate: channel.mask.jointPaths, 
           rotation: rotation
       )
   }
   ```
2. In the main `update(deltaTime:)` loop, after processing all layers and updating all dirty channels (accumulating `localPoses`), explicitly call `skeleton.evaluateWorldPoses()` on all skeletons that were modified.

## Phase 4: Configure the F-22 Flaperons
Finally, update `F22AnimationConfig.swift` to use the new channel.

**`F22AnimationConfig.swift`:**
```swift
static func createFlaperonLayer(for model: UsdModel) -> AnimationLayer {
    // ... find flaperon joint paths ...
    
    // Example: Left Flaperon rotates on X axis from -20 deg to +20 deg
    let leftFlaperonChannel = ProceduralRotationChannel(
        id: "flaperon_left",
        mask: AnimationMask(jointPaths: [leftFlaperonJointPath]),
        axis: float3(1, 0, 0),
        angleRange: (-20 * .pi/180, 20 * .pi/180),
        range: (-1.0, 1.0),
        transitionSpeed: 5.0
    )
    
    // ... same for right flaperon ...
    
    return AnimationLayer(id: flaperonLayerID, channels: [leftFlaperonChannel, rightFlaperonChannel])
}
```

## Summary
By decoupling the local pose state from the final world matrix evaluation in `Skeleton`, we enable true animation blending and layering. The introduction of `ProceduralRotationChannel` provides a clean, decoupled way to map player input directly to bone rotations, bypassing the need for authored animation clips for control surfaces.