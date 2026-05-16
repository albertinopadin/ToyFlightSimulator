//
//  PhysicsWorld.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

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
    
    private var entities: [PhysicsEntity]
    private var updateType: PhysicsUpdateType
    private var broadPhase = BroadPhaseCollisionDetector()
    
    // Performance testing flags
    public var useBroadPhase: Bool = true
    
    init(entities: [PhysicsEntity] = [], updateType: PhysicsUpdateType = .NaiveEuler) {
        self.entities = entities
        self.updateType = updateType
    }
    
    public func setEntities(_ entities: [PhysicsEntity]) {
        self.entities = entities
    }
    
    public func addEntity(_ entity: PhysicsEntity) {
        entities.append(entity)
    }
    
    public func addEntities(_ entities: [PhysicsEntity]) {
        self.entities += entities
    }
    
    public func update(deltaTime: Float) {
        for i in entities.indices {
            entities[i].resetCollisions()
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
    private func naiveUpdate(deltaTime: Float, collisionPairs: [(PhysicsEntity, PhysicsEntity)]) {
        // For now, naive update doesn't handle collisions, but we pass pairs for future use
        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &self.entities)
    }
    
    private func heckerVerletUpdate(deltaTime: Float, collisionPairs: [(PhysicsEntity, PhysicsEntity)]) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: &entities, collisionPairs: collisionPairs)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &entities)
    }
    
    // Original O(n²) update methods for comparison
    private func naiveUpdateOriginal(deltaTime: Float) {
        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &self.entities)
    }
    
    private func heckerVerletUpdateOriginal(deltaTime: Float) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: &entities)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &entities)
    }
    
    // Get broad-phase statistics for performance analysis
    public func getBroadPhaseStats() -> (totalChecks: Int, checksSaved: Int) {
        return broadPhase.getStatistics()
    }
    
    static func getDistance(_ pointA: float3, _ pointB: float3) -> Float {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        let dz = pointA.z - pointB.z
        return sqrt((pow(dx, 2) + pow(dy, 2) + pow(dz, 2)))
    }
    
    static func getCollisionData(_ entityA: PhysicsEntity, _ entityB: PhysicsEntity) -> CollisionData {
        switch (entityA.collisionShape, entityB.collisionShape) {
            case (.Sphere, .Sphere):
                let unormCV = Self.getUnnormalizedCollisionVector(entityA.getPosition(), entityB.getPosition())
                let penetrationDepth = Self.getPenetrationDepth(ballA: entityA as! SphereRigidBody,
                                                                ballB: entityB as! SphereRigidBody,
                                                                unnormalizedCollisionVector: unormCV)
                return CollisionData(collisionVector: unormCV.normalize(), penetrationDepth: penetrationDepth)
            
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
    
    static private func getUnnormalizedCollisionVector(_ pointA: float3, _ pointB: float3) -> float3 {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        let dz = pointA.z - pointB.z
        return [dx, dy, dz]
    }
    
    static public func getPenetrationDepth(ballA: SphereRigidBody,
                                           ballB: SphereRigidBody,
                                           unnormalizedCollisionVector: float3) -> Float {
        return ballA.collisionRadius + ballB.collisionRadius - unnormalizedCollisionVector.magnitude
    }
    
    // TODO: For now this assumes an infinite plane at 0, 0, 0 strecting out in the x and z axes:
    static public func getPenetrationDepth(ball: SphereRigidBody, plane: PlaneRigidBody) -> Float {
        return ball.collisionRadius - ball.getPosition().y
    }
    
    // TODO: Might make more sense to have this method in PhysicsEntity
    static func collided(entityA: PhysicsEntity, entityB: PhysicsEntity) -> Bool {
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
        return Self.getDistance(sphereA.getPosition(), sphereB.getPosition()) <=
                                (sphereA.collisionRadius + sphereB.collisionRadius)
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
