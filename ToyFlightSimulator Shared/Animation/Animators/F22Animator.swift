//
//  F22Animator.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/23/26.
//

final class F22Animator: AircraftAnimator {
    override init(model: UsdModel) {
        super.init(model: model)

        // Register all F-35 specific layers
        setupLayers()

        // Force initial pose update to ensure model starts in correct state
        layerSystem?.forceUpdateAllPoses()

        print("[F22Animator] Initialized with \(layerSystem?.channelCount ?? 0) channels")
    }
    
    override func setupLayers() {
        guard let model = model else {
            print("[F22Animator] Warning: No model available for layer setup")
            return
        }
        
        let layers = F22AnimationConfig.createLayers(for: model)
        for layer in layers {
            registerLayer(layer)
            print("[F35Animator] Registered layer: \(layer.id)")
        }
    }
}
