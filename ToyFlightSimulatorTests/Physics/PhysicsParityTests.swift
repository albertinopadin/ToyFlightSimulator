//
//  PhysicsParityTests.swift
//  ToyFlightSimulatorTests
//
//  Step 0.7 of plans/claude/compound_rigid_bodies_implementation_plan.md:
//  records the CURRENT physics engine's trajectories as committed goldens
//  (golden files in the golden-master-testing sense: known-good reference
//  outputs, checked in as Baselines/*.json, that later runs must reproduce
//  within tolerance) so Phase A's rewrite can be verified in two commits —
//  A-routing must match every golden unchanged; A-response deliberately
//  diverges from first contact and regoldens (re-records the baselines)
//  with a reviewed diff.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

// MARK: - Scenarios

/// One case per row of the 0.7 scenario table; rawValue == golden filename stem.
enum ParityScenario: String, CaseIterable, CustomTestStringConvertible {
    case singleBounceVerlet = "single_bounce_verlet"
    case singleBounceEuler  = "single_bounce_euler"
    case restLatch          = "rest_latch"
    case headOnPair         = "head_on_pair"
    case ballCluster16      = "ball_cluster_16"
    case stressGrid50       = "stress_grid_50"

    var testDescription: String { rawValue }

    var solver: PhysicsUpdateType { self == .singleBounceEuler ? .NaiveEuler : .HeckerVerlet }

    var useBroadPhase: Bool {
        switch self {
            case .ballCluster16, .stressGrid50: return true
            default: return false
        }
    }

    var dt: Float { 1.0 / 60.0 }

    /// Steps covered by the committed golden.
    var goldenSteps: Int {
        switch self {
            case .singleBounceVerlet, .singleBounceEuler: return 300
            case .restLatch:     return 600
            case .headOnPair:    return 120
            case .ballCluster16: return 180
            case .stressGrid50:  return 120
        }
    }

    /// Total steps run; the tail past goldenSteps is invariant-checked only
    /// (the chaos policy: goldens stay short where contact ordering amplifies
    /// float noise, invariants carry the rest of the run).
    var totalSteps: Int {
        switch self {
            case .ballCluster16, .stressGrid50: return 600
            default: return goldenSteps
        }
    }

    /// Sampling cadence inside the golden window (t=0 always included).
    /// Dense for the simple scenarios (readable Phase A diffs), thinned for
    /// the many-body ones (keeps committed JSON in the tens of KB).
    var sampleEvery: Int {
        switch self {
            case .ballCluster16, .stressGrid50: return 3
            default: return 1
        }
    }

    /// Invariant bound. Deliberately ~2× the max physically attainable speed
    /// (initial speed + fall from max spawn height): catches energy blowups,
    /// not micro-noise, and must keep holding after Phase A's response
    /// rewrite.
    var speedBudget: Float {
        switch self {
            case .singleBounceVerlet, .singleBounceEuler, .restLatch:
                return 20   // impact from ≤ 5 m ≈ 7 m/s
            case .headOnPair:
                return 40   // ±5 m/s closing + 2 s free fall ≈ 20 m/s
            case .ballCluster16:
                return 30   // fall from ≤ 10 m ≈ 14 m/s
            case .stressGrid50:
                return 50   // fall from ≤ 20 m ≈ 20 m/s, + ≤ 2.8 m/s initial
        }
    }

    /// Ground-plane height for the tunneling invariant; nil = no floor
    /// (head_on_pair falls freely by design — see build()).
    var floorY: Float? { self == .headOnPair ? nil : 0 }

    var sphereRadius: Float {
        switch self {
            case .ballCluster16: return 0.4
            case .stressGrid50:  return 0.3
            default:             return 0.5
        }
    }

    struct Built {
        let world: PhysicsWorld
        /// Tracked bodies, index-aligned with the golden's tracks. The static
        /// plane (when present) is in the world but never tracked.
        let spheres: [SphereRigidBody]
    }

    /// All bodies via the 0.6 detached inits — no GameObject, no Metal.
    /// Masses stay at the RigidBody default (1), matching the table.
    func build() -> Built {
        switch self {
            case .singleBounceVerlet, .singleBounceEuler:
                let ball = SphereRigidBody(detachedAt: [0, 5, 0], collisionRadius: 0.5)
                ball.restitution = 0.9
                return Built(world: makeWorld([ball, floorPlane(restitution: 0.9)]),
                             spheres: [ball])

            case .restLatch:
                // Plane e = 1.0, so min() picks the ball's 0.2: impacts decay
                // 7 → 1.4 → 0.28 m/s. Since the A-response commit the third
                // contact is below the 1 m/s restitution velocity threshold ⇒
                // e forced to 0 and the ball enters the per-step
                // support-impulse equilibrium — gravity stays ON, pinned by
                // the golden's finalShouldApplyGravity. (Pre-A-response, this
                // same scenario pinned the one-way rest latch: the 0.55 m/s
                // threshold froze the ball with gravity off.)
                let ball = SphereRigidBody(detachedAt: [0, 3, 0], collisionRadius: 0.5)
                ball.restitution = 0.2
                return Built(world: makeWorld([ball, floorPlane(restitution: 1.0)]),
                             spheres: [ball])

            case .headOnPair:
                // No plane, gravity left ON: both spheres fall in lockstep, so
                // the contact normal stays X-pure and the e=1 equal-mass
                // velocity swap plus the |vA| == |vB| mirror symmetry are
                // exact. (Restitution stays at the RigidBody default 1.)
                let a = SphereRigidBody(detachedAt: [-2, 0, 0], collisionRadius: 0.5)
                a.velocity = [5, 0, 0]
                let b = SphereRigidBody(detachedAt: [2, 0, 0], collisionRadius: 0.5)
                b.velocity = [-5, 0, 0]
                return Built(world: makeWorld([a, b]), spheres: [a, b])

            case .ballCluster16:
                // BallPhysicsScene's spawn distribution with the scene's
                // unseeded `.random` swapped for the harness RNG. DRAW ORDER
                // IS PART OF THE GOLDEN CONTRACT: x, y, z per ball, balls in
                // order. (The scene's color draw is not mirrored — the
                // harness stream is its own.)
                var rng = SplitMix64(seed: 0xF22_0005)
                var balls: [SphereRigidBody] = []
                for _ in 0..<16 {
                    let pos = float3(rng.float(in: -7...7),
                                     rng.float(in: 1...10),
                                     rng.float(in: -7...0))
                    let ball = SphereRigidBody(detachedAt: pos, collisionRadius: 0.4)
                    ball.restitution = 0.9
                    balls.append(ball)
                }
                return Built(world: makeWorld(balls + [floorPlane(restitution: 1.0)]),
                             spheres: balls)

            case .stressGrid50:
                // PhysicsStressTestScene.createSpheres(count: 50): 8×8 grid
                // (Int(sqrt(50))+1), spacing 2, origin -8; jittered x/z;
                // y and initial velocity seeded; plane e = 0.9. Draw order
                // per ball: xJitter, y, zJitter, vx, vz.
                var rng = SplitMix64(seed: 0xF22_0006)
                let gridSize = 8
                let spacing: Float = 2.0
                let start = -Float(gridSize) * spacing / 2
                var balls: [SphereRigidBody] = []
                for i in 0..<50 {
                    let pos = float3(start + Float(i % gridSize) * spacing + rng.float(in: -0.5...0.5),
                                     rng.float(in: 5...20),
                                     start + Float(i / gridSize) * spacing + rng.float(in: -0.5...0.5))
                    let ball = SphereRigidBody(detachedAt: pos, collisionRadius: 0.3)
                    ball.restitution = 0.8
                    ball.velocity = [rng.float(in: -2...2), 0, rng.float(in: -2...2)]
                    balls.append(ball)
                }
                return Built(world: makeWorld(balls + [floorPlane(restitution: 0.9)]),
                             spheres: balls)
        }
    }

    private func floorPlane(restitution: Float) -> PlaneRigidBody {
        // Position .zero + up normal is load-bearing: the goldens were
        // captured under the legacy y=0 plane hardcode (the deleted
        // PhysicsWorld.getPenetrationDepth(ball:plane:)), and A-routing's
        // bit-exactness vs those goldens needs NarrowPhase's general form
        // dot(c − planePos, n) to reduce to c.y exactly — which it does only
        // for planePos = .zero, n = [0, 1, 0] (plan A.5, argument 3).
        let plane = PlaneRigidBody(detachedAt: .zero, collisionNormal: [0, 1, 0])
        plane.restitution = restitution
        plane.isStatic = true
        return plane
    }

    private func makeWorld(_ entities: [RigidBody]) -> PhysicsWorld {
        let world = PhysicsWorld(entities: entities, updateType: solver)
        world.useBroadPhase = useBroadPhase
        return world
    }
}

// MARK: - Baseline model + runner

/// Golden-file schema. Codable → JSON; Equatable → the determinism test.
/// Flat [Float] triples, not float3: keeps the synthesized Codable output a
/// plain JSON array. (Float round-trips JSON exactly — the 1e-4 compare
/// tolerance exists for FMA/toolchain variance, not serialization.)
struct PhysicsBaseline: Codable, Equatable {
    struct BodyTrack: Codable, Equatable {
        var samples: [[Float]]              // [x,y,z]: t=0, then every sampleEvery-th step of the golden window
        var finalVelocity: [Float]          // at the END of the golden window (not totalSteps)
        var finalShouldApplyGravity: Bool   // makes the rest latch visible in the data
    }

    var scenario: String
    var solver: String
    var useBroadPhase: Bool
    var dt: Float
    var steps: Int                          // golden window length (== goldenSteps)
    var sampleEvery: Int
    var tracks: [BodyTrack]                 // index-aligned with Built.spheres
}

enum ParityRunner {
    /// Steps the scenario to totalSteps: samples the golden window, snapshots
    /// final state at goldenSteps, and #requires the chaos-policy invariants
    /// on EVERY step (fail-fast: one readable failure, not a cascade of
    /// thousands once a body blows up).
    static func run(_ scenario: ParityScenario) throws -> PhysicsBaseline {
        let built = scenario.build()
        var samples: [[[Float]]] = built.spheres.map { [flat($0.getPosition())] }
        var finalVelocity: [[Float]] = []
        var finalGravity: [Bool] = []

        for step in 1...scenario.totalSteps {
            built.world.update(deltaTime: scenario.dt)

            if step <= scenario.goldenSteps && step % scenario.sampleEvery == 0 {
                for (i, ball) in built.spheres.enumerated() {
                    samples[i].append(flat(ball.getPosition()))
                }
            }
            if step == scenario.goldenSteps {
                finalVelocity = built.spheres.map { flat($0.velocity) }
                finalGravity  = built.spheres.map { $0.shouldApplyGravity }
            }

            for (i, ball) in built.spheres.enumerated() {
                let p = ball.getPosition()
                let v = ball.velocity
                try #require(allFinite(p) && allFinite(v),
                             "body \(i) non-finite at step \(step): p=\(p) v=\(v)")
                if let floorY = scenario.floorY {
                    // 1 m slack: the response can leave a frame of transient
                    // penetration, but a tunneled ball falls away forever and
                    // trips this within a few steps.
                    try #require(p.y > floorY - scenario.sphereRadius - 1.0,
                                 "body \(i) tunneled at step \(step): y=\(p.y)")
                }
                try #require(simd_length(v) <= scenario.speedBudget,
                             "body \(i) over the speed budget at step \(step): |v|=\(simd_length(v))")
            }
        }

        return PhysicsBaseline(scenario: scenario.rawValue,
                               solver: String(describing: scenario.solver),
                               useBroadPhase: scenario.useBroadPhase,
                               dt: scenario.dt,
                               steps: scenario.goldenSteps,
                               sampleEvery: scenario.sampleEvery,
                               tracks: built.spheres.indices.map {
                                   .init(samples: samples[$0],
                                         finalVelocity: finalVelocity[$0],
                                         finalShouldApplyGravity: finalGravity[$0])
                               })
    }

    private static func flat(_ v: float3) -> [Float] { [v.x, v.y, v.z] }

    /// Committed goldens live next to the tests; #filePath works on both the
    /// local checkout and CI's.
    static var baselinesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // …/ToyFlightSimulatorTests/Physics/
            .appendingPathComponent("Baselines")
    }

    /// TFS_REGEN_PHYSICS_BASELINES=1 (mirrors TFS_REGEN_THUMBNAILS) rewrites
    /// the golden instead of comparing, then records an issue so a regen run
    /// can never silently pass CI.
    static func assertMatchesGolden(_ fresh: PhysicsBaseline,
                                    tolerance: Float = 1e-4,
                                    sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = baselinesDir.appendingPathComponent("\(fresh.scenario).json")

        if ProcessInfo.processInfo.environment["TFS_REGEN_PHYSICS_BASELINES"] == "1" {
            try FileManager.default.createDirectory(at: baselinesDir,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // stable diffs — regoldens are reviewed like code
            try encoder.encode(fresh).write(to: url)
            Issue.record("regenerated \(fresh.scenario).json — review the diff, then re-run without TFS_REGEN_PHYSICS_BASELINES",
                         sourceLocation: sourceLocation)
            return
        }

        let golden = try JSONDecoder().decode(PhysicsBaseline.self,
                                              from: Data(contentsOf: url))

        // Metadata compares EXACTLY — solver/steps/dt drift is a harness bug,
        // never something to tolerance past.
        try #require(fresh.scenario == golden.scenario
                     && fresh.solver == golden.solver
                     && fresh.useBroadPhase == golden.useBroadPhase
                     && fresh.dt == golden.dt
                     && fresh.steps == golden.steps
                     && fresh.sampleEvery == golden.sampleEvery
                     && fresh.tracks.count == golden.tracks.count,
                     "metadata mismatch vs \(fresh.scenario).json — regenerate deliberately",
                     sourceLocation: sourceLocation)

        // Report only the FIRST divergent (body, step): everything after the
        // first contact-order flip is downstream noise, and one readable
        // location is what makes a Phase A routing bug debuggable.
        for (body, (f, g)) in zip(fresh.tracks, golden.tracks).enumerated() {
            for (s, (fs, gs)) in zip(f.samples, g.samples).enumerated() {
                if (0..<3).contains(where: { abs(fs[$0] - gs[$0]) > tolerance }) {
                    Issue.record("body \(body) diverges at sample \(s) (step \(s * fresh.sampleEvery)): fresh \(fs) vs golden \(gs)",
                                 sourceLocation: sourceLocation)
                    return
                }
            }
            if f.finalShouldApplyGravity != g.finalShouldApplyGravity
                || (0..<3).contains(where: { abs(f.finalVelocity[$0] - g.finalVelocity[$0]) > tolerance }) {
                Issue.record("body \(body) final state diverges: v \(f.finalVelocity) vs \(g.finalVelocity), gravity \(f.finalShouldApplyGravity) vs \(g.finalShouldApplyGravity)",
                             sourceLocation: sourceLocation)
                return
            }
        }
    }
}

// MARK: - Tests

@Suite("Physics parity", .tags(.physics))
struct PhysicsParityTests {
    @Test("current behavior matches the committed golden",
          arguments: ParityScenario.allCases)
    func matchesGolden(_ scenario: ParityScenario) throws {
        try ParityRunner.assertMatchesGolden(try ParityRunner.run(scenario))
    }

    @Test("harness is deterministic — two fresh runs agree bit-for-bit")
    func harnessIsDeterministic() throws {
        // Validates the harness itself (seeding, no hidden global state) on
        // the scenario with the most RNG + broad-phase surface.
        let first  = try ParityRunner.run(.ballCluster16)
        let second = try ParityRunner.run(.ballCluster16)
        #expect(first == second)
    }

    @Test("A-response behavior: resting keeps gravity on (the latch is gone)")
    func restingKeepsGravityOn() throws {
        let track = try ParityRunner.run(.restLatch).tracks[0]
        // Support-cycle equilibrium: the e=0 impulse cancels each step's
        // gravity, so the boundary-frame velocity is at most ~one gravity
        // step (g·dt ≈ 0.163 m/s), and the ball floats within slop + β
        // residual of touching. EXACT zeros would be dishonest now — that
        // was the latch's signature.
        #expect(track.finalShouldApplyGravity == true)
        let v = track.finalVelocity
        #expect(simd_length(float3(v[0], v[1], v[2])) <= 0.25)
        // β-equilibrium depth ≈ slop + (per-step gravity sink)/β ≈ 1–2 cm at
        // 60 Hz — the 0.03 bound is deliberately loose; observed at the
        // 2026-08-31 regolden: y = 0.4882 (1.18 cm depth), |v| = 0.1635
        // (exactly g·dt). Tighten toward those once Phase B's fixed step
        // makes them dt-stable.
        let restingY = track.samples.last![1]
        #expect(abs(restingY - 0.5) <= 0.03)
    }
}
