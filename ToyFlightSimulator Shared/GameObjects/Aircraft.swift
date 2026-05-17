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
    
    /// Optional flight model.
    ///
    /// Assigning this property keeps `rigidBody.mass` in sync. Combined with
    /// `F22.rigidBody.didSet`, the rigid body's mass ends up correct regardless
    /// of whether the scene assigns `flightModel` before or after constructing
    /// the `RigidBody` — both orderings converge on `flightModel.mass`.
    ///
    /// ------------------------------------------------------------------
    /// FUTURE: Fix 3 — eliminate the duplicate mass field.
    /// ------------------------------------------------------------------
    /// `RigidBody.mass` and `FlightModel.mass` are two stored properties for
    /// the same physical quantity. They're kept in lockstep here and in
    /// `F22.rigidBody.didSet`. That works, but it's two assignment sites for
    /// one value, and it goes wrong silently if anyone mutates
    /// `flightModel.mass` at runtime (today F-22 mass is a `let`, so that
    /// can't happen — yet).
    ///
    /// The right long-term shape is for `RigidBody.mass` to be a *computed*
    /// property that reads from a `MassSource`: the flight model for aircraft,
    /// something else for non-aerodynamic bodies (spheres, ground planes,
    /// projectiles). No shadow field, no order-of-init to get wrong, one
    /// source of truth.
    ///
    /// Doing that requires designing the `MassSource` shape for non-aircraft
    /// rigid bodies and is out of scope for this refactor. See
    /// `debugging/claude/flight_model_refactor_mass_mismatch.md`
    /// (section "Recommended fixes — Fix 3") for the longer write-up.
    var flightModel: FlightModel? {
        didSet {
            if let flightModel {
                rigidBody?.mass = flightModel.mass
            }
        }
    }

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

        let controlInput = getControlInput()
        let deltaTurn = Float(GameTime.DeltaTime) * _turnSpeed
        let deltaMove = Float(GameTime.DeltaTime) * _moveSpeed
        
        if shouldUpdateOnPlayerInput && hasFocus {
            if let rigidBody, let flightModel {
                let rigidBodyState = rigidBody.getState()
                let force = flightModel.computeForce(state: rigidBodyState, input: controlInput)
                rigidBody.force += force
            } else {
                moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
            }
            
            applyPlayerAttitudeInput(deltaTurn: deltaTurn, controlInput: controlInput)
            applyPlayerSideMove(deltaMove: deltaMove)
            handleGearToggle()
        }

        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }
    
    internal func getControlInput() -> ControlInput {
        return ControlInput(throttle: InputManager.ContinuousCommand(.MoveFwd),
                            pitch: InputManager.ContinuousCommand(.Pitch),
                            roll: InputManager.ContinuousCommand(.Roll),
                            yaw: InputManager.ContinuousCommand(.Yaw))
    }

//    internal func applyPlayerAttitudeInput(deltaTurn: Float) {
//        rotateZ(-deltaTurn * InputManager.ContinuousCommand(.Roll))
//        rotateX(-deltaTurn * InputManager.ContinuousCommand(.Pitch))
//        rotateY(-deltaTurn * InputManager.ContinuousCommand(.Yaw))
//    }
    
    internal func applyPlayerAttitudeInput(deltaTurn: Float, controlInput: ControlInput) {
        rotateZ(-deltaTurn * controlInput.roll)
        rotateX(-deltaTurn * controlInput.pitch)
        rotateY(-deltaTurn * controlInput.yaw)
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

