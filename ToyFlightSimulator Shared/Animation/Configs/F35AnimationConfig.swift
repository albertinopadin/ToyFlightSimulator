//
//  F35AnimationConfig.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/26.
//

import Foundation

/// layer configuration for F-35 Lightning II aircraft.
/// Defines all animation layers available on this aircraft model.
struct F35AnimationConfig {
    // MARK: - layer IDs

    /// Standard layer ID for landing gear
//    static let landingGearlayerID = "landingGear"
    static let landingGearlayerSetID = "landingGear"

    // Future layer IDs:
    // static let weaponBaylayerID = "weaponBay"
    // static let canopylayerID = "canopy"
    // static let flapslayerID = "flaps"

    // MARK: - layer Creation

    /// Creates the landing gear layer for F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: A configured BinaryAnimationLayer for landing gear
    static func createLandingGearlayer(for model: UsdModel) -> BinaryAnimationLayer {
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

        print("[F35AnimConfig createLandingGearlayer] gearJointPaths: \(gearJointPaths)")
        
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
        
        print("[F35AnimConfig createLandingGearlayer] animationClips: \(model.animationClips.count)")

        print("[F35AnimationConfig] Creating landing gear layer:")
        print("  - Joint paths in mask: \(jointPaths.count)")
        print("  - Animation duration: \(duration)s")
        print("  - Animation clip: \(animationClip?.name ?? "none")")

        // TODO: Maybe use something like a layer Set (set of layers involved in gear animation)
        return BinaryAnimationLayer(
//            id: landingGearlayerID,
            id: "landingGear",
            mask: mask,
            transitionDuration: duration,
            initialState: .active,  // Start with gear down
            animationClip: animationClip,
            timeRange: (start: 0, end: duration)
        )
    }
    
    static func createLandingGearlayerSet(for model: UsdModel) -> AnimationLayerSet {
        var layers: [AnimationLayer] = []
        
        print("[createLandingGearlayerSet] model meshSkeletonMap: \(model.meshSkeletonMap)")
        print("[createLandingGearlayerSet] model skeletonAnimationMap: \(model.skeletonAnimationMap)")
        
        // For now using all animation clips since the F-35 model only has landing gear animations:
        for (i, animationClip) in model.animationClips.values.enumerated() {
            guard let skeletonAnimation = model.skeletonAnimationMap.first(where: {
                $0.value == animationClip.name
            }) else {
                fatalError("F-35 model has no animation clip named: \(animationClip.name)")
            }
            
            let meshIndices = model.meshSkeletonMap.filter { $0.value == skeletonAnimation.key }.map { $0.key }
            
            print("[createLandingGearlayerSet] meshIndices: \(meshIndices) for animationClip: \(animationClip.name)")
            
            guard !meshIndices.isEmpty else {
                fatalError("F-35 model has no mesh indices for animation clip: \(animationClip.name)")
            }
            
            let mask = AnimationMask(jointPaths: animationClip.jointPaths, meshIndices: meshIndices)
            
            let layer = BinaryAnimationLayer(
//                id: "\(landingGearlayerID)_\(i)",
                id: "landingGear_\(i)",
                mask: mask,
                transitionDuration: animationClip.duration,
                initialState: .active,  // Start with gear down
                animationClip: animationClip,
                timeRange: (start: 0, end: animationClip.duration)
            )
            
            layers.append(layer)
        }
        
        return AnimationLayerSet(id: landingGearlayerSetID, layers: layers)
    }

    /// Creates all animation layers for the F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: Array of configured animation layers
//    static func createAlllayers(for model: UsdModel) -> [AnimationLayer] {
//        var layers: [AnimationLayer] = []
//
//        // Landing gear is the primary layer
//        layers.append(createLandingGearlayer(for: model))
//
//        // Future layers can be added here:
//        // layers.append(createWeaponBaylayer(for: model))
//        // layers.append(createCanopylayer(for: model))
//        // layers.append(createFlapslayer(for: model))
//
//        return layers
//    }
    
    static func createLayerSets(for model: UsdModel) -> [AnimationLayerSet] {
        var layerSets: [AnimationLayerSet] = []

        // Landing gear is the primary layer set:
        layerSets.append(createLandingGearlayerSet(for: model))

        // Future layer sets can be added here:
        // layerSets.append(createWeaponBaylayer(for: model))
        // layerSets.append(createCanopylayer(for: model))
        // layerSets.append(createFlapslayer(for: model))

        return layerSets
    }

    // MARK: - Future layer Definitions

    /*
    /// Creates weapon bay doors layer (future)
    static func createWeaponBaylayer(for model: UsdModel) -> BinaryAnimationLayer {
        let bayJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
            .filter { $0.lowercased().contains("bay") || $0.lowercased().contains("weapon") }

        let mask = AnimationMask(jointPaths: bayJointPaths)

        return BinaryAnimationLayer(
            id: "weaponBay",
            mask: mask,
            transitionDuration: 2.0,
            initialState: .inactive
        )
    }

    /// Creates flaps layer (future)
    static func createFlapslayer(for model: UsdModel) -> ContinuousAnimationLayer {
        let flapJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
            .filter { $0.lowercased().contains("flap") }

        let mask = AnimationMask(jointPaths: flapJointPaths)

        return ContinuousAnimationLayer(
            id: "flaps",
            mask: mask,
            range: (0.0, 1.0),
            transitionSpeed: 0.5,
            initialValue: 0.0
        )
    }
    */
}
