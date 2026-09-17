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
    /// N3: below these, stick input / residual rotation rates are treated as
    /// zero, skipping per-frame transform writes that would otherwise dirty
    /// the aircraft's whole subtree (camera included) every frame while idle.
    private static let inputEpsilon: Float = 1e-5
    private static let rateEpsilon: Float = 1e-4   // rad/s; ~0.006°/s

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
    
    /// Raycast landing-gear suspension; nil for aircraft without a gear spec
    /// (they rest on their collision geometry, as in Phase A). Installed by
    /// the scene next to the rigid body.
    var gearSuspension: LandingGearSuspension?
    
    /// Optional flight model.
    ///
    /// Assigning this property syncs the body's mass and inertia through
    /// `syncMassProperties`, as does assigning `rigidBody`, so the body ends
    /// up correct whether the scene sets the model before or after the body.
    /// `RigidBody.mass` and `FlightModel.mass` are still two stored
    /// properties for one quantity (FUTURE Fix 3, a computed mass reading a
    /// source): see `debugging/claude/flight_model_refactor_mass_mismatch.md`
    /// (section "Recommended fixes — Fix 3") for the write-up.
    var flightModel: FlightModel? {
        didSet { syncMassProperties() }
    }
    
    /// Control input sampled once per frame in doUpdate and read by
    /// generateForces on every physics substep. nil while the aircraft is
    /// unfocused or not player-driven, so there is no flight force without
    /// focus, as before.
    private var latestControlInput: ControlInput?
    
    override var rigidBody: RigidBody? {
        didSet {
            syncMassProperties()
            
            // The world calls this from inside the physics step. Weak self:
            // the aircraft owns the body, so a strong capture would be a cycle.
            rigidBody?.forceGenerator = { [weak self] _, substepDelta, world in
                self?.generateForces(substepDelta: substepDelta, world: world)
            }
        }
    }
    
    /// Aircraft with a body and a flight model fly by forces and torques in
    /// generateForces. The rest move kinematically, as before: the F-16
    /// wingman has no body, FreeCamFlightboxScene's jet has no flight model.
    private var hasFlightPhysics: Bool { rigidBody != nil && flightModel != nil }

    /// Returns true if the landing gear is down.
    /// Aircraft without an animator are treated as having gear permanently down.
    var isGearDown: Bool {
        animator?.isGearDown ?? true
    }

    public var cameraOffset: float3 {
        [0, 10, -20]
    }

    /// Which picker type this airframe is; nil for aircraft outside the
    /// picker. Carried in every telemetry snapshot.
    public let aircraftType: AircraftType?
    /// The last snapshot built (UpdateThread only). While the nose is
    /// vertical, heading and bank are undefined and hold these values.
    private var lastTelemetrySnapshot: AircraftTelemetry
    
    init(name: String,
         aircraftType: AircraftType? = nil,
         modelType: ModelType,
         scale: Float = 1.0,
         shouldUpdateOnPlayerInput: Bool = true) {
        self.aircraftType = aircraftType
        self.shouldUpdateOnPlayerInput = shouldUpdateOnPlayerInput
        self.lastTelemetrySnapshot = AircraftTelemetry(aircraftType: aircraftType,
                                                       heading: 0,
                                                       altitudeInMeters: 0,
                                                       forwardSpeedInMetersPerSecond: 0,
                                                       pitchAngle: 0,
                                                       rollAngle: 0)
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
    
    /// Mass and inertia come from the flight model. Both didSets call this,
    /// so either assignment order converges. An aircraft without a flight
    /// model has infinite inertia and the kinematic attitude path; removing
    /// the model restores that (the tensor, and the angular state the
    /// integrator would otherwise keep applying next to the kinematic
    /// rotation). Mass is left where it was: nothing else authors it.
    private func syncMassProperties() {
        guard let rigidBody else { return }
        guard let flightModel else {
            rigidBody.inverseInertiaLocal = RigidBody.infiniteInertia
            rigidBody.angularVelocity = .zero
            rigidBody.torque = .zero
            return
        }
        rigidBody.mass = flightModel.mass
        rigidBody.inverseInertiaLocal = float3x3(diagonal: 1 / flightModel.inertia)
    }

    override func doUpdate() {
        super.doUpdate()

        let dt = Float(GameTime.DeltaTime)

        if shouldUpdateOnPlayerInput && hasFocus {
            let controlInput = getControlInput()
            let deltaMove = dt * _moveSpeed
            
            // Flight forces and the attitude torque are computed in
            // generateForces, inside the physics step. Here we only refresh
            // the input it reads.
            latestControlInput = controlInput
            if !hasFlightPhysics {
                // Kinematic path: the F-16 wingman, and a jet without a flight
                // model. Throttle moves the node and the stick turns it
                // through the damped rate filter.
                moveAlongVector(getFwdVector(), distance: deltaMove * controlInput.throttle)
                applyPlayerAttitudeInput(deltaTime: dt, controlInput: controlInput)
                // The A/D strafe teleports the node; on the physics path it
                // would slide the jet through its own tire model.
                applyPlayerSideMove(deltaMove: deltaMove)
            }
            
            handleGearToggle()
        } else {
            latestControlInput = nil
            if !hasFlightPhysics {
                // Kinematic path: bleed off the carried rates so resuming
                // control does not snap into a stale tumble. Keeps applying
                // the rotation, so a released stick damps out instead of
                // freezing in place. (On the physics path the controller
                // does this inside the step, with the command at zero.)
                decayAttitudeRates(deltaTime: dt)
            }
        }

        animator?.update(deltaTime: dt)
    }
    
    /// This frame's pilot-facing flight data. UpdateThread only: it reads the
    /// world matrix and the body's velocity (both final after the scene
    /// traversal, which is where `GameScene.update` calls it) and keeps the
    /// returned snapshot so heading and bank hold their last defined values
    /// while the nose is vertical. The math is `AircraftTelemetry.make`, a
    /// pure function tested without Metal.
    public func getTelemetrySnapshot() -> AircraftTelemetry {
        let snapshot = AircraftTelemetry.make(aircraftType: aircraftType,
                                              forward: getFwdVector(),
                                              right: getRightVector(),
                                              up: getUpVector(),
                                              velocity: rigidBody?.velocity ?? .zero,
                                              worldPosition: getWorldPosition(),
                                              previous: lastTelemetrySnapshot)
        lastTelemetrySnapshot = snapshot
        return snapshot
    }
    
    /// Called by the physics world at the top of each substep, on the
    /// UpdateThread, from live body state. doUpdate runs later in the frame,
    /// after the step, and only refreshes the cached input.
    func generateForces(substepDelta: Float, world: PhysicsWorld) {
        guard let rigidBody else { return }
        
        if let flightModel {
            if let input = latestControlInput, let state = rigidBody.getState() {
                rigidBody.force += flightModel.computeForce(state: state, input: input)
            }
            
            // Attitude by torque, outside the input guard: without focus the
            // command is zero and the controller damps the body's rates, as
            // the kinematic filter's decay did. The controller works in body
            // axes (Rᵀ ω in, a body-frame torque out, R back to world), so
            // its per-axis time constants stay attached to the airframe.
            let rotation = rigidBody.pose().rotation
            let commandedRates = AttitudeRateController.commandedRates(latestControlInput, attitudeDynamics)
            let torqueBody = AttitudeRateController.torque(commandedRates: commandedRates,
                                                           bodyRates: rotation.transpose * rigidBody.angularVelocity,
                                                           inertia: flightModel.inertia,
                                                           dynamics: attitudeDynamics,
                                                           substepDelta: substepDelta)
            rigidBody.torque += rotation * torqueBody
        }

        // Outside the input guard: a parked, unfocused aircraft must still be
        // held up. isGearDown is animator state written only in doUpdate, so
        // it is stable across a frame's substeps.
        gearSuspension?.accumulateForces(body: rigidBody,
                                         gearDeployed: isGearDown,
                                         brake: latestControlInput?.brake ?? 0,
                                         steer: latestControlInput?.yaw ?? 0,
                                         world: world,
                                         substepDelta: substepDelta)
    }
    
    internal func getControlInput() -> ControlInput {
        return ControlInput(throttle: InputManager.ContinuousCommand(.MoveFwd),
                            pitch: InputManager.ContinuousCommand(.Pitch),
                            roll: InputManager.ContinuousCommand(.Roll),
                            yaw: InputManager.ContinuousCommand(.Yaw),
                            brake: InputManager.ContinuousCommand(.Brake))
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

        applyAttitudeRates(deltaTime: deltaTime)
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

        applyAttitudeRates(deltaTime: deltaTime)
    }

    /// Applies the accumulated rates, snapping sub-epsilon residuals to
    /// exactly 0 so a settled aircraft performs zero rotate() calls (and never
    /// dirties its subtree) until the next real input. The exponential decay
    /// alone never reaches zero, which previously kept the transform dirty
    /// forever after the stick was released.
    private func applyAttitudeRates(deltaTime: Float) {
        if abs(currentPitchRate) < Self.rateEpsilon { currentPitchRate = 0 } else { rotateX(-currentPitchRate * deltaTime) }
        if abs(currentRollRate)  < Self.rateEpsilon { currentRollRate  = 0 } else { rotateZ(-currentRollRate  * deltaTime) }
        if abs(currentYawRate)   < Self.rateEpsilon { currentYawRate   = 0 } else { rotateY(-currentYawRate   * deltaTime) }
    }

    internal func applyPlayerSideMove(deltaMove: Float) {
        let side = InputManager.ContinuousCommand(.MoveSide)
        guard abs(side) > Self.inputEpsilon else { return }
        moveAlongVector(getRightVector(), distance: deltaMove * side)
    }

    internal func handleGearToggle() {
        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) { [weak self] in
            self?.animator?.toggleGear()
        }
    }
}

