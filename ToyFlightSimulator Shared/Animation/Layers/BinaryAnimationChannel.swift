//
//  BinaryAnimationChannel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Animation channel for two-state animations.
/// Used for components that have discrete on/off states like landing gear (up/down),
/// canopy (open/closed), air brake (deployed/retracted), etc.
final class BinaryAnimationChannel: AnimationChannel, StatefulAnimationChannel {
    // MARK: - State Definition

    /// Represents the possible states of a binary animation channel
    enum State {
        case inactive      // Fully in the "off" position (e.g., gear up, canopy closed)
        case activating    // Transitioning from inactive to active
        case active        // Fully in the "on" position (e.g., gear down, canopy open)
        case deactivating  // Transitioning from active to inactive
    }

    // MARK: - AnimationChannel Properties

    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?

    private(set) var isDirty: Bool = false

    // MARK: - Binary Channel Properties

    /// Current state of this channel
    private(set) var state: State

    /// Animation progress from 0.0 (inactive) to 1.0 (active)
    private(set) var progress: Float

    /// Duration for state transitions in seconds
    var transitionDuration: Float

    /// Optional time range within the animation clip to use
    /// If nil, uses progress * transitionDuration
    var timeRange: (start: Float, end: Float)?

    // MARK: - Computed Properties

    /// True if the channel is fully in the active state
    var isActive: Bool {
        state == .active
    }

    /// True if the channel is fully in the inactive state
    var isInactive: Bool {
        state == .inactive
    }

    /// True if an animation transition is in progress
    var isAnimating: Bool {
        state == .activating || state == .deactivating
    }

    /// Normalized progress (always 0.0 to 1.0 regardless of direction)
    var normalizedProgress: Float {
        progress
    }

    // MARK: - Initialization

    /// Creates a new binary animation channel
    /// - Parameters:
    ///   - id: Unique identifier for this channel
    ///   - mask: Defines which joints/meshes this channel controls
    ///   - transitionDuration: Time for transitions in seconds
    ///   - initialState: Starting state (default: .inactive)
    ///   - animationClip: Optional animation clip to use
    ///   - timeRange: Optional time range within the clip
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
        self.animationClip = animationClip
        self.timeRange = timeRange

        // Set initial progress based on state
        switch initialState {
        case .inactive, .activating:
            self.progress = 0.0
        case .active, .deactivating:
            self.progress = 1.0
        }

        // Mark dirty to ensure initial pose is set
        self.isDirty = true
    }

    // MARK: - Control Methods

    /// Begin transition to the active state
    /// Only works when fully inactive
    func activate() {
        guard state == .inactive else {
            print("[BinaryAnimationChannel '\(id)'] Cannot activate - current state: \(state)")
            return
        }
        print("[BinaryAnimationChannel '\(id)'] Beginning activation")
        state = .activating
        isDirty = true
    }

    /// Begin transition to the inactive state
    /// Only works when fully active
    func deactivate() {
        guard state == .active else {
            print("[BinaryAnimationChannel '\(id)'] Cannot deactivate - current state: \(state)")
            return
        }
        print("[BinaryAnimationChannel '\(id)'] Beginning deactivation")
        state = .deactivating
        isDirty = true
    }

    /// Toggle between active and inactive states
    /// Ignored if a transition is already in progress
    func toggle() {
        switch state {
        case .inactive:
            activate()
        case .active:
            deactivate()
        case .activating, .deactivating:
            print("[BinaryAnimationChannel '\(id)'] Animation in progress, ignoring toggle")
        }
    }

    /// Set the progress directly (for scrubbing or instant state changes)
    /// - Parameter value: Progress value (0.0 = inactive, 1.0 = active)
    func setProgress(_ value: Float) {
        progress = max(0, min(1, value))

        // Update state based on progress
        if progress >= 1.0 {
            state = .active
        } else if progress <= 0.0 {
            state = .inactive
        } else {
            // In between - determine direction based on previous state
            if state == .inactive || state == .activating {
                state = .activating
            } else {
                state = .deactivating
            }
        }

        isDirty = true
    }

    /// Set to active state immediately without animation
    func setActiveImmediate() {
        state = .active
        progress = 1.0
        isDirty = true
    }

    /// Set to inactive state immediately without animation
    func setInactiveImmediate() {
        state = .inactive
        progress = 0.0
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
                print("[BinaryAnimationChannel '\(id)'] Activation complete")
            }
            isDirty = true

        case .deactivating:
            progress -= deltaTime / transitionDuration
            if progress <= 0.0 {
                progress = 0.0
                state = .inactive
                print("[BinaryAnimationChannel '\(id)'] Deactivation complete")
            }
            isDirty = true

        case .active, .inactive:
            // No update needed when not animating
            break
        }
    }

    func getAnimationTime() -> Float {
        if let range = timeRange {
            // Map progress to time range
            return range.start + progress * (range.end - range.start)
        }
        // Default: use progress * duration
        return progress * transitionDuration
    }

    func clearDirty() {
        isDirty = false
    }
}

// MARK: - CustomStringConvertible

extension BinaryAnimationChannel: CustomStringConvertible {
    var description: String {
        "BinaryAnimationChannel('\(id)', state: \(state), progress: \(String(format: "%.2f", progress)))"
    }
}

// MARK: - Debug Helpers

extension BinaryAnimationChannel {
    /// Print current state for debugging
    func debugPrintState() {
        print("""
        [BinaryAnimationChannel '\(id)']
          State: \(state)
          Progress: \(String(format: "%.2f", progress))
          Duration: \(String(format: "%.2f", transitionDuration))s
          Animation Time: \(String(format: "%.2f", getAnimationTime()))s
          Dirty: \(isDirty)
          Mask: \(mask)
        """)
    }
}
