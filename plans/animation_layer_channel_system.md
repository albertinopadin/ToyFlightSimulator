# Animation Layer/Channel System Implementation Plan

**Date**: January 2026
**Status**: Ready for Implementation
**Prerequisites**: Research complete (see `investigations/animation-layer-channel-system.md`)

---

## Overview

Implement a flexible animation layer/channel system that allows independent control of each animatable aircraft part (landing gear, flaps, ailerons, rudder, canopy, etc.) through dedicated channels.

## Goals

1. **Independent Control**: Each animatable part has its own channel with state machine
2. **Efficient Updates**: Only recalculate poses for channels that changed
3. **Data-Driven**: Aircraft-specific channel configurations without code changes
4. **Extensible**: Easy to add new channel types (binary, continuous, triggered)
5. **Industry-Aligned**: Follow Unity/Unreal animation layer patterns

---

## File Structure

### New Files

```
ToyFlightSimulator Shared/Animation/
├── Channels/
│   ├── AnimationChannel.swift        # Protocol + base implementation
│   ├── BinaryAnimationChannel.swift  # Two-state channels (gear, canopy)
│   ├── ContinuousAnimationChannel.swift  # Variable position (flaps, ailerons)
│   └── AnimationMask.swift           # Bone/mesh masking
├── AnimationLayerSystem.swift        # Multi-channel orchestrator
└── Aircraft/
    ├── AircraftAnimator.swift        # REFACTOR: Use channels internally
    ├── F35AnimationConfig.swift      # F-35 channel definitions
    └── F35Animator.swift             # MODIFY: Use new channel system
```

### Modified Files

```
ToyFlightSimulator Shared/
├── Animation/
│   └── Skeleton.swift                # Add partial pose update method
├── Assets/
│   └── UsdModel.swift                # Minor: ensure data accessible
└── GameObjects/
    └── Aircraft/
        ├── F35.swift                 # Use new animation system
        └── Aircraft.swift            # Optional: base animation support
```

---

## Phase 1: Core Infrastructure

### Step 1.1: Create AnimationMask

**File**: `Animation/Channels/AnimationMask.swift`

```swift
/// Defines which joints and meshes an animation channel controls
struct AnimationMask {
    /// Joint paths that this mask includes (e.g., "Armature/LandingGear/MainGearLeft")
    let jointPaths: Set<String>

    /// Mesh indices that this mask includes (for transform-based animation)
    let meshIndices: Set<Int>

    /// Creates a mask with only joint paths
    init(jointPaths: [String]) {
        self.jointPaths = Set(jointPaths)
        self.meshIndices = []
    }

    /// Creates a mask with only mesh indices
    init(meshIndices: [Int]) {
        self.jointPaths = []
        self.meshIndices = Set(meshIndices)
    }

    /// Creates a mask with both joints and meshes
    init(jointPaths: [String], meshIndices: [Int]) {
        self.jointPaths = Set(jointPaths)
        self.meshIndices = Set(meshIndices)
    }

    /// Check if a joint path is included in this mask
    func contains(jointPath: String) -> Bool {
        jointPaths.contains(jointPath)
    }

    /// Check if a mesh index is included in this mask
    func contains(meshIndex: Int) -> Bool {
        meshIndices.contains(meshIndex)
    }

    /// An empty mask that affects nothing
    static let empty = AnimationMask(jointPaths: [], meshIndices: [])

    /// A mask that affects all joints and meshes (use with caution)
    static func all(jointPaths: [String], meshCount: Int) -> AnimationMask {
        AnimationMask(jointPaths: jointPaths, meshIndices: Array(0..<meshCount))
    }
}
```

### Step 1.2: Create AnimationChannel Protocol

**File**: `Animation/Channels/AnimationChannel.swift`

```swift
/// Protocol defining the interface for animation channels.
/// Each channel controls a specific animatable subsystem (gear, flaps, etc.)
protocol AnimationChannel: AnyObject {
    /// Unique identifier for this channel
    var id: String { get }

    /// Mask defining which joints/meshes this channel affects
    var mask: AnimationMask { get }

    /// Weight of this channel's contribution (0.0 to 1.0)
    var weight: Float { get set }

    /// Whether this channel has changed and needs pose update
    var isDirty: Bool { get }

    /// The animation clip this channel uses (if any)
    var animationClip: AnimationClip? { get set }

    /// Update the channel's internal state
    /// - Parameter deltaTime: Time since last update in seconds
    func update(deltaTime: Float)

    /// Get the current animation time for this channel
    func getAnimationTime() -> Float

    /// Clear the dirty flag after poses have been updated
    func clearDirty()
}

// Default implementations
extension AnimationChannel {
    var weight: Float { 1.0 }

    func clearDirty() {
        // Subclasses must implement if they track dirty state
    }
}
```

### Step 1.3: Create BinaryAnimationChannel

**File**: `Animation/Channels/BinaryAnimationChannel.swift`

```swift
/// Animation channel for two-state animations (gear up/down, canopy open/closed)
class BinaryAnimationChannel: AnimationChannel {
    /// State of a binary animation
    enum State {
        case inactive      // Fully in the "off" position (e.g., gear up)
        case activating    // Transitioning from inactive to active
        case active        // Fully in the "on" position (e.g., gear down)
        case deactivating  // Transitioning from active to inactive
    }

    // MARK: - AnimationChannel Conformance

    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?

    private(set) var isDirty: Bool = false

    // MARK: - Binary Channel Properties

    /// Current state of this channel
    private(set) var state: State

    /// Animation progress (0.0 = inactive, 1.0 = active)
    private(set) var progress: Float

    /// Duration for state transition in seconds
    var transitionDuration: Float

    /// Time range within the animation clip to use (nil = full clip)
    var timeRange: (start: Float, end: Float)?

    // MARK: - Computed Properties

    /// True if the channel is in the active (extended/open) state
    var isActive: Bool { state == .active }

    /// True if the channel is in the inactive (retracted/closed) state
    var isInactive: Bool { state == .inactive }

    /// True if an animation is in progress
    var isAnimating: Bool { state == .activating || state == .deactivating }

    // MARK: - Initialization

    init(
        id: String,
        mask: AnimationMask,
        transitionDuration: Float,
        initialState: State = .inactive,
        animationClip: AnimationClip? = nil,
        timeRange: (start: Float, end: Float)? = nil
    ) {
        self.id = id
        self.mask = mask
        self.transitionDuration = transitionDuration
        self.state = initialState
        self.progress = initialState == .active ? 1.0 : 0.0
        self.animationClip = animationClip
        self.timeRange = timeRange
    }

    // MARK: - Control Methods

    /// Transition to the active state
    func activate() {
        guard state == .inactive else { return }
        state = .activating
        isDirty = true
    }

    /// Transition to the inactive state
    func deactivate() {
        guard state == .active else { return }
        state = .deactivating
        isDirty = true
    }

    /// Toggle between active and inactive states
    func toggle() {
        switch state {
        case .inactive:
            activate()
        case .active:
            deactivate()
        case .activating, .deactivating:
            break // Ignore during transition
        }
    }

    /// Set to a specific progress value immediately
    func setProgress(_ value: Float) {
        progress = max(0, min(1, value))
        state = progress >= 1.0 ? .active : (progress <= 0.0 ? .inactive : .activating)
        isDirty = true
    }

    // MARK: - AnimationChannel Methods

    func update(deltaTime: Float) {
        guard transitionDuration > 0 else { return }

        switch state {
        case .activating:
            progress += deltaTime / transitionDuration
            if progress >= 1.0 {
                progress = 1.0
                state = .active
            }
            isDirty = true

        case .deactivating:
            progress -= deltaTime / transitionDuration
            if progress <= 0.0 {
                progress = 0.0
                state = .inactive
            }
            isDirty = true

        case .active, .inactive:
            break
        }
    }

    func getAnimationTime() -> Float {
        if let range = timeRange {
            return range.start + progress * (range.end - range.start)
        }
        return progress * transitionDuration
    }

    func clearDirty() {
        isDirty = false
    }
}
```

### Step 1.4: Create ContinuousAnimationChannel

**File**: `Animation/Channels/ContinuousAnimationChannel.swift`

```swift
/// Animation channel for variable-position animations (flaps, control surfaces)
class ContinuousAnimationChannel: AnimationChannel {
    // MARK: - AnimationChannel Conformance

    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?

    private(set) var isDirty: Bool = false

    // MARK: - Continuous Channel Properties

    /// Current value (-1.0 to 1.0 or 0.0 to 1.0 depending on range)
    private(set) var value: Float

    /// Target value for smooth transitions
    private(set) var targetValue: Float

    /// Speed of value change (units per second)
    var transitionSpeed: Float

    /// Valid range for the value
    let range: (min: Float, max: Float)

    /// Time range within the animation clip (maps value range to time range)
    var timeRange: (start: Float, end: Float)?

    // MARK: - Computed Properties

    /// Normalized value (0.0 to 1.0)
    var normalizedValue: Float {
        (value - range.min) / (range.max - range.min)
    }

    /// True if value is transitioning to target
    var isTransitioning: Bool {
        abs(value - targetValue) > 0.001
    }

    // MARK: - Initialization

    init(
        id: String,
        mask: AnimationMask,
        range: (min: Float, max: Float) = (0.0, 1.0),
        transitionSpeed: Float = 1.0,
        initialValue: Float = 0.0,
        animationClip: AnimationClip? = nil,
        timeRange: (start: Float, end: Float)? = nil
    ) {
        self.id = id
        self.mask = mask
        self.range = range
        self.transitionSpeed = transitionSpeed
        self.value = max(range.min, min(range.max, initialValue))
        self.targetValue = self.value
        self.animationClip = animationClip
        self.timeRange = timeRange
    }

    // MARK: - Control Methods

    /// Set the target value (will transition smoothly)
    func setValue(_ newValue: Float) {
        targetValue = max(range.min, min(range.max, newValue))
        if targetValue != value {
            isDirty = true
        }
    }

    /// Set the value immediately without transition
    func setValueImmediate(_ newValue: Float) {
        value = max(range.min, min(range.max, newValue))
        targetValue = value
        isDirty = true
    }

    /// Increment the value by a delta
    func adjustValue(by delta: Float) {
        setValue(targetValue + delta)
    }

    // MARK: - AnimationChannel Methods

    func update(deltaTime: Float) {
        guard isTransitioning else { return }

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
        if let range = timeRange {
            return range.start + normalizedValue * (range.end - range.start)
        }
        return normalizedValue
    }

    func clearDirty() {
        isDirty = false
    }
}
```

---

## Phase 2: Animation Layer System

### Step 2.1: Create AnimationLayerSystem

**File**: `Animation/AnimationLayerSystem.swift`

```swift
/// Manages multiple animation channels and coordinates pose updates
class AnimationLayerSystem {
    // MARK: - Properties

    /// Reference to the model containing animation data
    private weak var model: UsdModel?

    /// Registered animation channels, keyed by ID
    private var channels: [String: AnimationChannel] = [:]

    /// Order in which to evaluate channels (for potential blending)
    private var evaluationOrder: [String] = []

    // MARK: - Initialization

    init(model: UsdModel) {
        self.model = model
        model.hasExternalAnimator = true
    }

    // MARK: - Channel Management

    /// Register a new animation channel
    func registerChannel(_ channel: AnimationChannel) {
        channels[channel.id] = channel
        evaluationOrder.append(channel.id)

        // Try to find matching animation clip if not set
        if channel.animationClip == nil, let clip = model?.animationClips.values.first {
            channel.animationClip = clip
        }
    }

    /// Unregister a channel by ID
    func unregisterChannel(_ id: String) {
        channels.removeValue(forKey: id)
        evaluationOrder.removeAll { $0 == id }
    }

    /// Get a channel by ID
    func channel(_ id: String) -> AnimationChannel? {
        channels[id]
    }

    /// Get a typed channel by ID
    func channel<T: AnimationChannel>(_ id: String, as type: T.Type) -> T? {
        channels[id] as? T
    }

    /// Get all registered channel IDs
    var channelIDs: [String] {
        Array(channels.keys)
    }

    // MARK: - Update

    /// Update all channels and refresh poses for dirty channels
    func update(deltaTime: Float) {
        guard let model = model else { return }

        // Update all channels
        for id in evaluationOrder {
            channels[id]?.update(deltaTime: deltaTime)
        }

        // Update poses for dirty channels
        for id in evaluationOrder {
            guard let channel = channels[id], channel.isDirty else { continue }

            updatePoses(for: channel, model: model)
            channel.clearDirty()
        }
    }

    // MARK: - Pose Updates

    /// Update skeleton and mesh poses for a single channel
    private func updatePoses(for channel: AnimationChannel, model: UsdModel) {
        let animTime = channel.getAnimationTime()
        let mask = channel.mask

        // Update skeletons for affected joints
        for (skeletonPath, skeleton) in model.skeletons {
            let affectedJoints = skeleton.jointPaths.filter { mask.contains(jointPath: $0) }

            if !affectedJoints.isEmpty {
                // Find the animation clip to use
                let clip = channel.animationClip
                    ?? model.animationClips[model.skeletonAnimationMap[skeletonPath] ?? ""]
                    ?? model.animationClips.values.first

                if let clip = clip {
                    skeleton.updatePose(at: animTime, animationClip: clip)
                }
            }
        }

        // Update mesh transforms and skins
        for (index, mesh) in model.meshes.enumerated() {
            // Check if this mesh is affected by the channel mask
            let meshAffected = mask.contains(meshIndex: index)
            let skeletonAffected: Bool

            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                skeletonAffected = skeleton.jointPaths.contains { mask.contains(jointPath: $0) }
            } else {
                skeletonAffected = false
            }

            guard meshAffected || skeletonAffected else { continue }

            // Update transform if present
            if mesh.transform != nil {
                mesh.transform?.setCurrentTransform(at: animTime)
            }

            // Update skin
            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            }
        }
    }

    // MARK: - Convenience Methods

    /// Force update all poses regardless of dirty state
    func forceUpdateAllPoses() {
        guard let model = model else { return }

        for id in evaluationOrder {
            if let channel = channels[id] {
                updatePoses(for: channel, model: model)
            }
        }
    }

    /// Set all channels to their initial state
    func reset() {
        for channel in channels.values {
            if let binary = channel as? BinaryAnimationChannel {
                binary.setProgress(0)
            } else if let continuous = channel as? ContinuousAnimationChannel {
                continuous.setValueImmediate(0)
            }
        }
        forceUpdateAllPoses()
    }
}
```

---

## Phase 3: F-35 Integration

### Step 3.1: Create F35AnimationConfig

**File**: `Animation/Aircraft/F35AnimationConfig.swift`

```swift
/// Channel configuration for F-35 Lightning II
struct F35AnimationConfig {
    /// Landing gear channel configuration
    static func createLandingGearChannel(for model: UsdModel) -> BinaryAnimationChannel {
        // Determine joint paths for landing gear
        // These should be extracted from the actual F-35 model skeleton
        let gearJointPaths = model.skeletons.values.flatMap { skeleton in
            skeleton.jointPaths.filter { path in
                // Match landing gear related joints
                path.lowercased().contains("gear") ||
                path.lowercased().contains("wheel") ||
                path.lowercased().contains("strut") ||
                path.lowercased().contains("door")  // Gear doors
            }
        }

        let mask = AnimationMask(jointPaths: gearJointPaths)

        // Get duration from animation clip
        let duration = model.animationClips.values.first?.duration ?? 4.0

        return BinaryAnimationChannel(
            id: "landingGear",
            mask: mask,
            transitionDuration: duration,
            initialState: .active,  // Start with gear down
            animationClip: model.animationClips.values.first
        )
    }

    /// Create all channels for F-35
    static func createChannels(for model: UsdModel) -> [AnimationChannel] {
        var channels: [AnimationChannel] = []

        // Landing gear is the primary channel for now
        channels.append(createLandingGearChannel(for: model))

        // Future channels can be added here:
        // - Weapon bay doors
        // - VTOL nozzle (for F-35B)
        // - Refueling probe
        // - Canopy

        return channels
    }
}
```

### Step 3.2: Refactor AircraftAnimator (Option A: Keep as Facade)

**File**: `Animation/Aircraft/AircraftAnimator.swift` (modified)

Keep `AircraftAnimator` as a facade that uses `AnimationLayerSystem` internally:

```swift
/// Aircraft-specific animation controller providing convenience methods
/// for common aircraft animations while using AnimationLayerSystem internally.
class AircraftAnimator: AnimationController {
    // MARK: - Properties

    internal weak var model: UsdModel?
    internal var layerSystem: AnimationLayerSystem?

    // AnimationController conformance
    private(set) var playbackState: AnimationPlaybackState = .stopped
    private(set) var currentTime: Float = 0

    // MARK: - Initialization

    init(model: UsdModel) {
        self.model = model
        self.layerSystem = AnimationLayerSystem(model: model)
    }

    // MARK: - Channel Registration

    func registerChannel(_ channel: AnimationChannel) {
        layerSystem?.registerChannel(channel)
    }

    func channel(_ id: String) -> AnimationChannel? {
        layerSystem?.channel(id)
    }

    // MARK: - Gear Convenience Methods

    var gearChannel: BinaryAnimationChannel? {
        layerSystem?.channel("landingGear", as: BinaryAnimationChannel.self)
    }

    var gearState: GearState {
        guard let channel = gearChannel else { return .down }
        switch channel.state {
        case .inactive: return .up
        case .activating: return .extending
        case .active: return .down
        case .deactivating: return .retracting
        }
    }

    var isGearDown: Bool { gearChannel?.isActive ?? true }
    var isGearUp: Bool { gearChannel?.isInactive ?? false }
    var isGearAnimating: Bool { gearChannel?.isAnimating ?? false }
    var gearAnimationProgress: Float { gearChannel?.progress ?? 1.0 }

    func extendGear() { gearChannel?.activate() }
    func retractGear() { gearChannel?.deactivate() }
    func toggleGear() { gearChannel?.toggle() }

    // MARK: - AnimationController Protocol

    func play(clipName: String, speed: Float, loop: Bool) {
        playbackState = .playing
    }

    func pause() {
        playbackState = .paused
    }

    func stop() {
        playbackState = .stopped
    }

    func update(deltaTime: Float) {
        layerSystem?.update(deltaTime: deltaTime)
    }
}
```

### Step 3.3: Update F35Animator

**File**: `Animation/Aircraft/F35Animator.swift` (modified)

```swift
/// F-35 specific animator with configured channels
final class F35Animator: AircraftAnimator {
    override init(model: UsdModel) {
        super.init(model: model)

        // Register F-35 specific channels
        for channel in F35AnimationConfig.createChannels(for: model) {
            registerChannel(channel)
        }

        // Initialize to gear-down pose
        layerSystem?.forceUpdateAllPoses()
    }

    // Future: Add F-35 specific convenience methods
    // func openWeaponBay() { channel("weaponBay")?.activate() }
    // func toggleVTOLMode() { ... }
}
```

### Step 3.4: Update F35.swift Usage

**File**: `GameObjects/Aircraft/F35.swift` (relevant section)

```swift
class F35: Aircraft {
    private var animator: F35Animator?

    override init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(/* ... */)

        if let usdModel = model as? UsdModel {
            animator = F35Animator(model: usdModel)
        }
    }

    override func doUpdate() {
        super.doUpdate()

        // Handle gear toggle
        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
            animator?.toggleGear()
        }

        // Update animations
        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }
}
```

---

## Phase 4: Future Enhancements

### Step 4.1: Add More Channel Types

**Triggered Channel** for one-shot animations:
```swift
class TriggeredAnimationChannel: AnimationChannel {
    var isTriggered: Bool = false
    var playbackProgress: Float = 0

    func trigger() {
        isTriggered = true
        playbackProgress = 0
    }
}
```

### Step 4.2: Add More F-35 Channels

```swift
// In F35AnimationConfig.swift

static func createWeaponBayChannel(for model: UsdModel) -> BinaryAnimationChannel {
    let bayJoints = /* extract weapon bay door joints */
    let mask = AnimationMask(jointPaths: bayJoints)
    return BinaryAnimationChannel(
        id: "weaponBay",
        mask: mask,
        transitionDuration: 2.0,
        initialState: .inactive
    )
}

static func createFlapsChannel(for model: UsdModel) -> ContinuousAnimationChannel {
    let flapJoints = /* extract flap joints */
    let mask = AnimationMask(jointPaths: flapJoints)
    return ContinuousAnimationChannel(
        id: "flaps",
        mask: mask,
        range: (0.0, 1.0),
        transitionSpeed: 0.5
    )
}
```

### Step 4.3: Create Configurations for Other Aircraft

```swift
struct F22AnimationConfig {
    static func createChannels(for model: UsdModel) -> [AnimationChannel] {
        // F-22 specific channels: gear, weapon bays, thrust vectoring
    }
}

struct F18AnimationConfig {
    static func createChannels(for model: UsdModel) -> [AnimationChannel] {
        // F-18 specific channels: gear, hook, LEX fences
    }
}
```

### Step 4.4: Partial Skeleton Update Optimization

Add method to `Skeleton.swift` for partial updates:

```swift
extension Skeleton {
    /// Update only specific joints' poses
    func updatePartialPose(
        at time: Float,
        animationClip: AnimationClip,
        affectedJoints: Set<String>
    ) {
        // Only calculate poses for joints in the set
        // Still need to calculate parent transforms for hierarchy
    }
}
```

---

## Testing Plan

### Unit Tests

1. **AnimationMask Tests**
   - Test joint path containment
   - Test mesh index containment
   - Test empty mask

2. **BinaryAnimationChannel Tests**
   - Test state transitions (inactive -> activating -> active)
   - Test progress calculation
   - Test toggle behavior
   - Test animation time calculation

3. **ContinuousAnimationChannel Tests**
   - Test value range clamping
   - Test smooth transitions
   - Test immediate value setting

4. **AnimationLayerSystem Tests**
   - Test channel registration/unregistration
   - Test dirty flag handling
   - Test update dispatch

### Integration Tests

1. **F-35 Landing Gear**
   - Test gear extension animation
   - Test gear retraction animation
   - Test interruption during transition

2. **Multiple Channels**
   - Test simultaneous channel animations
   - Test channel independence

---

## Migration Strategy

1. **Phase 1**: Implement new system alongside existing code
2. **Phase 2**: Migrate F-35 to new system, keep old code for fallback
3. **Phase 3**: Verify F-35 works correctly with new system
4. **Phase 4**: Apply to F-22, F-18 if they have animations
5. **Phase 5**: Remove old `AircraftAnimator` gear-specific code
6. **Phase 6**: Add more channels (flaps, ailerons, etc.)

---

## Success Criteria

- [ ] F-35 landing gear works with new channel system
- [ ] Can add new channels without modifying core classes
- [ ] Only dirty channels trigger pose updates
- [ ] Channel state machines work independently
- [ ] No regression in animation quality or performance
- [ ] Clean separation between channel types (binary, continuous)
- [ ] Aircraft-specific configuration is data-driven
