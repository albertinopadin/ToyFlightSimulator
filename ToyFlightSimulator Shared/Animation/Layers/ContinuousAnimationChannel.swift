//
//  ContinuousAnimationChannel.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Animation channel for variable-position animations.
/// Used for components that have continuous values like flaps (0-100%),
/// control surfaces (ailerons, elevators, rudder at -100% to +100%), etc.
final class ContinuousAnimationChannel: AnimationChannel, ValuedAnimationChannel {
    // MARK: - AnimationChannel Properties

    let id: String
    let mask: AnimationMask
    var weight: Float = 1.0
    var animationClip: AnimationClip?

    private(set) var isDirty: Bool = false

    // MARK: - Continuous Channel Properties

    /// Current value of this channel
    private(set) var value: Float

    /// Target value for smooth transitions
    private(set) var targetValue: Float

    /// Speed of value change (units per second)
    var transitionSpeed: Float

    /// Valid range for the value (e.g., 0.0 to 1.0 for flaps, -1.0 to 1.0 for ailerons)
    let range: (min: Float, max: Float)

    /// Optional time range within the animation clip
    /// Maps the value range to this time range
    var timeRange: (start: Float, end: Float)?

    // MARK: - Computed Properties

    /// Normalized value mapped from range to 0.0-1.0
    var normalizedValue: Float {
        guard range.max > range.min else { return 0 }
        return (value - range.min) / (range.max - range.min)
    }

    /// True if value is currently transitioning to target
    var isTransitioning: Bool {
        abs(value - targetValue) > 0.001
    }

    /// True if value is at minimum
    var isAtMinimum: Bool {
        abs(value - range.min) < 0.001
    }

    /// True if value is at maximum
    var isAtMaximum: Bool {
        abs(value - range.max) < 0.001
    }

    /// True if value is at neutral (middle of range)
    var isAtNeutral: Bool {
        let neutral = (range.min + range.max) / 2.0
        return abs(value - neutral) < 0.001
    }

    // MARK: - Initialization

    /// Creates a new continuous animation channel
    /// - Parameters:
    ///   - id: Unique identifier for this channel
    ///   - mask: Defines which joints/meshes this channel controls
    ///   - range: Valid value range (default: 0.0 to 1.0)
    ///   - transitionSpeed: Speed of value changes in units per second
    ///   - initialValue: Starting value (default: 0.0)
    ///   - animationClip: Optional animation clip to use
    ///   - timeRange: Optional time range within the clip
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
        self.animationClip = animationClip
        self.timeRange = timeRange

        // Clamp initial value to range
        self.value = max(range.min, min(range.max, initialValue))
        self.targetValue = self.value

        // Mark dirty to ensure initial pose is set
        self.isDirty = true
    }

    // MARK: - Control Methods

    /// Set the target value (will transition smoothly based on transitionSpeed)
    /// - Parameter newValue: The target value (will be clamped to range)
    func setValue(_ newValue: Float) {
        let clampedValue = max(range.min, min(range.max, newValue))
        if abs(clampedValue - targetValue) > 0.001 {
            targetValue = clampedValue
            isDirty = true
        }
    }

    /// Set the value immediately without smooth transition
    /// - Parameter newValue: The value to set (will be clamped to range)
    func setValueImmediate(_ newValue: Float) {
        let clampedValue = max(range.min, min(range.max, newValue))
        value = clampedValue
        targetValue = clampedValue
        isDirty = true
    }

    /// Increment the target value by a delta
    /// - Parameter delta: Amount to add to target value
    func adjustValue(by delta: Float) {
        setValue(targetValue + delta)
    }

    /// Set to minimum value (with smooth transition)
    func setToMinimum() {
        setValue(range.min)
    }

    /// Set to maximum value (with smooth transition)
    func setToMaximum() {
        setValue(range.max)
    }

    /// Set to neutral/center value (with smooth transition)
    func setToNeutral() {
        setValue((range.min + range.max) / 2.0)
    }

    /// Set value as a normalized 0.0-1.0 value (mapped to actual range)
    /// - Parameter normalizedValue: Value from 0.0 to 1.0
    func setNormalizedValue(_ normalizedValue: Float) {
        let mapped = range.min + normalizedValue * (range.max - range.min)
        setValue(mapped)
    }

    // MARK: - AnimationChannel Methods

    func update(deltaTime: Float) {
        guard isTransitioning else { return }

        let maxChange = transitionSpeed * deltaTime
        let diff = targetValue - value

        if abs(diff) <= maxChange {
            // Close enough, snap to target
            value = targetValue
        } else {
            // Move toward target
            value += (diff > 0 ? maxChange : -maxChange)
        }

        isDirty = true
    }

    func getAnimationTime() -> Float {
        if let range = timeRange {
            // Map normalized value to time range
            return range.start + normalizedValue * (range.end - range.start)
        }
        // Default: return normalized value (0.0 to 1.0)
        return normalizedValue
    }

    func clearDirty() {
        isDirty = false
    }
}

// MARK: - CustomStringConvertible

extension ContinuousAnimationChannel: CustomStringConvertible {
    var description: String {
        "ContinuousAnimationChannel('\(id)', value: \(String(format: "%.2f", value)), target: \(String(format: "%.2f", targetValue)))"
    }
}

// MARK: - Debug Helpers

extension ContinuousAnimationChannel {
    /// Print current state for debugging
    func debugPrintState() {
        print("""
        [ContinuousAnimationChannel '\(id)']
          Value: \(String(format: "%.3f", value))
          Target: \(String(format: "%.3f", targetValue))
          Normalized: \(String(format: "%.3f", normalizedValue))
          Range: \(String(format: "%.1f", range.min)) to \(String(format: "%.1f", range.max))
          Speed: \(String(format: "%.2f", transitionSpeed))/s
          Animation Time: \(String(format: "%.3f", getAnimationTime()))
          Dirty: \(isDirty)
          Mask: \(mask)
        """)
    }
}
