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

        // Create the animator and tell the model it has an external controller
        animator = AircraftAnimator(model: usdModel)
        usdModel.hasExternalAnimator = true

        print("[F35] AircraftAnimator initialized with duration: \(animator?.duration ?? 0)")
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
