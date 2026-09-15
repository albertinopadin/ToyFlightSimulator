//
//  GearSuspensionWorldTests.swift
//  ToyFlightSimulatorTests
//
//  B.5 (B-suspension, part 2): the B-phase counterpart of CompoundBodyTests —
//  the real LandingGearSuspension driving the live F-22 gear spec through the
//  body's force hook, over the compound colliders and corrected response, end
//  to end and Metal-free (detached bodies, plan rule 3). D.2 adds the ground
//  handling cases: the tire model's brakes, grip, rolling resistance, and
//  holding, as physics numbers on the same rig (the plan keeps aircraft out
//  of the parity goldens). D.3 gives the rig the F-22's inertia tensor and
//  the attitude rate controller, as production installs them, so the jet
//  pitches and rolls on its struts: the geometric load split, a nose-last
//  touchdown, a one-wheel arrival, nosewheel steering, the braking dive, and
//  the two-cap belly rest. Every band was reproduced in a scratch replay of
//  the struts, the tire solve, the controller, the pair solve, and the Verlet
//  step before the tests ran.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Gear suspension (world)", .tags(.physics))
struct GearSuspensionWorldTests {
    private static let dt: Float = 1.0 / 60.0

    /// Body-origin height at which the F-22's struts first touch level ground:
    /// every authored strut reaches 2.05 m below the origin.
    private static let strutContactHeight: Float =
        AircraftLandingGearSpec.spec(for: .f22_cgtrader)[0].reachBelowOrigin

    /// The same for a rotated body: the height of the origin at which the
    /// lowest uncompressed contact patch, attach point minus the reach along
    /// body −Y, touches level ground. 2.05 m for the identity rotation.
    private static func strutContactHeight(rotation: float3x3) -> Float {
        AircraftLandingGearSpec.spec(for: .f22_cgtrader).map { strut -> Float in
            -(rotation * (strut.attachLocal - float3(0, strut.reach, 0))).y
        }.max() ?? 0
    }

    /// Pitch from the body's forward axis, degrees, nose-up positive.
    private func pitchDegrees(_ body: RigidBody) -> Float {
        asin(body.pose().rotation.forward.y) * 180 / .pi
    }

    /// Roll from the body's right axis, degrees, right wing up positive.
    private func rollDegrees(_ body: RigidBody) -> Float {
        asin(body.pose().rotation.right.y) * 180 / .pi
    }

    /// Metal-free stand-in for Aircraft: drives the real LandingGearSuspension
    /// and the AttitudeRateController from the body's force hook, in the
    /// order Aircraft.generateForces runs them (the flight model's force,
    /// the controller's torque, then the suspension, whose tire solve
    /// predicts with both). The body carries the F-22's tensor, so it pitches
    /// and rolls under the gear as in production. Node rotation and the
    /// animator gate are B.5's in-app checks. `brake` is the B key (0…1),
    /// `steer` the yaw command (−1…1, Q/E), `extraForce` stands in for the
    /// flight model's thrust, `commandedRates` for the stick (zero: an
    /// unfocused aircraft, whose controller only damps). The hook captures
    /// the rig weakly: a test must keep its `rig` alive through the run (use
    /// it afterwards), or the suspension silently stops and the jet drops
    /// onto its frictionless belly.
    private final class GearRig {
        let body: RigidBody
        let suspension: LandingGearSuspension
        var gearDeployed = true
        var brake: Float = 0
        var steer: Float = 0
        var extraForce: float3 = .zero
        /// Body-axis rate command (pitch, yaw, roll), rad/s.
        var commandedRates: float3 = .zero
        /// The F-22's tensor and time constants, as applyAircraftSwap and
        /// Aircraft.generateForces install and read them.
        let inertia: float3 = F22SimpleFlightModel().inertia
        let dynamics = AttitudeDynamics()

        init(body: RigidBody, struts: [SuspensionStrut]) {
            self.body = body
            self.suspension = LandingGearSuspension(struts: struts)
            body.inverseInertiaLocal = float3x3(diagonal: 1 / inertia)
            body.forceGenerator = { [weak self] body, substepDelta, world in
                guard let self else { return }
                body.force += self.extraForce
                // The controller in body axes, its torque back in world axes
                // — Aircraft.generateForces line for line.
                let rotation = body.pose().rotation
                let torqueBody = AttitudeRateController.torque(commandedRates: self.commandedRates,
                                                               bodyRates: rotation.transpose * body.angularVelocity,
                                                               inertia: self.inertia,
                                                               dynamics: self.dynamics,
                                                               substepDelta: substepDelta)
                body.torque += rotation * torqueBody
                self.suspension.accumulateForces(body: body,
                                                 gearDeployed: self.gearDeployed,
                                                 brake: self.brake,
                                                 steer: self.steer,
                                                 world: world,
                                                 substepDelta: substepDelta)
            }
        }
    }

    private func makeF22OnGear(startY: Float,
                               velocityY: Float = 0,
                               rotation: float3x3 = matrix_identity_float3x3,
                               updateType: PhysicsUpdateType = .HeckerVerlet)
        -> (world: PhysicsWorld, body: RigidBody, rig: GearRig) {
        let body = RigidBody(detachedAt: [0, startY, 0])
        body.mass = 30_000                                    // the flight model's mass
        body.restitution = 0.2
        body.velocity = [0, velocityY, 0]
        body.setRotation(rotation)
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let rig = GearRig(body: body, struts: AircraftLandingGearSpec.spec(for: .f22_cgtrader))
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: updateType)
        world.useBroadPhase = false
        return (world, body, rig)
    }

    @Test("the F-22 settles on its struts at ride height, gravity on, fuselage clear, with the geometric load split and its pitch")
    func settlesOnStruts() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        var airframeTouched = false
        body.onContact = { _, _ in airframeTouched = true }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // 10 s

        #expect(body.shouldApplyGravity)
        #expect(rig.suspension.weightOnWheels)
        #expect(abs(body.getPosition().y - 1.93) <= 0.02,
                "Σk·x = W gives x ≈ 0.119, ride height = 2.05 − x ≈ 1.93; the pitch equilibrium moves the origin 2 mm")
        // With pitch freedom the load splits by geometry, not spring rate:
        // the nose carries 0.9/6.1 of the weight (43 kN) on the softer strut,
        // the mains 125 kN each. Replay: 0.165, 0.114, 0.114; pitch −0.48°.
        #expect(abs(rig.suspension.compressions[0] - 0.162) <= 0.01, "nose: 43 kN / 268 kN/m")
        #expect(abs(rig.suspension.compressions[1] - 0.114) <= 0.01, "main: 125 kN / 1.1 MN/m")
        #expect(abs(rig.suspension.compressions[2] - 0.114) <= 0.01)
        #expect(abs(pitchDegrees(body) - (-0.45)) <= 0.15, "48 mm of nose drop over the 6.1 m wheelbase")
        #expect(abs(rollDegrees(body)) <= 0.05)
        #expect(simd_length(body.velocity) <= 0.05)
        #expect(!airframeTouched,
                "on its wheels the fuselage capsule (bottom −1.05) stays about 0.88 m clear")
    }

    @Test("gear up: the same body falls through the struts to the Phase A belly rest")
    func gearUpFallsToBelly() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        rig.gearDeployed = false
        var contactNames: Set<String> = []
        body.onContact = { contact, _ in
            if let name = contact.colliderNameA { contactNames.insert(name) }
        }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }

        #expect(abs(body.getPosition().y - 1.05) <= 0.05,
                "CompoundBodyTests' settle, with the suspension present but retracted")
        #expect(contactNames == ["fuselage"])
        #expect(!rig.suspension.weightOnWheels)
    }

    @Test("touchdown reports the incoming sink; a firm arrival overloads, a gentle one does not")
    func touchdownAndOverloadEvents() {
        // Start 1 cm above strut contact so the commanded velocity IS the
        // arrival velocity, one substep of gravity (0.08 m/s) aside. From
        // higher up the free fall before contact adds to it: 2.2 m arrives at
        // 4.4 m/s, not 4.
        let start = Self.strutContactHeight + 0.01

        // 4 m/s sink: the mains' damper alone gives 146 kN·s/m · 4 ≈ 584 kN,
        // past the 400 kN clamp, so the overload event fires on the rising edge.
        let firm = makeF22OnGear(startY: start, velocityY: -4)
        var firstSink: Float? = nil
        var overloadedStruts: Set<String> = []
        firm.rig.suspension.onLandingGearEvent = { event in
            switch event {
                case .touchdown(let sinkRate, _):
                    if firstSink == nil { firstSink = sinkRate }
                case .gearOverload(let strutName, _, _):
                    overloadedStruts.insert(strutName)
                case .liftoff:
                    break
            }
        }
        for _ in 0..<300 { firm.world.update(deltaTime: Self.dt) }
        #expect(firstSink != nil && abs(firstSink! - 4.0) <= 0.15)
        #expect(overloadedStruts.contains("mainGearLeft") && overloadedStruts.contains("mainGearRight"))

        // 0.5 m/s: damper under 110 kN and the spring peaks well under the clamp.
        let gentle = makeF22OnGear(startY: start, velocityY: -0.5)
        var gentleOverloads = 0
        gentle.rig.suspension.onLandingGearEvent = { if case .gearOverload = $0 { gentleOverloads += 1 } }
        for _ in 0..<300 { gentle.world.update(deltaTime: Self.dt) }
        #expect(gentleOverloads == 0)
        #expect(gentle.rig.suspension.weightOnWheels)
    }

    @Test("a body pushed upward leaves cleanly: struts push, never pull")
    func strutsNeverPull() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // settle first
        var sawLiftoff = false
        rig.suspension.onLandingGearEvent = { if case .liftoff = $0 { sawLiftoff = true } }

        body.velocity = [0, 4, 0]
        var maxY: Float = 0
        for _ in 0..<240 {
            world.update(deltaTime: Self.dt)
            maxY = max(maxY, body.getPosition().y)
        }

        #expect(sawLiftoff)
        // Ballistic apex from 4 m/s is about 0.82 m above launch; rebound
        // damping acts only across the first ~0.12 m of strut extension. A
        // strut that pulled would remove most of the apex.
        #expect(maxY - 1.93 >= 0.5)
    }

    @Test("a gear-up belly arrival classifies as a fuselage CRASH from pre-impact velocity, once")
    func bellyImpactClassifiesAsCrash() {
        // 5 m/s commanded at 2.0 m plus 0.95 m of free fall to the fuselage
        // bottom (capsule center 0.3, radius 1.35): arrival ≈ 6.6 m/s. onContact
        // fires after the pair's response, when the body already carries the
        // 0.2-restitution bounce, so the callback-time velocity reads as a
        // separating contact: a scrape. stepStartVelocity at the point is the
        // arrival (the point read production uses since D.3; level and not
        // rotating, it is the origin's). A level slap is two cap contacts in
        // one substep (D.3), so impacts are counted per substep, not per
        // contact: one.
        let (world, body, rig) = makeF22OnGear(startY: 2.0, velocityY: -5)
        rig.gearDeployed = false
        var substep = 0
        let rigHook = body.forceGenerator
        body.forceGenerator = { body, substepDelta, world in
            rigHook?(body, substepDelta, world)
            substep += 1
        }
        var contacts: [(name: String, cls: AirframeContactClass, speed: Float, bounceCls: AirframeContactClass)] = []
        var impactSubsteps: Set<Int> = []
        body.onContact = { [unowned body] contact, _ in
            let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                              preImpactVelocity: body.stepStartVelocity(atWorldPoint: contact.point))
            let bounceSpeed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                                    preImpactVelocity: body.velocity)
            let cls = AirframeContactClassifier.classification(forNormalSpeed: speed)
            if cls == .impact { impactSubsteps.insert(substep) }
            contacts.append((contact.colliderNameA ?? "?",
                             cls,
                             speed,
                             AirframeContactClassifier.classification(forNormalSpeed: bounceSpeed)))
        }
        for _ in 0..<120 { world.update(deltaTime: Self.dt) }   // 2 s

        let first = contacts.first
        #expect(first?.name == "fuselage")
        #expect(first?.cls == .impact)
        #expect(abs((first?.speed ?? 0) - 6.6) <= 0.25,
                "classification must see the ≈6.6 m/s arrival, not the post-impulse bounce")
        #expect(first?.bounceCls == .scrape,
                "the body's velocity inside onContact is already the bounce; it would miss the crash")
        // The 0.2 bounce comes back at ≈1.3 m/s, under the 2 m/s boundary:
        // one crashing substep (both caps), then scrapes while it settles.
        #expect(impactSubsteps.count == 1)
        #expect(rig.gearDeployed == false)
    }

    // MARK: - D.2: tires, brakes, and holding

    /// The F-22 settled on its struts for 10 s: ride height 1.93 m, the
    /// static loads on the wheels at the −0.48° stance, no motion.
    private func makeSettledF22() -> (world: PhysicsWorld, body: RigidBody, rig: GearRig) {
        let rigged = makeF22OnGear(startY: 2.5)
        for _ in 0..<600 { rigged.world.update(deltaTime: Self.dt) }
        return rigged
    }

    @Test("the jet stops: full brakes from 40 m/s bring it under 0.5 m/s within 12 s, in 150…260 m")
    func brakingStop() {
        // μ = 0.02 + 0.5 = 0.52 on the mains, which carry 85% of the weight
        // with the geometric split: a ≈ 0.52 · 0.85 · g ≈ 4.3 m/s², a stop
        // in about 9–10 s and 200 m. The D.2 replay (a body that cannot
        // pitch) gave 8.7 s and 175 m; the D.3 replay, with the braking
        // pitch shifting load onto the unbraked nose, 10.6 s and 213 m.
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()
        body.velocity = [0, 0, 40]
        rig.brake = 1

        var stopTime: Float? = nil
        for i in 0..<(12 * 60) {
            world.update(deltaTime: Self.dt)
            if stopTime == nil && simd_length(body.velocity) < 0.5 {
                stopTime = Float(i + 1) * Self.dt
            }
        }

        #expect(stopTime != nil, "still moving after 12 s")
        let distance = simd_length(body.getPosition() - start)
        #expect(distance >= 150 && distance <= 260, "roll-out \(distance) m")
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("a crab settles: 5 m/s sideways is gone within 2 s, in under 3 m")
    func crabSettles() {
        // Lateral grip 0.8 × 294 kN ≈ 235 kN, up to 7.8 m/s² against the
        // drift: about 0.65 s, the last centimetres per second held within
        // one substep (the replay: 0.63 s, 1.6 m; 1.4 m with the tensor).
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()
        body.velocity = [5, 0, 0]

        for _ in 0..<(2 * 60) { world.update(deltaTime: Self.dt) }

        #expect(abs(body.velocity.x) < 0.1)
        #expect(simd_length(body.getPosition() - start) < 3)
        #expect(rig.suspension.weightOnWheels, "still on its wheels: the grip came from the tires")
    }

    @Test("coasting: rolling resistance alone takes 0.98 m/s off 20 m/s in 5 s")
    func coasting() {
        // 0.02 · g ≈ 0.196 m/s² for 5 s; a taxiing jet coasts a long way.
        let (world, body, rig) = makeSettledF22()
        body.velocity = [0, 0, 20]

        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }

        #expect(abs(simd_length(body.velocity) - (20 - 0.98)) <= 0.2)
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("gear up: the belly slide keeps its speed — airframe contacts carry no friction")
    func gearUpSlides() {
        // Pins the boundary of this step: friction lives on the wheels only;
        // contact friction is a D.4 item.
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        rig.gearDeployed = false
        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // the belly rest
        body.velocity = [0, 0, 5]

        for _ in 0..<(2 * 60) { world.update(deltaTime: Self.dt) }

        #expect(simd_length(body.velocity) >= 4.5)
        #expect(!rig.suspension.weightOnWheels)
    }

    @Test("parked hold: a 4 kN push, under the 5.9 kN rolling-resistance limit, moves the jet less than 1 cm in 5 s")
    func parkedHold() {
        // Holding friction: the demand is the tangent velocity the push
        // would add this substep, and the unbraked wheels carry up to
        // 0.02 × W = 5.9 kN of it. A force proportional to slip speed (the
        // plan's first draft) would have crept at 0.34 m/s: 1.7 m in 5 s.
        // With pitch freedom the push pivots the jet on its patches by
        // 1.8 mm (replay) before it holds.
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()
        rig.extraForce = [0, 0, 4_000]

        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }

        #expect(simd_length(body.getPosition() - start) < 0.01)
        #expect(simd_length(body.velocity) < 1e-3)
    }

    @Test("brake hold and release: 100 kN against the brakes dives the nose and pivots the origin a few centimetres, then holds; 200 kN, over the 137 kN capacity, slides more than 1 m")
    func brakeHoldAndRelease() {
        // Capacity with the brakes on: 0.52 × 250 kN on the mains plus the
        // nose's 0.9 kN ≈ 131 kN (137 before the geometric split). Under it
        // the wheels are solved in strut order and each takes what the ones
        // before it left, so nothing slides — the plan's fixed-share draft
        // left 10 kN unopposed and crept 1.6 cm. What pitch freedom adds is
        // a transient: the thrust at the origin against the tire forces
        // 1.93 m below it is a 193 kN·m nose-down couple, the nose dives
        // from −0.48° to −1.80° and the origin, pivoting on the held
        // patches, moves 4.4 cm forward within a second (replay), then
        // nothing moves (0.01 mm over the next 5 s). D.2's strict 1 cm bound
        // was for a body that cannot pitch. Over the capacity every wheel is
        // at its limit and the jet slides: 36 m in the replay.
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()
        rig.brake = 1
        rig.extraForce = [0, 0, 100_000]
        for _ in 0..<(2 * 60) { world.update(deltaTime: Self.dt) }
        let forward = body.getPosition().z - start.z
        #expect(forward >= 0.02 && forward <= 0.08, "the dive's pivot: 4.4 cm in the replay")
        #expect(pitchDegrees(body) >= -2.3 && pitchDegrees(body) <= -1.3, "−1.80° in the replay")

        let afterDive = body.getPosition()
        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }
        #expect(simd_length(body.velocity) < 1e-3, "held")
        #expect(simd_length(body.getPosition() - afterDive) < 0.01, "held")

        let held = body.getPosition()
        rig.extraForce = [0, 0, 200_000]
        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }
        #expect(simd_length(body.getPosition() - held) > 1, "the wheels slide once the push exceeds the friction limit")
    }

    // MARK: - D.3: the aircraft rotates on its gear

    @Test("nose settles last: from 4° nose-up the mains compress first, the nose drops onto its gear, and the pitch ends at −0.45° ± 0.2°")
    func noseSettlesLast() {
        // A rotation about X by −4° lifts forward.y (nose up). The nose
        // wheel then starts 0.36 m higher than the mains'; start 1 cm above
        // the mains' contact height, sinking at 1 m/s. Replay: the mains
        // touch on substep 2, the nose on substep 56, and the gear's pitch
        // stiffness (9 MN·m/rad against 390 t·m²: 4.8 rad/s, damping ratio
        // 0.7 with the controller) brings the stance to −0.48° well inside 4 s.
        let noseUp = float3x3(simd_quatf(angle: -4 * .pi / 180, axis: X_AXIS))
        let (world, body, rig) = makeF22OnGear(startY: Self.strutContactHeight(rotation: noseUp) + 0.01,
                                               velocityY: -1,
                                               rotation: noseUp)
        #expect(abs(pitchDegrees(body) - 4) <= 0.01)

        var firstContactSubstep: [Int?] = [nil, nil, nil]
        var substep = 0
        let rigHook = body.forceGenerator
        body.forceGenerator = { [unowned rig] body, substepDelta, world in
            rigHook?(body, substepDelta, world)
            for i in 0..<3 where firstContactSubstep[i] == nil && rig.suspension.compressions[i] > 0 {
                firstContactSubstep[i] = substep
            }
            substep += 1
        }

        for _ in 0..<(4 * 60) { world.update(deltaTime: Self.dt) }

        let nose = firstContactSubstep[0], left = firstContactSubstep[1], right = firstContactSubstep[2]
        #expect(nose != nil && left != nil && right != nil, "every strut touched down")
        if let nose, let left, let right {
            #expect(left < nose && right < nose, "the mains take the weight first")
        }
        #expect(abs(pitchDegrees(body) - (-0.45)) <= 0.2)
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("one-wheel arrival rolls level: 3° of bank at 1 m/s sink ends within 0.3° of level after 3 s, both mains loaded within 10%")
    func oneWheelArrivalRollsLevel() {
        // The low main touches first and its spring torque (half the weight
        // at 1.62 m) rolls the jet toward the other main against the
        // controller's damping; the replay peaks at 0.2 rad/s and ends level
        // with the mains sharing the load exactly.
        let banked = float3x3(simd_quatf(angle: 3 * .pi / 180, axis: Z_AXIS))
        let (world, body, rig) = makeF22OnGear(startY: Self.strutContactHeight(rotation: banked) + 0.01,
                                               velocityY: -1,
                                               rotation: banked)
        #expect(abs(rollDegrees(body) - 3) <= 0.01)

        for _ in 0..<(3 * 60) { world.update(deltaTime: Self.dt) }

        #expect(abs(rollDegrees(body)) < 0.3)
        let left = rig.suspension.compressions[1]
        let right = rig.suspension.compressions[2]
        #expect(left > 0 && right > 0)
        #expect(abs(left - right) <= 0.1 * max(left, right))
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("steering: at taxi speed the yaw command turns the nose through the nose tire, in the airborne yaw direction",
          arguments: [Float(1), Float(-1)])
    func groundSteering(_ steer: Float) {
        // 8 m/s with the nose wheel at its 20° range: kinematic steering
        // would yaw at v·tan δ / wheelbase ≈ 0.48 rad/s; the mains' side
        // grip and the controller's rate damping (I_yaw/τ ≈ 1.1 MN·m per
        // rad/s) hold it to about 0.18, and the heading is 16.5° after 2 s
        // (replay). steer +1 commands −yaw about Y, so forward.x = sin(heading)
        // goes negative, as the airborne yaw does; the yaw controller damps
        // rates, not angles, so the turn holds against it.
        let (world, body, rig) = makeSettledF22()
        body.velocity = [0, 0, 8]
        rig.steer = steer

        for _ in 0..<(2 * 60) { world.update(deltaTime: Self.dt) }

        let headingSine = body.pose().rotation.forward.x
        #expect(steer > 0 ? headingSine < -0.05 : headingSine > 0.05, "heading sine \(headingSine)")
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("braking dips the nose: full brakes from 40 m/s compress the nose strut at least 0.05 m past static within 1 s, and the jet still stops within 12 s")
    func brakingDive() {
        // 0.52 × 250 kN at the patches, 1.93 m below the origin: a 250 kN·m
        // nose-down couple, +0.145 m of nose compression and −2.0° of pitch
        // in the replay (travel 0.40).
        let (world, body, rig) = makeSettledF22()
        let staticNose = rig.suspension.compressions[0]
        body.velocity = [0, 0, 40]
        rig.brake = 1

        var extraNose: Float = 0
        for _ in 0..<60 {
            world.update(deltaTime: Self.dt)
            extraNose = max(extraNose, rig.suspension.compressions[0] - staticNose)
        }
        #expect(extraNose >= 0.05)

        var stopped = false
        for _ in 60..<(12 * 60) where !stopped {
            world.update(deltaTime: Self.dt)
            stopped = simd_length(body.velocity) < 0.5
        }
        #expect(stopped)
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("belly rest without rocking: gear up from 2.0 m at −1 m/s, after 5 s the pitch rate stays under 0.02 rad/s and the pitch within 1°")
    func bellyRestWithoutRocking() {
        // Two caps 16.2 m apart on 390 t·m² of pitch inertia: one impulse
        // pass per substep leaves the first cap approaching again and the
        // replay rocks at 0.028 rad/s, four passes at 0.009, eight rest
        // (0.000 over the sixth second).
        let (world, body, rig) = makeF22OnGear(startY: 2.0, velocityY: -1)
        rig.gearDeployed = false
        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }

        var peakPitchRate: Float = 0
        for _ in 0..<60 {
            world.update(deltaTime: Self.dt)
            peakPitchRate = max(peakPitchRate, abs(body.angularVelocity.x))
        }

        #expect(peakPitchRate < 0.02)
        #expect(abs(pitchDegrees(body)) < 1)
        #expect(abs(body.getPosition().y - 1.05) <= 0.05)
        #expect(!rig.suspension.weightOnWheels)
    }

    @Test("the parked jet holds: settled at its stance, ten more seconds move it under 1 cm along the runway at |v| < 1e-3")
    func parkedJetHolds() {
        // The strut load acts along the ground normal, so the −0.48° stance
        // pushes nothing along the runway; a load along body up would have
        // pushed 2.3 kN, and the plan's first tire draft crept at 0.2 m/s on
        // it — 2 m in these ten seconds. Replay: 0.0 mm.
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()

        for _ in 0..<(10 * 60) { world.update(deltaTime: Self.dt) }

        let moved = body.getPosition() - start
        #expect(simd_length(float3(moved.x, 0, moved.z)) < 0.01)
        #expect(simd_length(body.velocity) < 1e-3)
        #expect(rig.suspension.weightOnWheels)
    }

    @Test("frame partitioning is exact on the gear: 1/30 s and 1/120 s frames agree bit-for-bit at 5 s",
          arguments: [PhysicsUpdateType.NaiveEuler, .HeckerVerlet])
    func partitionInvariance(_ updateType: PhysicsUpdateType) {
        // The FixedTimestepTests.partitioningInvariance pattern on the rig:
        // the aircraft's force hook, the controller, the tire solve, and the
        // pair solve are per substep, so nothing may depend on the frame.
        let coarse = makeF22OnGear(startY: 2.5, updateType: updateType)
        let fine = makeF22OnGear(startY: 2.5, updateType: updateType)

        for _ in 0..<150 {   // 5 s
            coarse.world.update(deltaTime: 1.0 / 30.0)
            for _ in 0..<4 { fine.world.update(deltaTime: 1.0 / 120.0) }
        }

        #expect(coarse.body.pose().position == fine.body.pose().position)
        #expect(coarse.body.pose().rotation == fine.body.pose().rotation)
        #expect(coarse.body.velocity == fine.body.velocity)
        #expect(coarse.rig.suspension.weightOnWheels && fine.rig.suspension.weightOnWheels)
    }
}
