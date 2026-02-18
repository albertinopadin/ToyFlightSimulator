//
//  F35AnimationConfig.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// Animation configuration for F-35 Lightning II aircraft.
/// Defines all animation layers and channels available on this aircraft model.
struct F35AnimationConfig {
    // MARK: - Layer IDs

    /// Standard layer ID for landing gear
    static let landingGearLayerID = "landingGear"

    // Future layer IDs:
    // static let weaponBayLayerID = "weaponBay"
    // static let canopyLayerID = "canopy"
    // static let flapsLayerID = "flaps"

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
        let jointAnim = animClip?.jointAnimation.values.first as? Animation

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

        return BinaryAnimationChannel(
            id: "landingGear",
            mask: mask,
            transitionDuration: duration,
            initialState: .active,  // Start with gear down
            animationClip: animationClip,
            timeRange: (start: 0, end: duration)
        )
    }

    /// Creates the landing gear layer (group of channels) for F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: A configured AnimationLayer grouping all landing gear channels
    static func createLandingGearLayer(for model: UsdModel) -> AnimationLayer {
        var channels: [AnimationChannel] = []

        print("[createLandingGearLayer] model meshSkeletonMap: \(model.meshSkeletonMap)")
        print("[createLandingGearLayer] model skeletonAnimationMap: \(model.skeletonAnimationMap)")

        // For now using all animation clips since the F-35 model only has landing gear animations:
        for (i, animationClip) in model.animationClips.values.enumerated() {
            guard let skeletonAnimation = model.skeletonAnimationMap.first(where: {
                $0.value == animationClip.name
            }) else {
                fatalError("F-35 model has no animation clip named: \(animationClip.name)")
            }

            let meshIndices = model.meshSkeletonMap.filter { $0.value == skeletonAnimation.key }.map { $0.key }

            print("[createLandingGearLayer] meshIndices: \(meshIndices) for animationClip: \(animationClip.name)")

            guard !meshIndices.isEmpty else {
                fatalError("F-35 model has no mesh indices for animation clip: \(animationClip.name)")
            }

            let mask = AnimationMask(jointPaths: animationClip.jointPaths, meshIndices: meshIndices)

            let channel = BinaryAnimationChannel(
                id: "landingGear_\(i)",
                mask: mask,
                transitionDuration: animationClip.duration,
                initialState: .active,  // Start with gear down
                animationClip: animationClip,
                timeRange: (start: 0, end: animationClip.duration)
            )

            channels.append(channel)
        }

        return AnimationLayer(id: landingGearLayerID, channels: channels)
    }

    /// Creates all animation layers for the F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: Array of configured animation layers
    static func createLayers(for model: UsdModel) -> [AnimationLayer] {
        var layers: [AnimationLayer] = []

        // Landing gear is the primary layer:
        layers.append(createLandingGearLayer(for: model))

        // Future layers can be added here:
        // layers.append(createWeaponBayLayer(for: model))
        // layers.append(createCanopyLayer(for: model))
        // layers.append(createFlapsLayer(for: model))

        return layers
    }

    // MARK: - Future Channel/Layer Definitions

    /*
    /// Creates weapon bay doors layer (future)
    static func createWeaponBayLayer(for model: UsdModel) -> AnimationLayer {
        let bayJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
            .filter { $0.lowercased().contains("bay") || $0.lowercased().contains("weapon") }

        let mask = AnimationMask(jointPaths: bayJointPaths)

        let channel = BinaryAnimationChannel(
            id: "weaponBay",
            mask: mask,
            transitionDuration: 2.0,
            initialState: .inactive
        )

        return AnimationLayer(id: "weaponBay", channels: [channel])
    }

    /// Creates flaps layer (future)
    static func createFlapsLayer(for model: UsdModel) -> AnimationLayer {
        let flapJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
            .filter { $0.lowercased().contains("flap") }

        let mask = AnimationMask(jointPaths: flapJointPaths)

        let channel = ContinuousAnimationChannel(
            id: "flaps",
            mask: mask,
            range: (0.0, 1.0),
            transitionSpeed: 0.5,
            initialValue: 0.0
        )

        return AnimationLayer(id: "flaps", channels: [channel])
    }
    */
}
