//
//  SuspensionSolverTests.swift
//  ToyFlightSimulatorTests
//
//  B.4 (B-suspension): the pure per-strut spring-damper step. Every case is
//  hand-computed against one test strut with binary-exact numbers; no bodies,
//  no world, no Metal.
//

import Testing
@testable import ToyFlightSimulator

@Suite("SuspensionSolver", .tags(.physics))
struct SuspensionSolverTests {

    /// reach 1.5 m (rest 1.0 + wheel 0.5), travel 0.5 m, attach 0.5 m below
    /// the origin; k 1000 N/m, c 1000 (compressing) / 2000 (extending) N·s/m,
    /// clamp 2000 N. Stepped at 0.1 s so rate = Δx·10.
    private static let strut = SuspensionStrut(name: "test",
                                               attachLocal: [0, -0.5, 0],
                                               restLength: 1.0,
                                               maxTravel: 0.5,
                                               wheelRadius: 0.5,
                                               springRate: 1_000,
                                               compressionDamping: 1_000,
                                               reboundDamping: 2_000,
                                               maxSupportForce: 2_000)
    private static let h: Float = 0.1

    private func solve(distance: Float?,
                       previous: Float = 0,
                       scale: Float = 1) -> SuspensionSolver.StrutStep {
        SuspensionSolver.solve(strut: Self.strut,
                               uniformScale: scale,
                               distanceToGround: distance,
                               previousCompression: previous,
                               substepDelta: Self.h)
    }

    @Test("reach = rest + wheel; reachBelowOrigin adds the attach depth")
    func reachHelpers() {
        #expect(Self.strut.reach == 1.5)
        #expect(Self.strut.reachBelowOrigin == 2.0)
    }

    @Test("no ground, or ground beyond reach, is .noContact; exactly at reach is a zero-force contact")
    func airborneIsNoContact() {
        #expect(solve(distance: nil) == .noContact)
        #expect(solve(distance: 1.6) == .noContact)
        #expect(solve(distance: 1.5001) == .noContact)
        // Inclusive boundary: touching, nothing to push with yet.
        let touching = solve(distance: 1.5)
        #expect(touching.compression == 0)
        #expect(touching.force == 0)
        #expect(!touching.overloaded)
    }

    @Test("static compression at zero rate gives k·x")
    func staticCompressionIsSpringOnly() {
        // distance 1.375 → x = 0.125; previous 0.125 → rate 0 → F = 1000·0.125.
        let step = solve(distance: 1.375, previous: 0.125)
        #expect(step.compression == 0.125)
        #expect(step.compressionRate == 0)
        #expect(step.force == 125)
        #expect(!step.bottomedOut)
        #expect(!step.overloaded)
    }

    @Test("compressing uses the compression damping, extending the rebound damping")
    func asymmetricDamping() {
        // Compressing 0.0625 → 0.125 in 0.1 s: rate 0.625 → F = 125 + 1000·0.625.
        let compressing = solve(distance: 1.375, previous: 0.0625)
        #expect(approxEqual(compressing.compressionRate, 0.625))
        #expect(approxEqual(compressing.force, 750))
        // Extending 0.2578125 → 0.25: rate −0.078125 → F = 250 + 2000·(−0.078125)
        // = 93.75 (171.875 if the compression damping were used).
        let extending = solve(distance: 1.25, previous: 0.2578125)
        #expect(approxEqual(extending.compressionRate, -0.078125))
        #expect(approxEqual(extending.force, 93.75))
    }

    @Test("a fast rebound floors the force at exactly 0: struts push, never pull")
    func fastReboundFloorsAtZero() {
        // 0.5 → 0.25: rate −2.5 → unclamped 250 − 5000 = −4750.
        let step = solve(distance: 1.25, previous: 0.5)
        #expect(step.force == 0)
        #expect(step.compression == 0.25, "state keeps tracking the geometry")
        #expect(!step.overloaded)
    }

    @Test("maxSupportForce clamps the force; overloaded is judged on the unclamped value")
    func clampAndOverload() {
        // x = 0.25 from 0: rate 2.5 → unclamped 250 + 2500 = 2750 ≥ 2000.
        let hard = solve(distance: 1.25)
        #expect(hard.force == 2_000)
        #expect(hard.overloaded)
        #expect(!hard.bottomedOut, "overload without bottoming out: the damper did it")
        // From 0.125: rate 1.25 → 250 + 1250 = 1500, under the clamp.
        let firm = solve(distance: 1.25, previous: 0.125)
        #expect(approxEqual(firm.force, 1_500))
        #expect(!firm.overloaded)
    }

    @Test("bottoming out caps the compression at maxTravel and counts as overloaded")
    func bottomOut() {
        // distance 0.75 → raw 0.75 ≥ travel 0.5. Held there (previous 0.5):
        // rate 0, spring 500 N — well under the clamp, overloaded anyway.
        let step = solve(distance: 0.75, previous: 0.5)
        #expect(step.compression == 0.5)
        #expect(step.bottomedOut)
        #expect(step.overloaded)
        #expect(step.force == 500)
    }

    @Test("uniformScale scales reach and travel, not the rates")
    func uniformScaleScalesGeometryOnly() {
        // Scale 2: reach 3.0, travel 1.0. distance 2.75 is out of reach
        // unscaled, x = 0.25 scaled, and the spring force is the same k·x.
        #expect(solve(distance: 2.75) == .noContact)
        let scaled = solve(distance: 2.75, previous: 0.25, scale: 2)
        #expect(scaled.compression == 0.25)
        #expect(scaled.force == 250)
        // distance 1.5: raw 1.5 caps at the scaled travel 1.0.
        let bottomed = solve(distance: 1.5, previous: 1.0, scale: 2)
        #expect(bottomed.compression == 1.0)
        #expect(bottomed.bottomedOut)
        #expect(bottomed.force == 1_000)
    }

    @Test("touchdown: previous 0 and penetration v·dt recover the sink speed as the rate")
    func touchdownRateIsSinkSpeed() {
        // 1.25 m/s sink for one 0.1 s substep: penetration 0.125 → rate 1.25,
        // F = 1000·0.125 + 1000·1.25 = 1375. No special case in the solver.
        let sink: Float = 1.25
        let step = solve(distance: Self.strut.reach - sink * Self.h)
        #expect(approxEqual(step.compression, 0.125))
        #expect(approxEqual(step.compressionRate, sink))
        #expect(approxEqual(step.force, 1_375, tolerance: 1e-3))
    }
}
