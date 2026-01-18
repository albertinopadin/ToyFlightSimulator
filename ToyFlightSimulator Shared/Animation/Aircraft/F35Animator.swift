//
//  F35Animator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/11/26.
//

import Foundation

/// F-35 Lightning II specific animator with configured channels.
/// Automatically registers all F-35 animation channels on initialization.
final class F35Animator: AircraftAnimator {

    // MARK: - Initialization

    override init(model: UsdModel) {
        super.init(model: model)

        // Register all F-35 specific channels
        setupChannels()

        // Force initial pose update to ensure model starts in correct state
        layerSystem?.forceUpdateAllPoses()

        print("[F35Animator] Initialized with \(layerSystem?.channelCount ?? 0) channels")
    }

    // MARK: - Channel Setup

    override func setupChannels() {
        guard let model = model else {
            print("[F35Animator] Warning: No model available for channel setup")
            return
        }

        // Register all channels defined in F35AnimationConfig
//        let channels = F35AnimationConfig.createAllChannels(for: model)
        let channelSets = F35AnimationConfig.createAllChannelSets(for: model)
        for channelSet in channelSets {
            registerChannelSet(channelSet)
            print("[F35Animator] Registered channel set: \(channelSet.id)")
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
