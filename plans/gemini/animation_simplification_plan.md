# Animation Architecture Simplification Plan

## Objective
Simplify the animation system by consolidating `AnimationChannel` and `AnimationChannelSet` into a unified polymorphic hierarchy. This will remove duplicated logic in `AnimationLayerSystem` and `AircraftAnimator`, making the code easier to maintain and extend.

## Architecture Changes

1.  **New Protocol: `ToggleableAnimationChannel`**
    - Defines the interface for discrete state animations (Landing Gear, Canopy, etc.).
    - Inherits from `AnimationChannel`.
    - Methods: `activate()`, `deactivate()`, `toggle()`.
    - Properties: `isActive`, `isAnimating`, `state`.

2.  **Update `AnimationChannel` Protocol**
    - Add `func applyPose(to model: UsdModel)`.
    - Create a default implementation in a protocol extension that contains the logic currently in `AnimationLayerSystem.updatePoses`.

3.  **Refactor `BinaryAnimationChannel`**
    - Conform to `ToggleableAnimationChannel`.
    - Use the default `applyPose` implementation (no changes needed for logic, just conformance).

4.  **Refactor `AnimationChannelSet`**
    - Convert from `struct` to `class`.
    - Conform to `ToggleableAnimationChannel`.
    - **Crucial:** Implement `applyPose(to:)` to iterate over children and call *their* `applyPose`.
    - Implement `ToggleableAnimationChannel` methods by forwarding to children (or managing internal state if preferred, but forwarding matches current behavior).

5.  **Simplify `AnimationLayerSystem`**
    - Remove `channelSets` dictionary and `registerChannelSet`.
    - Remove `updatePoses` private method.
    - In `update(deltaTime:)`, iterate channels and call `channel.applyPose(to: model)` for dirty channels.

6.  **Simplify `AircraftAnimator`**
    - Change `landingGearChannelSet` property to `var landingGearChannel: ToggleableAnimationChannel?`.
    - Remove specific `ChannelSet` handling.

## Step-by-Step Implementation

1.  **Define Protocols & Extensions** (`AnimationChannel.swift`)
    - Add `applyPose` to `AnimationChannel`.
    - Extract logic from `AnimationLayerSystem.updatePoses` into `AnimationChannel` extension.
    - Define `ToggleableAnimationChannel` protocol.

2.  **Update `BinaryAnimationChannel`** (`BinaryAnimationChannel.swift`)
    - Adopt `ToggleableAnimationChannel`.

3.  **Refactor `AnimationChannelSet`** (`AnimationChannelSet.swift`)
    - Change to `class`.
    - Adopt `ToggleableAnimationChannel`.
    - Implement `applyPose` (delegation).
    - Implement toggle/activate logic (delegation).

4.  **Refactor `AnimationLayerSystem`** (`AnimationLayerSystem.swift`)
    - Remove `channelSets` storage.
    - Simplify `update` method.
    - Remove `updatePoses`.

5.  **Update `AircraftAnimator`** (`AircraftAnimator.swift`)
    - Update type of `landingGearChannel` or `landingGearChannelSet`.
    - Remove redundant methods.

6.  **Verification**
    - Build project.
    - Ensure F-35 landing gear still works (conceptually, I cannot run it).
    - Ensure no compilation errors.

## Risks & Mitigations
- **Logic Transfer:** Moving `updatePoses` logic might break if it relies on private `AnimationLayerSystem` state.
    - *Check:* It relies on `model.skeletons`, `model.meshes`. These are available via the `model` parameter passed to `applyPose`. It also relies on `debugLogging` which is on `AnimationLayerSystem`.
    - *Mitigation:* We can pass `debugLogging` bool to `applyPose` or just remove debug prints in the low-level method, or make `applyPose` take a context object. For simplicity, I'll remove non-critical debug prints or keep them generic.
- **Access Control:** `UsdModel` properties might be internal/private?
    - *Check:* They seem accessible (internal to the module).

## Future Work
- Consolidate `F35AnimationConfig` to not need to iterate all clips if not necessary (optimization).
