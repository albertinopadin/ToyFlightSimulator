//
//  F35.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/21/23.
//

class F35: Aircraft {
    static let NAME: String = "F-35"

    override var cameraOffset: float3 {
        [0, -2, 24]
    }

    init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .Sketchfab_F35,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)

        // Set up the animator for skeletal animation control
        setupAnimator()
    }

    /// Creates and configures the AircraftAnimator for this F-35
    private func setupAnimator() {
        guard let usdModel = model as? UsdModel else {
            print("[F35] Warning: Model is not a UsdModel, animations will not be controlled")
            return
        }

        // Create the animator (AnimationLayerSystem handles hasExternalAnimator flag)
        animator = F35Animator(model: usdModel)

        print("[F35] F35Animator initialized with duration: \(animator?.gearAnimationDuration ?? 0)")
    }

    override func doUpdate() {
        super.doUpdate()

        // Handle landing gear toggle input
        if shouldUpdateOnPlayerInput && hasFocus {
            InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
                self.animator?.toggleGear()
            }
        }

        // Update the animator each frame
        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }
}
