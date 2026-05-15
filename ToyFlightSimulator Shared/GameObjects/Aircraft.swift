//
//  Aircraft.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

class Aircraft: GameObject {
    public var shouldUpdateOnPlayerInput: Bool

    internal var _moveSpeed: Float = 25.0
    internal var _turnSpeed: Float = 4.0

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
            let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
            let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed

            applyPlayerAttitudeInput(deltaTurn: deltaTurn)
            moveAlongVector(getFwdVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveFwd))
            applyPlayerSideMove(deltaMove: deltaMove)
            handleGearToggle()
        }

        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }

    internal func applyPlayerAttitudeInput(deltaTurn: Float) {
        rotateZ(-deltaTurn * InputManager.ContinuousCommand(.Roll))
        rotateX(-deltaTurn * InputManager.ContinuousCommand(.Pitch))
        rotateY(-deltaTurn * InputManager.ContinuousCommand(.Yaw))
    }

    internal func applyPlayerSideMove(deltaMove: Float) {
        moveAlongVector(getRightVector(), distance: deltaMove * InputManager.ContinuousCommand(.MoveSide))
    }

    internal func handleGearToggle() {
        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) { [weak self] in
            self?.animator?.toggleGear()
        }
    }
}

