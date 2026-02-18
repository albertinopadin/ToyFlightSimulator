//
//  F35Animator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/11/26.
//

import Foundation

/// F-35 Lightning II specific animator with configured layers.
/// Automatically registers all F-35 animation layers on initialization.
final class F35Animator: AircraftAnimator {

    // MARK: - Initialization

    override init(model: UsdModel) {
        super.init(model: model)

        // Register all F-35 specific layers
        setuplayers()

        // Force initial pose update to ensure model starts in correct state
        layerSystem?.forceUpdateAllPoses()

        print("[F35Animator] Initialized with \(layerSystem?.layerCount ?? 0) layers")
    }

    // MARK: - layer Setup

    override func setuplayers() {
        guard let model = model else {
            print("[F35Animator] Warning: No model available for layer setup")
            return
        }

        // Register all layers defined in F35AnimationConfig
//        let layers = F35AnimationConfig.createAlllayers(for: model)
        let layerSets = F35AnimationConfig.createLayerSets(for: model)
        for layerSet in layerSets {
            registerlayerSet(layerSet)
            print("[F35Animator] Registered layer set: \(layerSet.id)")
        }
    }

    // MARK: - F-35 Specific Methods

    // Future: Add F-35 specific convenience methods here
    // For example:

    /*
    /// Open weapon bay doors
    func openWeaponBay() {
        layer(F35AnimationConfig.weaponBaylayerID, as: BinaryAnimationLayer.self)?.activate()
    }

    /// Close weapon bay doors
    func closeWeaponBay() {
        layer(F35AnimationConfig.weaponBaylayerID, as: BinaryAnimationLayer.self)?.deactivate()
    }

    /// Set flap position (0.0 = retracted, 1.0 = fully extended)
    func setFlaps(_ position: Float) {
        layer(F35AnimationConfig.flapslayerID, as: ContinuousAnimationLayer.self)?.setValue(position)
    }
    */
}
