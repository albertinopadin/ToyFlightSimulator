//
//  F35Animator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/11/26.
//

import Foundation

/// F-35 Lightning II specific animator with configured animation layers.
/// Automatically registers all F-35 animation layers on initialization.
final class F35Animator: AircraftAnimator {

    // MARK: - Initialization

    override init(model: UsdModel) {
        super.init(model: model)

        // Register all F-35 specific layers
        setupLayers()

        // Force initial pose update to ensure model starts in correct state
        layerSystem?.forceUpdateAllPoses()

        print("[F35Animator] Initialized with \(layerSystem?.channelCount ?? 0) channels")
    }

    // MARK: - Layer Setup

    override func setupLayers() {
        guard let model = model else {
            print("[F35Animator] Warning: No model available for layer setup")
            return
        }

        // Register all layers defined in F35AnimationConfig
        let layers = F35AnimationConfig.createLayers(for: model)
        for layer in layers {
            registerLayer(layer)
            print("[F35Animator] Registered layer: \(layer.id)")
        }
    }

    // MARK: - F-35 Specific Methods

    // Future: Add F-35 specific convenience methods here
    // For example:

    /*
    /// Open weapon bay doors
    func openWeaponBay() {
        channel(F35AnimationConfig.weaponBayChannelID, as: BinaryAnimationChannel.self)?.activate()
    }

    /// Close weapon bay doors
    func closeWeaponBay() {
        channel(F35AnimationConfig.weaponBayChannelID, as: BinaryAnimationChannel.self)?.deactivate()
    }

    /// Set flap position (0.0 = retracted, 1.0 = fully extended)
    func setFlaps(_ position: Float) {
        channel(F35AnimationConfig.flapsChannelID, as: ContinuousAnimationChannel.self)?.setValue(position)
    }
    */
}
