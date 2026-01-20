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
//    static let landingGearChannelID = "landingGear"
    static let landingGearChannelSetID = "landingGear"

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

        print("[F35AnimConfig createLandingGearChannel] gearJointPaths: \(gearJointPaths)")
        
        // If no specific gear joints found, use all joints (full model animation)
        let jointPaths = gearJointPaths.isEmpty ? allJointPaths : gearJointPaths
        let animClip = model.animationClips.first?.value
//        animClip.
        let jointAnim = animClip?.jointAnimation.values.first as? Animation
//        let bb = jointAnim.

        let mask = AnimationMask(jointPaths: jointPaths)

        // Get duration from the first animation clip
        let duration = model.animationClips.values.first?.duration ?? 4.0

        // Get the animation clip
        let animationClip = model.animationClips.values.first
        
        print("[F35AnimConfig createLandingGearChannel] animationClips: \(model.animationClips.count)")

        print("[F35AnimationConfig] Creating landing gear channel:")
        print("  - Joint paths in mask: \(jointPaths.count)")
        print("  - Animation duration: \(duration)s")
        print("  - Animation clip: \(animationClip?.name ?? "none")")

        // TODO: Maybe use something like a Channel Set (set of channels involved in gear animation)
        return BinaryAnimationChannel(
//            id: landingGearChannelID,
            id: "landingGear",
            mask: mask,
            transitionDuration: duration,
            initialState: .active,  // Start with gear down
            animationClip: animationClip,
            timeRange: (start: 0, end: duration)
        )
    }
    
    static func createLandingGearChannelSet(for model: UsdModel) -> AnimationChannelSet {
        var channels: [AnimationChannel] = []
        
        print("[createLandingGearChannelSet] model meshSkeletonMap: \(model.meshSkeletonMap)")
        print("[createLandingGearChannelSet] model skeletonAnimationMap: \(model.skeletonAnimationMap)")
        
        // For now using all animation clips since the F-35 model only has landing gear animations:
        for (i, animationClip) in model.animationClips.values.enumerated() {
            guard let skeletonAnimation = model.skeletonAnimationMap.first(where: {
                $0.value == animationClip.name
            }) else {
                fatalError("F-35 model has no animation clip named: \(animationClip.name)")
            }
            
            let meshIndices = model.meshSkeletonMap.filter { $0.value == skeletonAnimation.key }.map { $0.key }
            
            print("[createLandingGearChannelSet] meshIndices: \(meshIndices) for animationClip: \(animationClip.name)")
            
            guard !meshIndices.isEmpty else {
                fatalError("F-35 model has no mesh indices for animation clip: \(animationClip.name)")
            }
            
            let mask = AnimationMask(jointPaths: animationClip.jointPaths, meshIndices: meshIndices)
            
            let channel = BinaryAnimationChannel(
//                id: "\(landingGearChannelID)_\(i)",
                id: "landingGear_\(i)",
                mask: mask,
                transitionDuration: animationClip.duration,
                initialState: .active,  // Start with gear down
                animationClip: animationClip,
                timeRange: (start: 0, end: animationClip.duration)
            )
            
            channels.append(channel)
        }
        
        return AnimationChannelSet(id: landingGearChannelSetID, channels: channels)
    }

    /// Creates all animation channels for the F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: Array of configured animation channels
//    static func createAllChannels(for model: UsdModel) -> [AnimationChannel] {
//        var channels: [AnimationChannel] = []
//
//        // Landing gear is the primary channel
//        channels.append(createLandingGearChannel(for: model))
//
//        // Future channels can be added here:
//        // channels.append(createWeaponBayChannel(for: model))
//        // channels.append(createCanopyChannel(for: model))
//        // channels.append(createFlapsChannel(for: model))
//
//        return channels
//    }
    
    static func createAllChannelSets(for model: UsdModel) -> [AnimationChannelSet] {
        var channelSets: [AnimationChannelSet] = []

        // Landing gear is the primary channel set:
        channelSets.append(createLandingGearChannelSet(for: model))

        // Future channel sets can be added here:
        // channelSets.append(createWeaponBayChannel(for: model))
        // channelSets.append(createCanopyChannel(for: model))
        // channelSets.append(createFlapsChannel(for: model))

        return channelSets
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
