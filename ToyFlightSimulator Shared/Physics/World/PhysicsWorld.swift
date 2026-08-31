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

    // NOTE(P6): storage is the concrete class `RigidBody`, not `any PhysicsEntity`.
    // RigidBody is currently the only conformer; concrete storage gives direct
    // class dispatch in the solver loops instead of protocol-witness dispatch.
    // If a second, non-RigidBody PhysicsEntity type is ever added, either give
    // it a RigidBody base or revisit these signatures (PhysicsWorld, the
    // solvers, HeckerCollisionResponse, BroadPhaseCollisionDetector).
    private var entities: [RigidBody]
    private var updateType: PhysicsUpdateType
    private var broadPhase = BroadPhaseCollisionDetector()
    
    /// Per-instance contact scratch (pre-Phase-A correction 1: parameterized
    /// parity cases run multiple live worlds concurrently in one process — no
    /// statics anywhere in the step path). Cleared and refilled by the
    /// response each step; contents are reused scratch, same discipline as
    /// the broad phase's pairs array.
    private var contactsScratch: [Contact] = []

    // Performance testing flags
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
            // Deviation 1: start-of-step invalidation covers node transforms
            // changed since the last step — attitude rotation never routes
            // through RigidBody.setPosition, so the dirty flag alone can't
            // see it. Mid-step moves are covered by setPosition itself.
            entity.invalidateWorldColliders()
        }

        if useBroadPhase {
            // Use optimized broad-phase collision detection
            broadPhase.update(entities: entities)
            let potentialPairs = broadPhase.getPotentialCollisionPairs()

            switch self.updateType {
                case .NaiveEuler:
                    naiveUpdate(deltaTime: deltaTime, collisionPairs: potentialPairs)

                case .HeckerVerlet:
                    heckerVerletUpdate(deltaTime: deltaTime, collisionPairs: potentialPairs)
            }
        } else {
            // Use original O(n²) algorithm for comparison
            switch self.updateType {
                case .NaiveEuler:
                    naiveUpdateOriginal(deltaTime: deltaTime)

                case .HeckerVerlet:
                    heckerVerletUpdateOriginal(deltaTime: deltaTime)
            }
        }
    }

    // Optimized update methods using broad-phase pairs
    private func naiveUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        // P1: the Euler path resolves collisions against the broad-phase
        // candidate pairs instead of its own O(n²) sweep.
        EulerSolver.step(deltaTime: deltaTime,
                         gravity: PhysicsWorld.gravity,
                         entities: entities,
                         collisionPairs: collisionPairs,
                         contactsScratch: &contactsScratch)
    }

    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime,
                                                  collisionPairs: collisionPairs,
                                                  contactsScratch: &contactsScratch)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    // Original O(n²) update methods for comparison
    private func naiveUpdateOriginal(deltaTime: Float) {
        EulerSolver.step(deltaTime: deltaTime,
                         gravity: PhysicsWorld.gravity,
                         entities: entities,
                         contactsScratch: &contactsScratch)
    }

    private func heckerVerletUpdateOriginal(deltaTime: Float) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime,
                                                  entities: entities,
                                                  contactsScratch: &contactsScratch)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    // Get broad-phase statistics for performance analysis
    public func getBroadPhaseStats() -> (totalChecks: Int, checksSaved: Int) {
        return broadPhase.getStatistics()
    }
}
