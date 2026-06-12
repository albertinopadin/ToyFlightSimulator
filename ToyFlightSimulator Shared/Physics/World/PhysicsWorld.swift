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

struct CollisionData {
    let collisionVector: float3
    let penetrationDepth: Float
}

final class PhysicsWorld {
    public static let gravity: float3 = [0, -9.81, 0]
//    public static let gravity: float3 = [0, -(9.8 * 9.8), 0]

    // NOTE(P6): storage is the concrete class `RigidBody`, not `any PhysicsEntity`.
    // RigidBody is currently the only conformer; concrete storage gives direct
    // class dispatch in the solver loops instead of protocol-witness dispatch.
    // If a second, non-RigidBody PhysicsEntity type is ever added, either give
    // it a RigidBody base or revisit these signatures (PhysicsWorld, the
    // solvers, HeckerCollisionResponse, BroadPhaseCollisionDetector).
    private var entities: [RigidBody]
    private var updateType: PhysicsUpdateType
    private var broadPhase = BroadPhaseCollisionDetector()

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
                         collisionPairs: collisionPairs)
    }

    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(RigidBody, RigidBody)]) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, collisionPairs: collisionPairs)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    // Original O(n²) update methods for comparison
    private func naiveUpdateOriginal(deltaTime: Float) {
        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    private func heckerVerletUpdateOriginal(deltaTime: Float) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: entities)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: entities)
    }

    // Get broad-phase statistics for performance analysis
    public func getBroadPhaseStats() -> (totalChecks: Int, checksSaved: Int) {
        return broadPhase.getStatistics()
    }

    static func getDistance(_ pointA: float3, _ pointB: float3) -> Float {
        return simd_distance(pointA, pointB)
    }

    static func getCollisionData(_ entityA: RigidBody, _ entityB: RigidBody) -> CollisionData {
        switch (entityA.collisionShape, entityB.collisionShape) {
            case (.Sphere, .Sphere):
                // One sqrt total (was: sqrt in normalize() + sqrt in magnitude + pow()s).
                let ballA = entityA as! SphereRigidBody
                let ballB = entityB as! SphereRigidBody
                let delta = ballA.getPosition() - ballB.getPosition()
                let distance = simd_length(delta)
                let normal: float3 = distance > 0 ? delta / distance : .zero
                return CollisionData(collisionVector: normal,
                                     penetrationDepth: ballA.collisionRadius + ballB.collisionRadius - distance)

            case (.Sphere, .Plane):
                let penetrationDepth = Self.getPenetrationDepth(ball: entityA as! SphereRigidBody,
                                                                plane: entityB as! PlaneRigidBody)
                return CollisionData(collisionVector: (entityB as! PlaneRigidBody).collisionNormal,
                                     penetrationDepth: penetrationDepth)

            case (.Plane, .Sphere):
                let penetrationDepth = Self.getPenetrationDepth(ball: entityB as! SphereRigidBody,
                                                                plane: entityA as! PlaneRigidBody)
                return CollisionData(collisionVector: (entityA as! PlaneRigidBody).collisionNormal,
                                     penetrationDepth: penetrationDepth)

            case (.Plane, .Plane):
                print("[getCollisionVector] Collision plane/plane")
                return CollisionData(collisionVector: .zero, penetrationDepth: 0.0)
        }
    }

    static public func getPenetrationDepth(ballA: SphereRigidBody,
                                           ballB: SphereRigidBody,
                                           unnormalizedCollisionVector: float3) -> Float {
        return ballA.collisionRadius + ballB.collisionRadius - unnormalizedCollisionVector.magnitude
    }
    // ^ kept for API compatibility, but no longer called on the hot path
    //   (getCollisionData computes the sphere-sphere depth inline with one sqrt).

    // TODO: For now this assumes an infinite plane at 0, 0, 0 strecting out in the x and z axes:
    static public func getPenetrationDepth(ball: SphereRigidBody, plane: PlaneRigidBody) -> Float {
        return ball.collisionRadius - ball.getPosition().y
    }

    // TODO: Might make more sense to have this method in PhysicsEntity
    static func collided(entityA: RigidBody, entityB: RigidBody) -> Bool {
        switch (entityA.collisionShape, entityB.collisionShape) {
            case (.Sphere, .Sphere):
                return Self.collided(sphereA: entityA as! SphereRigidBody, sphereB: entityB as! SphereRigidBody)

            case (.Sphere, .Plane):
                return Self.collided(sphere: entityA as! SphereRigidBody, plane: entityB as! PlaneRigidBody)

            case (.Plane, .Sphere):
                return Self.collided(sphere: entityB as! SphereRigidBody, plane: entityA as! PlaneRigidBody)

            case (.Plane, .Plane):
                print("[collided] Check plane/plane")
                return Self.collided(planeA: entityA as! PlaneRigidBody, planeB: entityB as! PlaneRigidBody)
        }
    }

    static func collided(sphereA: SphereRigidBody, sphereB: SphereRigidBody) -> Bool {
        // Squared-distance compare: no sqrt on the narrow-phase reject path.
        let radiusSum = sphereA.collisionRadius + sphereB.collisionRadius
        return simd_distance_squared(sphereA.getPosition(), sphereB.getPosition()) <= radiusSum * radiusSum
    }

    static func collided(sphere: SphereRigidBody, plane: PlaneRigidBody) -> Bool {
        let spherePosVector = plane.getPosition() - sphere.getPosition()
        let sphereVecToPlane = dot(spherePosVector, -plane.collisionNormal)
        return sphereVecToPlane <= sphere.collisionRadius
    }

    static func collided(planeA: PlaneRigidBody, planeB: PlaneRigidBody) -> Bool {
        return false
    }
}
