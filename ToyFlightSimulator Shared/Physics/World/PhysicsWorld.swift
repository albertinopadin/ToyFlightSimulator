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
    public static let gravity: float3 = [0, -9.8, 0]
    
    private var entities: [PhysicsEntity]
    private var updateType: PhysicsUpdateType
    
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
        for var entity in entities {
            entity.reset()
        }
        
        switch self.updateType {
            case .NaiveEuler:
                naiveUpdate(deltaTime: deltaTime)
                
            case .HeckerVerlet:
                heckerVerletUpdate(deltaTime: deltaTime)
        }
    }
    
    private func naiveUpdate(deltaTime: Float) {
        EulerSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &self.entities)
    }
    
    private func heckerVerletUpdate(deltaTime: Float) {
        HeckerCollisionResponse.resolveCollisions(deltaTime: deltaTime, entities: &entities)
        VerletSolver.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &entities)
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
                let penetrationDepth = Self.getPenetrationDepth(ballA: entityA as! SpherePhysicsEntity,
                                                                ballB: entityB as! SpherePhysicsEntity,
                                                                unnormalizedCollisionVector: unormCV)
                return CollisionData(collisionVector: unormCV.normalize(), penetrationDepth: penetrationDepth)
            
            case (.Sphere, .Plane):
                let penetrationDepth = Self.getPenetrationDepth(ball: entityA as! SpherePhysicsEntity,
                                                                plane: entityB as! PlanePhysicsEntity)
                return CollisionData(collisionVector: (entityB as! PlanePhysicsEntity).collisionNormal,
                                     penetrationDepth: penetrationDepth)
                
            case (.Plane, .Sphere):
                let penetrationDepth = Self.getPenetrationDepth(ball: entityB as! SpherePhysicsEntity,
                                                                plane: entityA as! PlanePhysicsEntity)
                return CollisionData(collisionVector: (entityA as! PlanePhysicsEntity).collisionNormal,
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
    
    static public func getPenetrationDepth(ballA: SpherePhysicsEntity,
                                           ballB: SpherePhysicsEntity,
                                           unnormalizedCollisionVector: float3) -> Float {
        return ballA.collisionRadius + ballB.collisionRadius - unnormalizedCollisionVector.magnitude
    }
    
    // TODO: For now this assumes an infinite plane at 0, 0, 0 strecting out in the x and z axes:
    static public func getPenetrationDepth(ball: SpherePhysicsEntity, plane: PlanePhysicsEntity) -> Float {
        return ball.collisionRadius - ball.getPosition().y
    }
    
    // TODO: Might make more sense to have this method in PhysicsEntity
    static func collided(entityA: PhysicsEntity, entityB: PhysicsEntity) -> Bool {
        switch (entityA.collisionShape, entityB.collisionShape) {
            case (.Sphere, .Sphere):
                return Self.collided(sphereA: entityA as! SpherePhysicsEntity, sphereB: entityB as! SpherePhysicsEntity)
                
            case (.Sphere, .Plane):
                return Self.collided(sphere: entityA as! SpherePhysicsEntity, plane: entityB as! PlanePhysicsEntity)
                
            case (.Plane, .Sphere):
                return Self.collided(sphere: entityB as! SpherePhysicsEntity, plane: entityA as! PlanePhysicsEntity)
                
            case (.Plane, .Plane):
                print("[collided] Check plane/plane")
                return Self.collided(planeA: entityA as! PlanePhysicsEntity, planeB: entityB as! PlanePhysicsEntity)
        }
    }
    
    static func collided(sphereA: SpherePhysicsEntity, sphereB: SpherePhysicsEntity) -> Bool {
        return Self.getDistance(sphereA.getPosition(), sphereB.getPosition()) <=
                                (sphereA.collisionRadius + sphereB.collisionRadius)
    }
    
    static func collided(sphere: SpherePhysicsEntity, plane: PlanePhysicsEntity) -> Bool {
        let spherePosVector = plane.getPosition() - sphere.getPosition()
        let sphereVecToPlane = dot(spherePosVector, -plane.collisionNormal)
        return sphereVecToPlane <= sphere.collisionRadius
    }
    
    static func collided(planeA: PlanePhysicsEntity, planeB: PlanePhysicsEntity) -> Bool {
        return false
    }
}
