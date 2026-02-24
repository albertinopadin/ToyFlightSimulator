//
//  F22AnimationConfig.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/23/26.
//

struct F22AnimationConfig {
    /// Standard layer ID for landing gear
    static let landingGearLayerID = "landingGear"

    // Future layer IDs:
    // static let weaponBayLayerID = "weaponBay"
    // static let canopyLayerID = "canopy"
    // static let flapsLayerID = "flaps"

    /// Creates the landing gear layer (group of channels) for F-35
    /// - Parameter model: The UsdModel containing animation data
    /// - Returns: A configured AnimationLayer grouping all landing gear channels
    static func createLandingGearLayer(for model: UsdModel) -> AnimationLayer {
        var channels: [AnimationChannel] = []

        print("[F22 createLandingGearLayer] model meshSkeletonMap: \(model.meshSkeletonMap)")
        print("[F22 createLandingGearLayer] model skeletonAnimationMap: \(model.skeletonAnimationMap)")
        print("[F22 createLandingGearLayer] model skeleton: \(model.skeletons["/root/Armature/Armature"]!.jointPaths)")

        // For now using all animation clips since the F-35 model only has landing gear animations:
        for (i, animationClip) in model.animationClips.values.enumerated() {
            guard let skeletonAnimation = model.skeletonAnimationMap.first(where: {
                $0.value == animationClip.name
            }) else {
                fatalError("F-22 model has no animation clip named: \(animationClip.name)")
            }

            let meshIndices = model.meshSkeletonMap.filter { $0.value == skeletonAnimation.key }.map { $0.key }

            print("[F22 createLandingGearLayer] meshIndices: \(meshIndices) for animationClip: \(animationClip.name)")

            guard !meshIndices.isEmpty else {
                fatalError("F-22 model has no mesh indices for animation clip: \(animationClip.name)")
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
