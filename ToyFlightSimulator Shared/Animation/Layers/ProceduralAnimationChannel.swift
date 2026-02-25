//
//  ProceduralAnimationChannel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/24/26.
//

import simd

/// Configuration for a single joint's procedural rotation.
struct ProceduralJointConfig {
    /// Joint path in the skeleton (e.g., "/root/Armature/Armature/LeftFlaperon")
    let jointPath: String

    /// Axis of rotation in the joint's local space (e.g., [1, 0, 0] for pitch-axis)
    let axis: float3

    /// Maximum deflection angle in radians when channel value is at range max
    let maxDeflection: Float

    /// If true, the deflection direction is inverted (useful for left/right symmetry)
    let inverted: Bool

    init(jointPath: String, axis: float3, maxDeflection: Float, inverted: Bool = false) {
        self.jointPath = jointPath
        self.axis = axis
        self.maxDeflection = maxDeflection
        self.inverted = inverted
    }
}

/// Animation channel for procedural (input-driven) bone animation.
/// Used for control surfaces that are rotated directly by player input
/// rather than sampled from pre-authored animation clips.
///
/// Unlike ContinuousAnimationChannel which maps a value to an animation clip time,
/// this channel maps a value directly to per-joint rotation transforms.
final class ProceduralAnimationChannel: AnimationChannel, ValuedAnimationChannel {
    // MARK: - AnimationChannel Properties

    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?  // Always nil for procedural channels

    private(set) var isDirty: Bool = false

    // MARK: - Value Properties

    /// Current value of this channel
    private(set) var value: Float

    /// Target value for smooth transitions
    private(set) var targetValue: Float

    /// Speed of value change (units per second)
    var transitionSpeed: Float

    /// Valid range for the value (e.g., -1.0 to 1.0 for control surfaces)
    let range: (min: Float, max: Float)

    // MARK: - Procedural Properties

    /// Per-joint rotation configurations
    let jointConfigs: [ProceduralJointConfig]

    // MARK: - Computed Properties

    /// True if value is currently transitioning to target
    var isTransitioning: Bool {
        abs(value - targetValue) > 0.001
    }

    // MARK: - Initialization

    /// Creates a new procedural animation channel.
    /// - Parameters:
    ///   - id: Unique identifier for this channel
    ///   - mask: Defines which joints this channel controls
    ///   - range: Valid value range (default: -1.0 to 1.0)
    ///   - transitionSpeed: Speed of value changes in units per second
    ///   - initialValue: Starting value (default: 0.0)
    ///   - jointConfigs: Per-joint rotation configurations
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

    // MARK: - Control Methods

    /// Set the target value (will transition smoothly based on transitionSpeed)
    /// - Parameter newValue: The target value (will be clamped to range)
    func setValue(_ newValue: Float) {
        let clamped = max(range.min, min(range.max, newValue))
        if abs(clamped - targetValue) > 0.001 {
            targetValue = clamped
            isDirty = true
        }
    }

    /// Set the value immediately without smooth transition
    /// - Parameter newValue: The value to set (will be clamped to range)
    func setValueImmediate(_ newValue: Float) {
        let clamped = max(range.min, min(range.max, newValue))
        value = clamped
        targetValue = clamped
        isDirty = true
    }

    // MARK: - AnimationChannel Protocol

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
        // Not used for procedural channels, but required by protocol.
        return 0
    }

    func clearDirty() {
        isDirty = false
    }

    // MARK: - Procedural Pose Computation

    /// Computes joint rotation overrides based on the current channel value.
    /// Returns a dictionary of jointPath -> local rotation matrix.
    /// These rotations are applied on top of (multiplied with) the joint's rest transform.
    func getJointOverrides() -> [String: float4x4] {
        var overrides: [String: float4x4] = [:]

        for config in jointConfigs {
            let deflection = config.inverted ? -value : value
            let angle = deflection * config.maxDeflection
            let rotation = float4x4(rotateAbout: normalize(config.axis), byAngle: angle)
            overrides[config.jointPath] = rotation
        }

        return overrides
    }
}

// MARK: - CustomStringConvertible

extension ProceduralAnimationChannel: CustomStringConvertible {
    var description: String {
        "ProceduralAnimationChannel('\(id)', value: \(String(format: "%.2f", value)), target: \(String(format: "%.2f", targetValue)), joints: \(jointConfigs.count))"
    }
}

// MARK: - Debug Helpers

extension ProceduralAnimationChannel {
    func debugPrintState() {
        print("""
        [ProceduralAnimationChannel '\(id)']
          Value: \(String(format: "%.3f", value))
          Target: \(String(format: "%.3f", targetValue))
          Range: \(String(format: "%.1f", range.min)) to \(String(format: "%.1f", range.max))
          Speed: \(String(format: "%.2f", transitionSpeed))/s
          Dirty: \(isDirty)
          Joint Configs: \(jointConfigs.count)
          Mask: \(mask)
        """)
    }
}
