# Plan: Animation Channel Simplification

## Goal
Same functionality, less code. Eliminate `AnimationChannelSet` by making channels natively support multiple animation targets. Remove dead code and vestigial legacy protocol.

## Key Insight
A channel set is really just one state machine driving multiple (clip, mask) pairs. The state/progress is identical across all channels in a set. Move the targets INTO the channel, delete the set.

---

## Step 1: Introduce AnimationTarget

**File: AnimationChannel.swift**

Add a struct that pairs an animation clip with its mask:

```swift
struct AnimationTarget {
    let clip: AnimationClip
    let mask: AnimationMask
}
```

Update `AnimationChannel` protocol:
- Replace `var animationClip: AnimationClip? { get set }` and `var mask: AnimationMask { get }` with `var targets: [AnimationTarget] { get }`
- Keep: `id`, `weight`, `isDirty`, `update(deltaTime:)`, `getAnimationTime()`, `clearDirty()`
- Remove: `StatefulAnimationChannel` and `ValuedAnimationChannel` sub-protocols (unused in practice, consumers cast to concrete types)

## Step 2: Update BinaryAnimationChannel

**File: BinaryAnimationChannel.swift**

- Replace `let mask: AnimationMask` and `var animationClip: AnimationClip?` with `let targets: [AnimationTarget]`
- If a convenience init with a single clip+mask is useful, keep it (creates a one-element targets array)
- `transitionDuration` stays. For multi-target, use the max duration across targets, or accept it as a parameter (current behavior: each channel had its own duration from its clip, but they were all the same in practice)
- Remove excessive `print()` calls from `activate()/deactivate()/toggle()` (keep state-completion prints if desired)
- Everything else unchanged (state machine, progress, toggle, etc.)

## Step 3: Update ContinuousAnimationChannel

**File: ContinuousAnimationChannel.swift**

- Same change: replace single clip+mask with `targets: [AnimationTarget]`
- Everything else unchanged

## Step 4: Delete AnimationChannelSet.swift

The whole file goes away. Its responsibilities are absorbed by the multi-target channel.

## Step 5: Simplify AnimationLayerSystem

**File: AnimationLayerSystem.swift**

- Remove `channelSets` dict and `channelSetEvaluationOrder`
- Keep only `channels` dict and `evaluationOrder`
- Remove `registerChannelSet()`, `channelSet()`, `hasChannelSet()`
- Delete all commented-out code

Update `update(deltaTime:)`:
```swift
func update(deltaTime: Float) {
    guard let model = model else { return }
    for id in evaluationOrder {
        guard let channel = channels[id] else { continue }
        channel.update(deltaTime: deltaTime)
        guard channel.isDirty else { continue }
        updatePoses(for: channel, model: model)
        channel.clearDirty()
    }
}
```

Update `updatePoses(for:model:)` to iterate `channel.targets`:
```swift
private func updatePoses(for channel: AnimationChannel, model: UsdModel) {
    let animTime = channel.getAnimationTime()
    for target in channel.targets {
        // Find skeletons affected by this target's mask
        // Update skeleton poses with this target's clip at animTime
        // Update mesh skins
    }
}
```

Update `forceUpdateAllPoses()` and `resetAllChannels()` to use channels only.

## Step 6: Simplify AircraftAnimator

**File: AircraftAnimator.swift**

- Remove `AnimationController` protocol conformance
- Remove `playbackState`, `currentTime`, `playbackSpeed`, `shouldLoop`, `currentClipName`
- Remove `play()`, `pause()`, `stop()` methods
- Remove `registerChannelSet()` pass-through
- Change `landingGearChannelSet` to `landingGearChannel` returning `BinaryAnimationChannel?`
- Update gear API to use the channel directly (no more `channelSet.state` etc.)
- Keep: `model`, `layerSystem`, `init(model:)`, `setupChannels()`, `registerChannel()`, `channel()`, `update()`, gear control methods

## Step 7: Delete AnimationController.swift

The protocol and `AnimationPlaybackState` enum are no longer used by anything.

## Step 8: Update F35AnimationConfig

**File: F35AnimationConfig.swift**

- Delete `createLandingGearChannel()` (the old single-channel version)
- Rename `createLandingGearChannelSet()` to `createLandingGearChannel()` - now returns a single `BinaryAnimationChannel` with multiple targets
- Delete `createAllChannelSets()`, replace with `createAllChannels()` returning `[AnimationChannel]`
- Remove all commented-out code

The factory logic becomes:
```swift
static func createLandingGearChannel(for model: UsdModel) -> BinaryAnimationChannel {
    var targets: [AnimationTarget] = []
    for clip in model.animationClips.values {
        // Find skeleton for this clip
        // Find mesh indices for that skeleton
        // Create AnimationTarget(clip: clip, mask: AnimationMask(...))
        targets.append(...)
    }
    let duration = targets.map { $0.clip.duration }.max() ?? 4.0
    return BinaryAnimationChannel(
        id: "landingGear",
        targets: targets,
        transitionDuration: duration,
        initialState: .active
    )
}
```

## Step 9: Update F35Animator

**File: F35Animator.swift**

- Change `setupChannels()` to call `F35AnimationConfig.createAllChannels()` and `registerChannel()` for each

## Step 10: Update AnimationMask.swift

**File: AnimationMask.swift**

- Remove the `print()` in the `init(jointPaths:meshIndices:)` initializer
- Everything else stays as-is

## Step 11: Verify No Other References

- Check that `Aircraft.swift` and `F35.swift` don't need changes (they shouldn't - they only interact via `AircraftAnimator`)
- Check nothing else references `AnimationChannelSet` or `AnimationController`

---

## Files Changed Summary

| File | Action |
|------|--------|
| AnimationChannel.swift | Rewrite: add `AnimationTarget`, simplify protocol |
| BinaryAnimationChannel.swift | Modify: use `targets` array instead of single clip+mask |
| ContinuousAnimationChannel.swift | Modify: use `targets` array instead of single clip+mask |
| AnimationChannelSet.swift | **DELETE** |
| AnimationController.swift | **DELETE** |
| AnimationMask.swift | Minor: remove debug print |
| AnimationLayerSystem.swift | Simplify: single-track, remove commented code |
| AircraftAnimator.swift | Simplify: remove legacy protocol, streamline |
| F35Animator.swift | Minor: update to new API |
| F35AnimationConfig.swift | Simplify: multi-target factory |
| Aircraft.swift | No change |
| F35.swift | No change |

## Risk Assessment

- **Low risk**: The external API (F35 calls `animator?.toggleGear()` and `animator?.update()`) doesn't change
- **Medium risk**: The `updatePoses` refactor in AnimationLayerSystem is the most complex change. The per-target loop needs to correctly find and update affected skeletons, which is currently working with the per-channel approach
- **Testing**: Run the existing landing gear animation to verify it still works correctly (gear extends/retracts smoothly for all 3 assemblies)

## Estimated Reduction

- Current: ~1,670 lines across 10 files
- After: ~900-1,000 lines across 8 files (2 deleted)
- Reduction: ~40%
