//
//  Aircraft.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class Aircraft: GameObject {
    public var shouldUpdateOnPlayerInput: Bool

    private var _moveSpeed: Float = 25.0
    private var _turnSpeed: Float = 4.0

    /// Optional animator for controlling aircraft animations (gear, flaps, etc.)
    /// Subclasses with skeletal animation set this via `setupAnimator(_:)`.
    var animator: AircraftAnimator?

    /// Returns true if the landing gear is down.
    /// Aircraft without an animator are treated as having gear permanently down.
    var isGearDown: Bool {
        animator?.isGearDown ?? true
    }

    public var cameraOffset: float3 {
        [0, 10, -20]
    }

    init(name: String, modelType: ModelType, scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        self.shouldUpdateOnPlayerInput = shouldUpdateOnPlayerInput
        super.init(name: name, modelType: modelType)
        self.setScale(scale)
        print("[Aircraft init] name: \(name), scale: \(scale)")
        self.hasFocus = true  // TODO: This doesn't look right...
    }

    /// Convenience for subclasses that use skeletal animation.
    /// Casts the model to `UsdModel`, builds an animator via `make`, and stores it.
    /// No-op (with a warning) if the model isn't a UsdModel.
    func setupAnimator<A: AircraftAnimator>(_ make: (UsdModel) -> A) {
        guard let usdModel = model as? UsdModel else {
            print("[\(getName())] Warning: Model is not a UsdModel; animations disabled")
            return
        }
        animator = make(usdModel)
    }

    override func doUpdate() {
        super.doUpdate()

        if shouldUpdateOnPlayerInput && hasFocus {
            if let ac = self as? F22 {
                // Using forces:
                // Engine:
                let engineForce: float3 = getFwdVector() * ac.engineThrust * 10 * InputManager.ContinuousCommand(.MoveFwd)
                let lift: float3 = getUpVector() * (self.rigidBody?.velocity.z ?? 1.0) * 100.0
                self.rigidBody?.force = engineForce + lift
                
                let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
                
                self.rotateZ(-deltaTurn * InputManager.ContinuousCommand(.Roll))
                self.rotateX(-deltaTurn * InputManager.ContinuousCommand(.Pitch))
                self.rotateY(-deltaTurn * InputManager.ContinuousCommand(.Yaw))
                
                let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
                self.moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
            } else {
                let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
                let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
                
                self.rotateZ(-deltaTurn * InputManager.ContinuousCommand(.Roll))
                self.rotateX(-deltaTurn * InputManager.ContinuousCommand(.Pitch))
                self.rotateY(-deltaTurn * InputManager.ContinuousCommand(.Yaw))
                
                self.moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
                self.moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
            }
            
            InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) { [weak self] in
                self?.animator?.toggleGear()
            }
        }

        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }
}

