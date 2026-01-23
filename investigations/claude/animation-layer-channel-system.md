# Animation Layer/Channel System Research

**Date**: January 2026
**Status**: Research Complete
**Author**: Architecture Investigation

---

## Problem Statement

The current F-35 animation implementation has a single hardcoded gear state machine in `AircraftAnimator`. We need a flexible **animation layer/channel system** that allows:

1. Independent control of each animatable part (landing gear, flaps, ailerons, rudder, canopy, etc.)
2. Easy addition of channels based on aircraft complexity
3. Efficient partial updates (only animate what changed)
4. Data-driven configuration per aircraft model

### Current Architecture Limitations

| Issue | Location | Impact |
|-------|----------|--------|
| Single gear state machine | `AircraftAnimator.swift:46-52` | Cannot add more animatable parts without code changes |
| Updates ALL skeletons | `AircraftAnimator.swift:203-238` | Inefficient; no partial updates |
| No joint-to-channel mapping | N/A | Cannot isolate which bones belong to which animation |
| F35-specific code in generic class | `AircraftAnimator.swift` | Not reusable for other aircraft |

---

## Industry Research: Animation Layer Systems

### Unity's Animation Layers

Unity uses **Animation Layers** to manage complex state machines for different body parts. Key concepts:

| Component | Purpose |
|-----------|---------|
| **Animation Layer** | Independent state machine controlling a subset of bones |
| **Avatar Mask** | Defines which bones a layer can animate |
| **Layer Weight** | Controls influence (0.0 = none, 1.0 = full) |
| **Blending Mode** | Override (replace) or Additive (combine) |

**Layer Weight Formula (Override mode)**:
```
NextValue = CurrentValue + NewWeight * (NewValue - CurrentValue)
```

**Avatar Mask Behavior**: Essentially an on/off switch per bone - either the layer can animate that bone or it cannot.

**Key Quote from Unity Documentation**:
> "Unity uses Animation Layers for managing complex state machines for different body parts. For example, you might have a lower-body layer for walking-Loss, jumping, and an upper-body layer for throwing objects / shooting."

**Sources**:
- [Unity Animation Layers](https://docs.unity3d.com/Manual/AnimationLayers.html)
- [Unity Avatar Mask](https://docs.unity3d.com/2022.3/Documentation/Manual/class-AvatarMask.html)
- [Diego Giacomelli's Avatar Mask Tutorial](https://diegogiacomelli.com.br/unity-avatar-mask-and-animation-layers/)

### Unreal Engine's Animation Montages and Slots

Unreal uses **Animation Slots** and **Layered Blend Per Bone** nodes:

| Component | Purpose |
|-----------|---------|
| **Animation Slot** | Named channel for playing montages |
| **Slot Group** | Organizes slots; montages in same group interrupt each other |
| **Layered Blend Per Bone** | Blends animations starting from a specific bone |
| **Blend Mask** | Pre-defined per-bone weight definitions |
| **Branch Filter** | Specifies blend starting bone and depth |

**Blend Mask Features**:
- Define weight influences per bone (0.0 to 1.0)
- Exclude lower-body bones for upper-body animations
- Can specify blend depth (how many children bones to include)

**Key Quote**:
> "A common use-case for using Blend Masks is to exclude lower-body bones so that animation plays only on the upper-body, regardless of the full-body state."

**Sources**:
- [Unreal Animation Slots](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-slots-in-unreal-engine)
- [Using Layered Animations](https://docs.unrealengine.com/4.26/en-US/AnimatingObjects/SkeletalMeshAnimation/AnimHowTo/AdditiveAnimations/)
- [Blend Masks and Blend Profiles](https://dev.epicgames.com/documentation/en-us/unreal-engine/blend-masks-and-blend-profiles-in-unreal-engine)

### Bevy Engine (Rust)

Bevy implemented animation layers in 2024 with these patterns:

| Component | Purpose |
|-----------|---------|
| **Animation Graph Masks** | Sets of bones that nodes cannot animate |
| **Mask Groups** | Named collections of bones, specific to each graph |
| **Add Nodes** | Combine animations without normalizing weights |
| **Blend Nodes** | Standard weighted blending |

**Key Insight**:
> "A mask is a set of animation targets (bones) that neither a node nor its descendants are allowed to animate"

Separating "blend weight" from "target bones" provides cleaner abstraction than monolithic layering systems.

**Source**: [Bevy Animation Layers Issue #14395](https://github.com/bevyengine/bevy/issues/14395)

### Common Pattern: 3D Animation Engine Architecture

From the classic article "Architecting a 3D Animation Engine":

**Channel Capture System**:
> "The engine responds to a capture request by stopping the animation for that channel only. For example, with 16 joints being animated with rotation information every frame, capturing joint 10 means that joint 10 will no longer be updated with rotation information every frame, but the other 15 joints will continue to be updated."

This allows:
- Algorithmically controlling one part while others animate normally
- Looking in a direction while running (capture neck, let body run)
- Independent channel states without full pose recalculation

**Source**: [Architecting a 3D Animation Engine (Game Developer)](https://www.gamedeveloper.com/programming/architecting-a-3d-animation-engine)

---

## Current Codebase Analysis

### Existing Animation Data Structures

**UsdModel.swift** stores animation data:
```swift
var skeletons: [String: Skeleton] = [:]           // Keyed by path
var meshSkeletonMap: [Int: String] = [:]          // Mesh index -> skeleton path
var animationClips: [String: AnimationClip] = []  // Keyed by clip name
var skeletonAnimationMap: [String: String] = []   // Skeleton path -> clip name
```

**AnimationClip.swift** organizes keyframes per joint:
```swift
var jointAnimation: [String: Animation?] = [:]    // Keyed by joint path
```

**Key Insight**: Joint animations are already keyed by path. We can selectively apply animation to specific joints without modifying the clip structure.

### Current AircraftAnimator Structure

```
AircraftAnimator
├── model: UsdModel (weak ref)
├── playbackState: AnimationPlaybackState
├── currentTime: Float
├── gearState: GearState
├── gearAnimationProgress: Float
├── gearAnimationDuration: Float
└── methods:
    ├── extendGear() / retractGear() / toggleGear()
    ├── updateGearStateMachine(deltaTime:)
    ├── didUpdateGearStateMachine()  // Override point
    └── updateSkeletonPoses()        // Updates ALL poses
```

**Problems**:
1. Only ONE animatable subsystem (gear)
2. `updateSkeletonPoses()` updates all skeletons/meshes regardless of what changed
3. F35Animator subclass pattern doesn't scale for multiple channels
4. No concept of which joints belong to gear vs. other systems

---

## Aircraft Animation Channel Requirements

### Channel Types

**Binary Channels** (Two-state: fully extended/retracted):
| Channel | Example Aircraft |
|---------|-----------------|
| Landing Gear (main) | F-35, F-22, F-18 |
| Landing Gear (nose) | All |
| Canopy | F-35, F-22, F-16 |
| Air Brake / Speed Brake | F-15, F-18 |
| Refueling Probe | F-18, Tornado |
| Arrestor Hook | F-18, F-35C |
| APU Doors | F-35 |
| Weapon Bay Doors | F-22, F-35 |

**Continuous Channels** (Variable position):
| Channel | Range | Example |
|---------|-------|---------|
| Flaps | 0-100% | All |
| Ailerons | -100% to +100% | All |
| Elevators | -100% to +100% | All |
| Rudder | -100% to +100% | All |
| Horizontal Stabilizer | -100% to +100% | F-18, F-22 |
| Thrust Vector | -100% to +100% | F-22 |
| Variable Geometry Wings | 0-100% | F-14, F-111 |

**Triggered Channels** (One-shot sequences):
| Channel | Description |
|---------|-------------|
| Weapon Release | Open door, release, close door |
| Ejection Sequence | Multiple stages |
| Startup Sequence | Multiple systems |

### Per-Aircraft Complexity

| Aircraft | Channels |
|----------|----------|
| F-35 | Landing gear, weapon bay doors, VTOL nozzle |
| F-22 | Landing gear, weapon bay doors, thrust vectoring |
| F-18 | Landing gear, hook, flaps, LEX fences |
| F-14 | Landing gear, variable geometry wings |
| F-16 | Landing gear (simple) |

---

## Proposed Architecture

### Core Abstractions

```
AnimationChannel (protocol)
├── id: String
├── mask: AnimationMask
├── weight: Float
├── isDirty: Bool
├── update(deltaTime:)
├── getAnimationTime() -> Float

AnimationMask (struct)
├── jointPaths: Set<String>
├── meshIndices: Set<Int>
├── contains(jointPath:) -> Bool
├── contains(meshIndex:) -> Bool

AnimationLayerSystem (class)
├── model: UsdModel
├── channels: [String: AnimationChannel]
├── registerChannel(_:)
├── channel(_:) -> AnimationChannel?
├── update(deltaTime:)
```

### Channel Implementations

**BinaryAnimationChannel** - For two-state animations:
```swift
class BinaryAnimationChannel: AnimationChannel {
    enum State {
        case inactive      // Fully retracted/closed
        case activating    // Transitioning to active
        case active        // Fully extended/open
        case deactivating  // Transitioning to inactive
    }

    var state: State
    var progress: Float       // 0.0 (inactive) to 1.0 (active)
    var duration: Float       // Transition time in seconds
    var animationClip: AnimationClip?
    var timeRange: (start: Float, end: Float)?

    func activate()           // inactive -> activating
    func deactivate()         // active -> deactivating
    func toggle()             // Convenience method
}
```

**ContinuousAnimationChannel** - For variable-position animations:
```swift
class ContinuousAnimationChannel: AnimationChannel {
    var value: Float              // Current value (-1.0 to 1.0 or 0.0 to 1.0)
    var targetValue: Float        // Target value for smooth transitions
    var transitionSpeed: Float    // Units per second
    var range: (min: Float, max: Float)

    func setValue(_ value: Float, immediate: Bool = false)
}
```

### Component Diagram

```
F35 (Aircraft/GameObject)
│
├── model: UsdModel                     ← Pure data container
│   ├── skeletons                       (skeleton hierarchy)
│   ├── animationClips                  (keyframe data)
│   ├── meshSkeletonMap                 (mesh-to-skeleton bindings)
│   └── skins                           (skinning data)
│
└── animationSystem: AnimationLayerSystem   ← NEW
    ├── channels
    │   ├── "landingGear": BinaryAnimationChannel
    │   │   ├── mask: {MainGearL, MainGearR, NoseGear}
    │   │   ├── state: .active
    │   │   └── progress: 1.0
    │   │
    │   ├── "flaps": ContinuousAnimationChannel (future)
    │   │   ├── mask: {FlapL, FlapR}
    │   │   └── value: 0.0
    │   │
    │   └── "canopy": BinaryAnimationChannel (future)
    │       ├── mask: {Canopy}
    │       └── state: .inactive
    │
    └── update(deltaTime:)              ← Updates only dirty channels
```

### Update Flow

```
1. Input: User presses gear toggle
2. F35.doUpdate() detects input
3. animationSystem.channel("landingGear")?.toggle()
4. BinaryAnimationChannel.toggle() changes state, marks dirty
5. Each frame: animationSystem.update(deltaTime)
6. For each dirty channel:
   a. channel.update(deltaTime) - advance state machine
   b. Get animation time from channel progress
   c. Get affected joints from channel mask
   d. Update ONLY those skeleton joints
   e. Update ONLY affected mesh skins
7. Clear dirty flags
```

### Selective Pose Update (Key Optimization)

```swift
func updateChannelPoses(_ channel: AnimationChannel, at time: Float) {
    guard let model = model else { return }
    let mask = channel.mask

    for (skeletonPath, skeleton) in model.skeletons {
        // Filter to only joints in the channel mask
        let affectedJoints = skeleton.jointPaths.filter { mask.contains($0) }

        if !affectedJoints.isEmpty {
            // Update only affected joints
            updatePartialPose(
                skeleton: skeleton,
                joints: affectedJoints,
                at: time,
                clip: channel.animationClip
            )
        }
    }

    // Update only affected mesh skins
    for meshIndex in mask.meshIndices {
        if let skeletonPath = model.meshSkeletonMap[meshIndex],
           let skeleton = model.skeletons[skeletonPath] {
            model.meshes[meshIndex].skin?.updatePalette(skeleton: skeleton)
        }
    }
}
```

---

## Comparison with Industry Solutions

| Feature | Unity | Unreal | Proposed System |
|---------|-------|--------|-----------------|
| Layer/Channel Abstraction | Animation Layer | Animation Slot | AnimationChannel |
| Bone Masking | Avatar Mask | Blend Mask | AnimationMask |
| Weight Blending | 0.0-1.0 per layer | Per-bone weights | Per-channel weight |
| State Machine | Animator Controller | State Machine | Per-channel state |
| Override Mode | Yes | Yes | Yes (default) |
| Additive Mode | Yes | Yes | Future enhancement |
| Per-bone Weights | No (on/off only) | Yes | Future enhancement |
| Data-driven Config | Asset files | Blueprint | Swift structs |

---

## Benefits of Proposed Architecture

1. **Modularity**: Each animation subsystem is independent
2. **Efficiency**: Only update changed channels and affected bones
3. **Extensibility**: Easy to add new channels via configuration
4. **Reusability**: Same architecture works for all aircraft
5. **Testability**: Channels can be unit tested in isolation
6. **Industry Alignment**: Follows Unity/Unreal proven patterns

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Complex joint path management | Use configuration files/structs per aircraft |
| Performance with many channels | Dirty flag system limits updates |
| Blending conflicts between channels | Override mode by default; document joint ownership |
| USD animation clip compatibility | Test with existing F-35 model; adapt as needed |

---

## References

- [Unity Animation Layers](https://docs.unity3d.com/Manual/AnimationLayers.html)
- [Unity Avatar Mask](https://docs.unity3d.com/2022.3/Documentation/Manual/class-AvatarMask.html)
- [Unreal Layered Animations](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-layered-animations-in-unreal-engine)
- [Unreal Animation Slots](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-slots-in-unreal-engine)
- [Bevy Animation Layers](https://github.com/bevyengine/bevy/issues/14395)
- [Architecting a 3D Animation Engine](https://www.gamedeveloper.com/programming/architecting-a-3d-animation-engine)
- [Skeletal Animation Implementation](https://vlad.website/game-engine-skeletal-animation/)
- [Animancer Layers Documentation](https://kybernetik.com.au/animancer/docs/manual/blending/layers/)
