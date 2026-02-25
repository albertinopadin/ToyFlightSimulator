//
//  F22AnimationConfig.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/23/26.
//

struct F22AnimationConfig {
    /// Standard layer ID for landing gear
    static let landingGearLayerID = "landingGear"
    static let flaperonLayerID = "flaperon"  // TODO: Provide this to the aircraft animator so you don't have to redeclare

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
        layers.append(createFlaperonLayer(for: model))

        // Future layers can be added here:
        // layers.append(createWeaponBayLayer(for: model))
        // layers.append(createCanopyLayer(for: model))
        // layers.append(createFlapsLayer(for: model))

        return layers
    }
    
    /// Maximum flaperon deflection angle in radians (~25 degrees)
    static let flaperonMaxDeflection: Float = 25.0 * (.pi / 180.0)

    /// Rotation axis for flaperons in bone-local space.
    /// Verify against the model's bone orientation — may need to be adjusted.
    static let flaperonRotationAxis: float3 = float3(0, 1, 0).normalize()

    /// Creates the flaperon layer using procedural animation channels.
    /// Flaperons are driven by player roll input, not animation clips.
    static func createFlaperonLayer(for model: UsdModel) -> AnimationLayer {
        let allJointPaths = model.skeletons.values.flatMap { $0.jointPaths }
        let leftFlaperonPath = allJointPaths.first { $0.hasSuffix("LeftFlaperon") }
        let rightFlaperonPath = allJointPaths.first { $0.hasSuffix("RightFlaperon") }

        var jointConfigs: [ProceduralJointConfig] = []

        if let left = leftFlaperonPath {
            jointConfigs.append(ProceduralJointConfig(
                jointPath: left,
                axis: flaperonRotationAxis,
                maxDeflection: flaperonMaxDeflection,
                inverted: false
            ))
        } else {
            print("[F22AnimationConfig] Warning: LeftFlaperon joint not found in skeleton")
        }

        if let right = rightFlaperonPath {
            jointConfigs.append(ProceduralJointConfig(
                jointPath: right,
                axis: flaperonRotationAxis,
                maxDeflection: flaperonMaxDeflection,
                inverted: false  // Opposite deflection for roll
            ))
        } else {
            print("[F22AnimationConfig] Warning: RightFlaperon joint not found in skeleton")
        }

        let allPaths = jointConfigs.map { $0.jointPath }
        let mask = AnimationMask(jointPaths: allPaths)

        let channel = ProceduralAnimationChannel(
            id: "flaperons",
            mask: mask,
            range: (-1.0, 1.0),
            transitionSpeed: 5.0,  // Fast response for control surfaces
            initialValue: 0.0,
            jointConfigs: jointConfigs
        )

        return AnimationLayer(id: flaperonLayerID, channels: [channel])
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
