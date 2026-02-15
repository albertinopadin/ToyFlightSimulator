# Animation Architecture Simplification Analysis

## Current Architecture
- **`AnimationChannel` Protocol:** Defines interface for an animation channel (`update`, `getAnimationTime`, `weight`, `mask`).
- **Concrete Channels:**
    - `BinaryAnimationChannel`: Finite State Machine (Active/Inactive) for things like Landing Gear.
    - `ContinuousAnimationChannel`: Value-based (0.0 - 1.0) for things like Flaps.
- **`AnimationChannelSet`:** A struct that groups multiple channels. It "hacks" its way into looking like a `BinaryAnimationChannel` by forwarding calls to its children and reading state from the first child.
- **`AnimationLayerSystem`:** Manages a collection of `AnimationChannel`s AND `AnimationChannelSet`s. Contains the logic for applying poses (`updatePoses`) which iterates skeletons/meshes and applies transforms based on `channel.mask` and `channel.animationClip`.
- **`AircraftAnimator`:** Manages the high-level logic. Currently has distinct code paths for `Channel` vs `ChannelSet`.
- **`F35AnimationConfig`:** Creates a `ChannelSet` containing multiple `BinaryAnimationChannel`s (one for each animation clip in the F-35 USD file).

## The Problem
1.  **Duplication:** `AnimationLayerSystem` and `AircraftAnimator` duplicate logic to handle `Channel` and `ChannelSet` separately.
2.  **Leaky Abstraction:** The concept of a "Set" leaks into the usage layer. The user shouldn't care if "Landing Gear" is one channel or ten.
3.  **Fragility:** `AnimationChannelSet` makes assumptions (all children are binary, all have same state) that are not enforced by types.

## Proposed Solution: Polymorphic `AnimationChannel`

The goal is to treat `AnimationChannelSet` as just another `AnimationChannel`. To do this, we need to move the "apply pose" logic from the manager into the channels themselves.

### 1. Update `AnimationChannel` Protocol
Add a requirement for the channel to apply its own pose to the model.

```swift
protocol AnimationChannel: AnyObject {
    // ... existing properties ...
    
    /// Apply the calculated pose to the model
    func applyPose(to model: UsdModel)
}
```

### 2. Create `BaseAnimationChannel` (or Protocol Extension)
Encapsulate the current `updatePoses` logic from `AnimationLayerSystem` into a reusable block. Since `Binary` and `Continuous` channels share this logic, we can put it in a protocol extension or a base class.

```swift
extension AnimationChannel {
    func applyPose(to model: UsdModel) {
        let animTime = getAnimationTime()
        // ... Logic from AnimationLayerSystem.updatePoses ...
        // Uses self.mask, self.animationClip, etc.
    }
}
```

### 3. Refactor `AnimationChannelSet`
Make it a class that conforms to `AnimationChannel` (and potentially `StatefulAnimationChannel` if we want to treat it as binary).

```swift
class AnimationChannelSet: AnimationChannel {
    let id: String
    var channels: [AnimationChannel]
    
    // ... Conformance ...
    
    func applyPose(to model: UsdModel) {
        // Delegate to children
        channels.forEach { $0.applyPose(to: model) }
    }
    
    func update(deltaTime: Float) {
        channels.forEach { $0.update(deltaTime: deltaTime) }
    }
    
    // ...
}
```

### 4. Simplify `AnimationLayerSystem`
It no longer needs to know about Sets or `updatePoses` implementation details.

```swift
class AnimationLayerSystem {
    var channels: [String: AnimationChannel] = [:]
    
    func update(deltaTime: Float) {
        // Update states
        channels.values.forEach { $0.update(deltaTime: deltaTime) }
        
        // Apply poses for dirty channels
        channels.values.filter { $0.isDirty }.forEach { channel in
            channel.applyPose(to: model)
            channel.clearDirty()
        }
    }
}
```

### 5. Simplify `AircraftAnimator`
Remove `landingGearChannelSet` property. Just use `channel("landingGear")`.
We might need a helper to cast it to `BinaryAnimationChannel` (or a protocol that both Binary and Set conform to) to call `activate()`.

## Detailed Plan

1.  **Refactor `AnimationChannel` Protocol:**
    - Add `func applyPose(to model: UsdModel)`.
2.  **Move Pose Logic:**
    - Extract `updatePoses` logic from `AnimationLayerSystem` to a default implementation in `AnimationChannel` (or a shared helper struct if protocol extension is too restrictive regarding property access).
    - *Note:* The logic requires access to `mask` and `animationClip`. These are in the protocol, so extension should work.
3.  **Update `AnimationChannelSet`:**
    - Change from `struct` to `class`.
    - Conform to `AnimationChannel`.
    - Implement `applyPose` (forward to children).
    - Implement properties `weight`, `mask` (can be dummy or union), `animationClip` (dummy).
    - Conform to `StatefulAnimationChannel` (optional, but helpful for `AircraftAnimator` to treat it like a binary channel). Or just keep the `activate/toggle` methods matching `BinaryAnimationChannel`.
4.  **Refactor `AnimationLayerSystem`:**
    - Remove `channelSets` storage.
    - Remove `updatePoses` method.
    - Update `registerChannel` to just take `AnimationChannel`.
    - Update `update` loop.
5.  **Refactor `F35AnimationConfig`:**
    - Ensure `createLandingGearChannelSet` returns the new `AnimationChannelSet` class.
6.  **Refactor `AircraftAnimator`:**
    - Remove `landingGearChannelSet`.
    - Update `toggleGear` etc. to look up channel by ID and cast to `BinaryAnimationChannel` (or a common protocol).
    - *Self-correction:* `AnimationChannelSet` is not a `BinaryAnimationChannel`. We might need a protocol `ToggleableAnimationChannel` that both conform to?
    - Or just let `AircraftAnimator` check: `if let ch = channel as? BinaryAnimationChannel { ... } else if let set = channel as? AnimationChannelSet { ... }`.
    - Better: `AnimationChannelSet` can wrap the "Binary" interface methods.

## Refinement on Channel Set Interface
If `AircraftAnimator` expects to call `toggle()`, `activate()`, etc., we should define a protocol for that.

```swift
protocol ToggleableAnimation {
    func toggle()
    func activate()
    func deactivate()
    var isActive: Bool { get }
    var isAnimating: Bool { get }
}
```

Make `BinaryAnimationChannel` and `AnimationChannelSet` conform to this.
Then `AircraftAnimator` holds `var landingGear: ToggleableAnimation?`.

But `AnimationChannelSet` is currently specific to this project's needs. We can just keep the methods on it and cast.

## Code Structure Changes
- **Delete:** `AnimationChannelSet.swift` (struct) -> Replace with `CompositeAnimationChannel.swift` (class) or keep name but change type.
- **Modify:** `AnimationChannel.swift` (Add `applyPose`).
- **Modify:** `AnimationLayerSystem.swift` (Simplify).
- **Modify:** `AircraftAnimator.swift` (Simplify).

This significantly reduces code in `AnimationLayerSystem` and removes the bifurcation in logic.
