//
//  FixedTimestepTests.swift
//  ToyFlightSimulatorTests
//
//  B.3 (B-timestep): PhysicsWorld.update(deltaTime:) slices frame time into
//  fixed 1/120 s substeps behind a per-instance accumulator. Metal-free.
//

import Foundation
import Testing
import simd
@testable import ToyFlightSimulator

@Suite("Fixed timestep", .tags(.physics))
struct FixedTimestepTests {
    private final class SubstepCounter {
        var calls = 0
        var lastDelta: Float = 0
    }

    /// A body whose force hook counts substeps.
    private func makeCountingWorld() -> (world: PhysicsWorld, counter: SubstepCounter) {
        let counter = SubstepCounter()
        let probe = RigidBody(detachedAt: .zero)
        probe.shouldApplyGravity = false
        probe.forceGenerator = { _, delta, _ in
            counter.calls += 1
            counter.lastDelta = delta
        }
        let world = PhysicsWorld(entities: [probe], updateType: .HeckerVerlet)
        return (world, counter)
    }

    @Test("a 60 Hz frame runs exactly two substeps of fixedDelta")
    func sixtyHzFrames() {
        let (world, counter) = makeCountingWorld()
        for _ in 0..<10 { world.update(deltaTime: 1.0 / 60.0) }
        #expect(counter.calls == 20)
        #expect(counter.lastDelta == PhysicsWorld.fixedDelta)
    }

    @Test("1/240 s frames accumulate: a substep every second call")
    func accumulationAcrossSmallFrames() {
        let (world, counter) = makeCountingWorld()
        for _ in 0..<8 { world.update(deltaTime: 1.0 / 240.0) }
        #expect(counter.calls == 4)
    }

    @Test("a huge frame runs maxSubstepsPerUpdate and drops the rest")
    func hitchClampDropsExcessTime() {
        let (world, counter) = makeCountingWorld()
        world.update(deltaTime: 10.0)
        #expect(counter.calls == PhysicsWorld.maxSubstepsPerUpdate)
        world.update(deltaTime: 1.0 / 60.0)   // the dropped time is gone, not banked
        #expect(counter.calls == PhysicsWorld.maxSubstepsPerUpdate + 2)
    }

    @Test("the accumulator is per world (rule 1), not process-wide")
    func accumulatorIsPerInstance() {
        let (a, countA) = makeCountingWorld()
        let (b, countB) = makeCountingWorld()
        a.update(deltaTime: 1.0 / 240.0)
        b.update(deltaTime: 1.0 / 240.0)   // a shared accumulator would step here
        #expect(countA.calls == 0)
        #expect(countB.calls == 0)
        a.update(deltaTime: 1.0 / 240.0)
        #expect(countA.calls == 1)
        #expect(countB.calls == 0)
    }

    /// How frame time is sliced into update calls must not change the
    /// simulation. All three slicings run the same substep sequence, so
    /// positions compare exactly, contacts and pair order included.
    @Test("frame partitioning is exact: 1×(1/30) ≡ 2×(1/60) ≡ 4×(1/120)",
          arguments: [ParityScenario.singleBounceVerlet, ParityScenario.ballCluster16])
    func partitioningInvariance(_ scenario: ParityScenario) {
        let a = scenario.build()
        let b = scenario.build()
        let c = scenario.build()
        for _ in 0..<90 {   // 3 s, compared at every 1/30 s boundary
            a.world.update(deltaTime: 1.0 / 30.0)
            for _ in 0..<2 { b.world.update(deltaTime: 1.0 / 60.0) }
            for _ in 0..<4 { c.world.update(deltaTime: 1.0 / 120.0) }
            for i in a.spheres.indices {
                #expect(a.spheres[i].getPosition() == b.spheres[i].getPosition())
                #expect(b.spheres[i].getPosition() == c.spheres[i].getPosition())
            }
        }
    }
}
