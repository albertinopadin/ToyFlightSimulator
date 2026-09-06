//
//  PhysicsWorld.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

import simd

enum PhysicsUpdateType {
    case NaiveEuler
    case HeckerVerlet
}

final class PhysicsWorld {
    /// Fixed simulation step. Physics must not change with the menu's
    /// 30–120 Hz refresh selection; before B-timestep it did, because
    /// update(deltaTime:) consumed the raw frame delta. 1/120 s divides every
    /// selectable frame period exactly (120 Hz: 1 substep per frame, 60 Hz: 2,
    /// 30 Hz: 4) and makes the rest jitter bound g·dt² a constant 0.68 mm.
    public static let fixedDelta: Float = 1.0 / 120.0
    
    /// At most this many substeps per update call (66.7 ms of simulated
    /// time). Time beyond it is dropped, not carried, like
    /// UpdateThread.maxDeltaTime one level down. Replaces the scenes'
    /// `GameTime.DeltaTime < 1.0` guards.
    public static let maxSubstepsPerUpdate = 8
    
    /// Standard gravity, m/s²: the one place 9.81 is written. `gravity` is
    /// this magnitude along −Y; static-load sizing reads the scalar
    /// (AircraftLandingGearSpec.staticStance).
    public static let standardGravity: Float = 9.81
    public static let gravity: float3 = [0, -standardGravity, 0]
    
    /// Frame time not yet simulated. Per instance (rule 1: tests run several
    /// worlds in one process). Always below fixedDelta after an update.
    private var accumulator: Float = 0

    // Storage is the concrete class RigidBody for direct dispatch in the solver
    // loops. If a second PhysicsEntity type is ever added, give it a RigidBody
    // base or revisit the solver signatures.
    private var entities: [RigidBody]
    private var updateType: PhysicsUpdateType
    private var broadPhase = BroadPhaseCollisionDetector()

    /// Reused per-instance scratch (tests run several worlds concurrently in
    /// one process, so nothing here may be static).
    private var contactsScratch: [Contact] = []
    private var allPairsScratch: [(RigidBody, RigidBody)] = []

    /// When false, every pair is a candidate: the O(n²) comparison baseline for
    /// the broad phase's statistics. Four of the six parity goldens run this way.
    public var useBroadPhase: Bool = true
    /// Forwarded to the broad phase; when false (default) the per-frame
    /// CFAbsoluteTimeGetCurrent() calls and stat bookkeeping are skipped.
    public var collectBroadPhaseStatistics: Bool {
        get { broadPhase.collectStatistics }
        set { broadPhase.collectStatistics = newValue }
    }

    init(entities: [RigidBody] = [], updateType: PhysicsUpdateType = .NaiveEuler) {
        self.entities = entities
        self.updateType = updateType
    }

    public func setEntities(_ entities: [RigidBody]) {
        self.entities = entities
    }

    public func addEntity(_ entity: RigidBody) {
        entities.append(entity)
    }

    public func addEntities(_ entities: [RigidBody]) {
        self.entities += entities
    }

    /// `deltaTime` is the frame delta. The world advances in fixed substeps
    /// and banks the remainder. Counting by division and subtracting once is
    /// exact in Float for 1/30, 1/60, 1/120 and 1/240 s frames (zero residue),
    /// which lets FixedTimestepTests compare partitions with ==.
    public func update(deltaTime: Float) {
        accumulator = min(accumulator + deltaTime, Float(Self.maxSubstepsPerUpdate) * Self.fixedDelta)
        let substeps = Int(accumulator / Self.fixedDelta)
        accumulator -= Float(substeps) * Self.fixedDelta
        for _ in 0..<substeps {
            step(deltaTime: Self.fixedDelta)
        }
    }
    
    /// One fixed substep: the pre-B-timestep update(deltaTime:) body, unchanged.
    private func step(deltaTime: Float) {
        for entity in entities {
            entity.resetCollisions()
            // Node transforms can change between steps without going through
            // RigidBody.setPosition (attitude rotation), so every world-collider
            // cache is invalidated here. setPosition covers mid-step moves.
            entity.invalidateWorldColliders()
            // Per-substep forces (the flight model and the landing-gear suspension).
            entity.forceGenerator?(entity, deltaTime, self)
        }

        let pairs: [(RigidBody, RigidBody)]
        if useBroadPhase {
            broadPhase.update(entities: entities)
            pairs = broadPhase.getPotentialCollisionPairs()
        } else {
            Self.appendAllPairs(of: entities, into: &allPairsScratch)
            pairs = allPairsScratch
        }
        
        switch updateType {
            case .NaiveEuler:
                EulerSolver.step(deltaTime: deltaTime,
                                 gravity: Self.gravity,
                                 entities: entities,
                                 collisionPairs: pairs,
                                 contactsScratch: &contactsScratch)
                
            case .HeckerVerlet:
                HeckerCollisionResponse.resolveCollisions(collisionPairs: pairs,
                                                          contactsScratch: &contactsScratch)
                VerletSolver.step(deltaTime: deltaTime, gravity: Self.gravity, entities: entities)
        }
    }

    /// Every unordered pair (i < j) in index order: the same visiting order as
    /// the old O(n²) loops, so the goldens do not move.
    static func appendAllPairs(of entities: [RigidBody], into out: inout [(RigidBody, RigidBody)]) {
        out.removeAll(keepingCapacity: true)
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                out.append((entities[i], entities[j]))
            }
        }
    }

    /// Distance to the nearest static plane along a ray, or nil. O(planes)
    /// per call; every current scene has one.
    public func raycastStaticPlanes(from origin: float3, direction: float3) -> Float? {
        var nearest: Float? = nil
        for case let plane as PlaneRigidBody in entities where plane.isStatic {
            if let t = NarrowPhase.rayVsPlane(origin: origin,
                                              direction: direction,
                                              planePoint: plane.getPosition(),
                                              planeNormal: plane.collisionNormal),
               t < (nearest ?? .infinity) {
                nearest = t
            }
        }
        
        return nearest
    }

    // MARK: - Deprecated update paths

    /// Deprecated and unused. `update(deltaTime:)` now calls the solvers
    /// directly on the candidate pairs (Phase A cleanup C3). Kept until the
    /// single-path update has soaked; delete together with the three below.
    private func naiveUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        EulerSolver.step(deltaTime: deltaTime,
                         gravity: PhysicsWorld.gravity,
                         entities: entities,
                         collisionPairs: collisionPairs,
                         contactsScratch: &contactsScratch)
    }

    /// Deprecated and unused; see naiveUpdate.
    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        HeckerCollisionResponse.resolveCollisions(collisionPairs: collisionPairs,
                                                  contactsScratch: &contactsScratch)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    /// Deprecated and unused. The broad-phase-off mode of `update(deltaTime:)`
    /// builds the same all-pairs list with appendAllPairs; this body was
    /// rerouted through it when the O(n²) solver overloads were deleted.
    private func naiveUpdateOriginal(deltaTime: Float) {
        Self.appendAllPairs(of: entities, into: &allPairsScratch)
        EulerSolver.step(deltaTime: deltaTime,
                         gravity: PhysicsWorld.gravity,
                         entities: entities,
                         collisionPairs: allPairsScratch,
                         contactsScratch: &contactsScratch)
    }

    /// Deprecated and unused; see naiveUpdateOriginal.
    private func heckerVerletUpdateOriginal(deltaTime: Float) {
        Self.appendAllPairs(of: entities, into: &allPairsScratch)
        HeckerCollisionResponse.resolveCollisions(collisionPairs: allPairsScratch,
                                                  contactsScratch: &contactsScratch)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    // Get broad-phase statistics for performance analysis
    public func getBroadPhaseStats() -> (totalChecks: Int, checksSaved: Int) {
        return broadPhase.getStatistics()
    }
}
