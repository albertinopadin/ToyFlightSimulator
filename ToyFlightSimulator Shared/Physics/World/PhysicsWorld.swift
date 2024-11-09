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

final class PhysicsWorld {
    public static let gravity: float3 = [0, -9.8, 0]
    
    var entities: [PhysicsEntity]
    var updateType: PhysicsUpdateType
    
    init(entities: [PhysicsEntity], updateType: PhysicsUpdateType = .NaiveEuler) {
        self.entities = entities
        self.updateType = updateType
    }
    
    public func update(deltaTime: Float) {
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
    
    static func getCollisionVector(_ entityA: PhysicsEntity, _ entityB: PhysicsEntity) -> float3 {
        return Self.getCollisionVector(entityA.getPosition(), entityB.getPosition())
    }
    
    static func getCollisionVector(_ pointA: float3, _ pointB: float3) -> float3 {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        let dz = pointA.z - pointB.z
        return [dx, dy, dz]
    }
    
    // TODO: Might make more sense to have this method in PhysicsEntity
    static func collided(entityA: PhysicsEntity, entityB: PhysicsEntity) -> Bool {
        // TODO: This assumes all collidables are spheres
        return Self.getDistance(entityA.getPosition(), entityB.getPosition()) <= (entityA.radius + entityB.radius)
    }
}
