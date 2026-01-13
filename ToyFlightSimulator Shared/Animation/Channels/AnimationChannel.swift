//
//  AnimationChannel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Protocol defining the interface for animation channels.
/// Each channel controls a specific animatable subsystem (landing gear, flaps, ailerons, etc.)
/// and maintains its own state machine and timing independent of other channels.
protocol AnimationChannel: AnyObject {
    /// Unique identifier for this channel (e.g., "landingGear", "flaps", "leftAileron")
    var id: String { get }

    /// Mask defining which joints and meshes this channel affects
    var mask: AnimationMask { get }

    /// Weight of this channel's contribution (0.0 to 1.0)
    /// Default is 1.0 (full contribution)
    var weight: Float { get set }

    /// Whether this channel has changed and needs a pose update
    var isDirty: Bool { get }

    /// The animation clip this channel uses (if any)
    var animationClip: AnimationClip? { get set }

    /// Update the channel's internal state machine
    /// - Parameter deltaTime: Time since last update in seconds
    func update(deltaTime: Float)

    /// Get the current animation time for this channel based on its state
    /// - Returns: The time value to sample from the animation clip
    func getAnimationTime() -> Float

    /// Clear the dirty flag after poses have been updated
    func clearDirty()
}

// MARK: - Default Implementations

extension AnimationChannel {
    /// Default weight is full contribution
    var weight: Float {
        get { 1.0 }
        set { /* Subclasses can override to make this settable */ }
    }
}

// MARK: - Channel State Protocol

/// Protocol for channels that have discrete states (used by binary channels)
protocol StatefulAnimationChannel: AnimationChannel {
    associatedtype StateType

    /// The current state of this channel
    var state: StateType { get }

    /// Whether the channel is currently animating between states
    var isAnimating: Bool { get }
}

// MARK: - Channel Value Protocol

/// Protocol for channels that have continuous values (used by continuous channels)
protocol ValuedAnimationChannel: AnimationChannel {
    /// The current value of this channel
    var value: Float { get }

    /// The target value this channel is transitioning to
    var targetValue: Float { get }

    /// Set the target value for this channel
    /// - Parameter newValue: The new target value
    func setValue(_ newValue: Float)
}
