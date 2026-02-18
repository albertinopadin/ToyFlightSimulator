//
//  AnimationLayer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Protocol defining the interface for animation layers.
/// Each layer controls a specific animatable subsystem (landing gear, flaps, ailerons, etc.)
/// and maintains its own state machine and timing independent of other layers.
protocol AnimationLayer: AnyObject {
    /// Unique identifier for this layer (e.g., "landingGear", "flaps", "leftAileron")
    var id: String { get }

    /// Mask defining which joints and meshes this layer affects
    var mask: AnimationMask { get }

    /// Weight of this layer's contribution (0.0 to 1.0)
    /// Default is 1.0 (full contribution)
    var weight: Float { get set }

    /// Whether this layer has changed and needs a pose update
    var isDirty: Bool { get }

    /// The animation clip this layer uses (if any)
    var animationClip: AnimationClip? { get set }

    /// Update the layer's internal state machine
    /// - Parameter deltaTime: Time since last update in seconds
    func update(deltaTime: Float)

    /// Get the current animation time for this layer based on its state
    /// - Returns: The time value to sample from the animation clip
    func getAnimationTime() -> Float

    /// Clear the dirty flag after poses have been updated
    func clearDirty()
}

// MARK: - Default Implementations

extension AnimationLayer {
    /// Default weight is full contribution
    var weight: Float {
        get { 1.0 }
        set { /* Subclasses can override to make this settable */ }
    }
}

// MARK: - layer State Protocol

/// Protocol for layers that have discrete states (used by binary layers)
protocol StatefulAnimationLayer: AnimationLayer {
    associatedtype StateType

    /// The current state of this layer
    var state: StateType { get }

    /// Whether the layer is currently animating between states
    var isAnimating: Bool { get }
}

// MARK: - layer Value Protocol

/// Protocol for layers that have continuous values (used by continuous layers)
protocol ValuedAnimationLayer: AnimationLayer {
    /// The current value of this layer
    var value: Float { get }

    /// The target value this layer is transitioning to
    var targetValue: Float { get }

    /// Set the target value for this layer
    /// - Parameter newValue: The new target value
    func setValue(_ newValue: Float)
}
