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
    
    let eulerPhysics = EulerSolver.self
    
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
        eulerPhysics.step(deltaTime: deltaTime, gravity: PhysicsWorld.gravity, entities: &self.entities)
        checkEntitiesHitFloor()
    }
    
    private func heckerVerletUpdate(deltaTime: Float) {
        // TODO
    }
    
    private func checkEntitiesHitFloor() {
        for i in 0..<entities.count {
            let entityPos = entities[i].getPosition()
            let entityRadius = entities[i].radius
            
            if ((entityPos.y - entityRadius) <= 0 && entities[i].velocity.y <= 0) {
                entities[i].acceleration = [entities[i].acceleration.x, 0, entities[i].acceleration.z]
                entities[i].velocity = [entities[i].velocity.x,
                                        -entities[i].velocity.y,
                                        entities[i].velocity.z]
                entities[i].setPosition([entityPos.x, entityRadius, entityPos.z])
            }
        }
    }
    
    static func getDistance(_ pointA: float3, _ pointB: float3) -> Float {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        let dz = pointA.z - pointB.z
        return sqrt((pow(dx, 2) + pow(dy, 2) + pow(dz, 2)))
    }
    
    static func getCollisionVector(_ pointA: float3, _ pointB: float3) -> float3 {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        let dz = pointA.z - pointB.z
        return [dx, dy, dz]
    }
    
    static func collided(entityA: PhysicsEntity, entityB: PhysicsEntity) -> Bool {
        // TODO: This assumes all collidables are spheres
        return Self.getDistance(entityA.getPosition(), entityB.getPosition()) <= (entityA.radius + entityB.radius)
    }
}
