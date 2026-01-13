//
//  F35AnimationConfig.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Channel configuration for F-35 Lightning II aircraft.
/// Defines all animation channels available on this aircraft model.
struct F35AnimationConfig {
    // MARK: - Channel IDs

    /// Standard channel ID for landing gear
    static let landingGearChannelID = "landingGear"

    // Future channel IDs:
    // static let weaponBayChannelID = "weaponBay"
    // static let canopyChannelID = "canopy"
    // static let flapsChannelID = "flaps"

    // MARK: - Channel Creation

    /// Creates the landing gear channel for F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: A configured BinaryAnimationChannel for landing gear
    static func createLandingGearChannel(for model: UsdModel) -> BinaryAnimationChannel {
        // Get all joint paths from the model's skeletons
        let allJointPaths = model.skeletons.values.flatMap { $0.jointPaths }

        // Filter to find landing gear related joints
        // The F-35 model may have joints named with gear/wheel/strut/door patterns
        let gearJointPaths = allJointPaths.filter { path in
            let lowercased = path.lowercased()
            return lowercased.contains("gear") ||
                   lowercased.contains("wheel") ||
                   lowercased.contains("strut") ||
                   lowercased.contains("door") ||
                   lowercased.contains("landing")
        }

        // If no specific gear joints found, use all joints (full model animation)
        let jointPaths = gearJointPaths.isEmpty ? allJointPaths : gearJointPaths

        let mask = AnimationMask(jointPaths: jointPaths)

        // Get duration from the first animation clip
        let duration = model.animationClips.values.first?.duration ?? 4.0

        // Get the animation clip
        let animationClip = model.animationClips.values.first

        print("[F35AnimationConfig] Creating landing gear channel:")
        print("  - Joint paths in mask: \(jointPaths.count)")
        print("  - Animation duration: \(duration)s")
        print("  - Animation clip: \(animationClip?.name ?? "none")")

        return BinaryAnimationChannel(
            id: landingGearChannelID,
            mask: mask,
            transitionDuration: duration,
            initialState: .active,  // Start with gear down
            animationClip: animationClip,
            timeRange: (start: 0, end: duration)
        )
    }

    /// Creates all animation channels for the F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: Array of configured animation channels
    static func createAllChannels(for model: UsdModel) -> [AnimationChannel] {
        var channels: [AnimationChannel] = []

        // Landing gear is the primary channel
        channels.append(createLandingGearChannel(for: model))

        // Future channels can be added here:
        // channels.append(createWeaponBayChannel(for: model))
        // channels.append(createCanopyChannel(for: model))
        // channels.append(createFlapsChannel(for: model))

        return channels
    }

    // MARK: - Future Channel Definitions

    /*
    /// Creates weapon bay doors channel (future)
    static func createWeaponBayChannel(for model: UsdModel) -> BinaryAnimationChannel {
        let bayJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
            .filter { $0.lowercased().contains("bay") || $0.lowercased().contains("weapon") }

        let mask = AnimationMask(jointPaths: bayJointPaths)

        return BinaryAnimationChannel(
            id: "weaponBay",
            mask: mask,
            transitionDuration: 2.0,
            initialState: .inactive
        )
    }

    /// Creates flaps channel (future)
    static func createFlapsChannel(for model: UsdModel) -> ContinuousAnimationChannel {
        let flapJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
            .filter { $0.lowercased().contains("flap") }

        let mask = AnimationMask(jointPaths: flapJointPaths)

        return ContinuousAnimationChannel(
            id: "flaps",
            mask: mask,
            range: (0.0, 1.0),
            transitionSpeed: 0.5,
            initialValue: 0.0
        )
    }
    */
}
