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
//  of the parity goldens). Every band was reproduced in a scratch replay of
//  the struts, the tire solve, and the Verlet step before the tests ran.
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

    /// Metal-free stand-in for Aircraft: drives the real LandingGearSuspension
    /// from the body's force hook. A detached body's pose has the identity
    /// rotation, i.e. a level aircraft. Node rotation and the animator gate
    /// are B.5's in-app checks. `brake` is the B key (0…1); `extraForce` is
    /// added to the body before the suspension runs, where the flight model's
    /// thrust would be, so the tire solve's prediction includes it. The hook
    /// captures the rig weakly: a test must keep its `rig` alive through the
    /// run (use it afterwards), or the suspension silently stops and the jet
    /// drops onto its frictionless belly.
    private final class GearRig {
        let body: RigidBody
        let suspension: LandingGearSuspension
        var gearDeployed = true
        var brake: Float = 0
        var extraForce: float3 = .zero

        init(body: RigidBody, struts: [SuspensionStrut]) {
            self.body = body
            self.suspension = LandingGearSuspension(struts: struts)
            body.forceGenerator = { [weak self] body, substepDelta, world in
                guard let self else { return }
                body.force += self.extraForce
                self.suspension.accumulateForces(body: body,
                                                 gearDeployed: self.gearDeployed,
                                                 brake: self.brake,
                                                 world: world,
                                                 substepDelta: substepDelta)
            }
        }
    }

    private func makeF22OnGear(startY: Float, velocityY: Float = 0)
        -> (world: PhysicsWorld, body: RigidBody, rig: GearRig) {
        let body = RigidBody(detachedAt: [0, startY, 0])
        body.mass = 30_000                                    // the flight model's mass
        body.restitution = 0.2
        body.velocity = [0, velocityY, 0]
        body.colliders = AircraftColliderSpec.spec(for: .f22_cgtrader)
        let rig = GearRig(body: body, struts: AircraftLandingGearSpec.spec(for: .f22_cgtrader))
        let plane = PlaneRigidBody(detachedAt: .zero)
        plane.isStatic = true
        let world = PhysicsWorld(entities: [body, plane], updateType: .HeckerVerlet)
        world.useBroadPhase = false
        return (world, body, rig)
    }

    @Test("the F-22 settles on its struts at ride height, gravity on, fuselage clear")
    func settlesOnStruts() {
        let (world, body, rig) = makeF22OnGear(startY: 2.5)
        var airframeTouched = false
        body.onContact = { _, _ in airframeTouched = true }

        for _ in 0..<600 { world.update(deltaTime: Self.dt) }   // 10 s

        #expect(body.shouldApplyGravity)
        #expect(rig.suspension.weightOnWheels)
        #expect(abs(body.getPosition().y - 1.93) <= 0.02,
                "Σk·x = W gives x ≈ 0.119, ride height = 2.05 − x ≈ 1.93")
        #expect(abs(rig.suspension.compressions[0] - 0.119) <= 0.01,
                "equal-reach struts share the static compression")
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

    @Test("a gear-up belly arrival classifies as a fuselage CRASH from pre-impact velocity")
    func bellyImpactClassifiesAsCrash() {
        // 5 m/s commanded at 2.0 m plus 0.95 m of free fall to the fuselage
        // bottom (capsule center 0.3, radius 1.35): arrival ≈ 6.6 m/s. onContact
        // fires after the pair's response, when the body already carries the
        // 0.2-restitution bounce, so the callback-time velocity reads as a
        // separating contact: a scrape. stepStartVelocity is the arrival.
        let (world, body, rig) = makeF22OnGear(startY: 2.0, velocityY: -5)
        rig.gearDeployed = false
        var contacts: [(name: String, cls: AirframeContactClass, speed: Float, bounceCls: AirframeContactClass)] = []
        body.onContact = { [unowned body] contact, _ in
            let speed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                              preImpactVelocity: body.stepStartVelocity)
            let bounceSpeed = AirframeContactClassifier.normalSpeed(contactNormal: contact.normal,
                                                                    preImpactVelocity: body.velocity)
            contacts.append((contact.colliderNameA ?? "?",
                             AirframeContactClassifier.classification(forNormalSpeed: speed),
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
        // one crash, then scrapes while it settles on the belly.
        #expect(contacts.filter { $0.cls == .impact }.count == 1)
    }

    // MARK: - D.2: tires, brakes, and holding

    /// The F-22 settled on its struts for 10 s: ride height 1.93 m, the
    /// static loads on the wheels, no motion.
    private func makeSettledF22() -> (world: PhysicsWorld, body: RigidBody, rig: GearRig) {
        let rigged = makeF22OnGear(startY: 2.5)
        for _ in 0..<600 { rigged.world.update(deltaTime: Self.dt) }
        return rigged
    }

    @Test("the jet stops: full brakes from 40 m/s bring it under 0.5 m/s within 12 s, in 150…260 m")
    func brakingStop() {
        // μ = 0.02 + 0.5 = 0.52 on the mains, which carry 89% of the weight
        // (a body that cannot pitch shares the struts' compression, so the
        // load splits by spring rate): a ≈ 0.52 · 0.89 · g ≈ 4.5 m/s², a stop
        // in about 9 s and 180 m. The replay gives 8.7 s and 175 m; the band
        // also covers D.3's geometric split and braking pitch.
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
        // one substep (the replay: 0.63 s, 1.6 m).
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
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()
        rig.extraForce = [0, 0, 4_000]

        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }

        #expect(simd_length(body.getPosition() - start) < 0.01)
        #expect(simd_length(body.velocity) < 1e-3)
    }

    @Test("brake hold and release: 100 kN against the brakes moves nothing in 5 s; 200 kN, over the 137 kN capacity, slides more than 1 m")
    func brakeHoldAndRelease() {
        // Capacity with the brakes on: 0.52 × 262 kN on the mains plus the
        // nose's 0.6 kN ≈ 137 kN. Under it the wheels are solved in strut
        // order and each takes what the ones before it left (nose 0.6, mains
        // 68.1 and 31.2 kN against 100 kN), so nothing moves — the plan's
        // fixed-share draft left 10 kN unopposed and crept 1.6 cm. Over it
        // every wheel is at its limit and the jet slides: 26 m in the replay.
        let (world, body, rig) = makeSettledF22()
        let start = body.getPosition()
        rig.brake = 1
        rig.extraForce = [0, 0, 100_000]
        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }
        #expect(simd_length(body.getPosition() - start) < 0.01, "held")

        let held = body.getPosition()
        rig.extraForce = [0, 0, 200_000]
        for _ in 0..<(5 * 60) { world.update(deltaTime: Self.dt) }
        #expect(simd_length(body.getPosition() - held) > 1, "the wheels slide once the push exceeds the friction limit")
    }
}
