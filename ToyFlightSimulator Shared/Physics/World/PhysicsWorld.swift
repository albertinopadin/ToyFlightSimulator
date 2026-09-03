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
    public static let gravity: float3 = [0, -9.81, 0]

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

    public func update(deltaTime: Float) {
        for entity in entities {
            entity.resetCollisions()
            // Node transforms can change between steps without going through
            // RigidBody.setPosition (attitude rotation), so every world-collider
            // cache is invalidated here. setPosition covers mid-step moves.
            entity.invalidateWorldColliders()
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
