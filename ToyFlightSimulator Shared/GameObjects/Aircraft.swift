//
//  Aircraft.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 2/11/23.
//

import MetalKit

/// Per-axis kinematic response parameters for first-order attitude lag.
/// `maxRate` is the steady-state rotation rate at full stick deflection (rad/s).
/// `timeConstant` (τ) is how long it takes the current rate to reach ~63% of
/// commanded; ~95% takes `3·τ`. See `plans/claude/damped_attitude_response.md`.
struct AttitudeDynamics {
    var maxPitchRate: Float   = 1.0   // rad/s (~57°/s)
    var maxRollRate: Float    = 4.7   // rad/s (~270°/s)
    var maxYawRate: Float     = 0.5   // rad/s (~29°/s)

    var pitchTimeConstant: Float = 0.25  // seconds
    var rollTimeConstant: Float  = 0.15
    var yawTimeConstant: Float   = 0.40
}

class Aircraft: GameObject {
    public var shouldUpdateOnPlayerInput: Bool

    internal var _moveSpeed: Float = 25.0
    /// Retained for `applyPlayerAttitudeInputImmediate`, the pre-damping
    /// snap-to-target rotation path kept for debugging. Not consumed by the
    /// default update path, which uses `attitudeDynamics` instead.
    internal var _turnSpeed: Float = 4.0

    /// Per-axis response parameters for the damped attitude filter.
    /// Subclasses override in init if they want type-specific feel.
    var attitudeDynamics = AttitudeDynamics()

    /// Current angular rates carried across frames by the lag filter.
    /// Decays toward zero on the `!hasFocus` path so resuming control doesn't
    /// snap into a stale tumble.
    private var currentPitchRate: Float = 0
    private var currentRollRate: Float = 0
    private var currentYawRate: Float = 0

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
    
    override var rigidBody: RigidBody? {
        didSet {
            // Mass-sync mirror of `Aircraft.flightModel.didSet` — see there for
            // the Fix 3 future-work note. Together these two didSets make mass
            // converge regardless of assignment order.
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

        let dt = Float(GameTime.DeltaTime)

        if shouldUpdateOnPlayerInput && hasFocus {
            let controlInput = getControlInput()
            let deltaMove = dt * _moveSpeed

            if let rigidBody,
               let flightModel,
               let rigidBodyState = rigidBody.getState() {
                let force = flightModel.computeForce(state: rigidBodyState, input: controlInput)
                rigidBody.force += force
            } else {
                moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
            }

            applyPlayerAttitudeInput(deltaTime: dt, controlInput: controlInput)
            applyPlayerSideMove(deltaMove: deltaMove)
            handleGearToggle()
        } else {
            // Lost control — bleed off accumulated rotation rate so resuming
            // control doesn't snap-resume a tumble. Continues to apply the
            // rotation, so a released stick damps out physically instead of
            // freezing in place.
            decayAttitudeRates(deltaTime: dt)
        }

        animator?.update(deltaTime: dt)
    }
    
    internal func getControlInput() -> ControlInput {
        return ControlInput(throttle: InputManager.ContinuousCommand(.MoveFwd),
                            pitch: InputManager.ContinuousCommand(.Pitch),
                            roll: InputManager.ContinuousCommand(.Roll),
                            yaw: InputManager.ContinuousCommand(.Yaw))
    }
    
    /// Snap-to-target rotation: full stick → full rate in one frame.
    /// Retained for debugging; not on the default update path. To use,
    /// swap the `applyPlayerAttitudeInput(deltaTime:...)` call in `doUpdate`
    /// for `applyPlayerAttitudeInputImmediate(deltaTurn: dt * _turnSpeed, ...)`.
    internal func applyPlayerAttitudeInputImmediate(deltaTurn: Float, controlInput: ControlInput) {
        rotateZ(-deltaTurn * controlInput.roll)
        rotateX(-deltaTurn * controlInput.pitch)
        rotateY(-deltaTurn * controlInput.yaw)
    }

    /// First-order lag filter on rotation rate. Pilot stick commands a rate
    /// (`stick * maxRate`); the current rate ramps toward it with time
    /// constant τ. The applied rotation is `ω · dt`. Sign convention matches
    /// the legacy immediate path — see "Coordinate Conventions" in CLAUDE.md.
    internal func applyPlayerAttitudeInput(deltaTime: Float, controlInput: ControlInput) {
        let dyn = attitudeDynamics

        let cmdPitchRate = controlInput.pitch * dyn.maxPitchRate
        let cmdRollRate  = controlInput.roll  * dyn.maxRollRate
        let cmdYawRate   = controlInput.yaw   * dyn.maxYawRate

        // Frame-rate-independent exponential smoothing: α = 1 - e^(-dt/τ).
        // The exact form (vs. α = dt/τ) keeps 30/60/120 Hz steps converging
        // to the same trajectory.
        let pitchAlpha = 1 - exp(-deltaTime / dyn.pitchTimeConstant)
        let rollAlpha  = 1 - exp(-deltaTime / dyn.rollTimeConstant)
        let yawAlpha   = 1 - exp(-deltaTime / dyn.yawTimeConstant)

        currentPitchRate += (cmdPitchRate - currentPitchRate) * pitchAlpha
        currentRollRate  += (cmdRollRate  - currentRollRate)  * rollAlpha
        currentYawRate   += (cmdYawRate   - currentYawRate)   * yawAlpha

        rotateX(-currentPitchRate * deltaTime)
        rotateZ(-currentRollRate  * deltaTime)
        rotateY(-currentYawRate   * deltaTime)
    }

    /// Decay accumulated rates toward zero when not under player control.
    /// Uses the same τ as the active path so bleed-off feels symmetric with
    /// spool-up. Continues applying rotation so a released stick damps out
    /// physically rather than freezing attitude.
    private func decayAttitudeRates(deltaTime: Float) {
        let dyn = attitudeDynamics
        let pitchAlpha = 1 - exp(-deltaTime / dyn.pitchTimeConstant)
        let rollAlpha  = 1 - exp(-deltaTime / dyn.rollTimeConstant)
        let yawAlpha   = 1 - exp(-deltaTime / dyn.yawTimeConstant)

        currentPitchRate += (0 - currentPitchRate) * pitchAlpha
        currentRollRate  += (0 - currentRollRate)  * rollAlpha
        currentYawRate   += (0 - currentYawRate)   * yawAlpha

        rotateX(-currentPitchRate * deltaTime)
        rotateZ(-currentRollRate  * deltaTime)
        rotateY(-currentYawRate   * deltaTime)
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

