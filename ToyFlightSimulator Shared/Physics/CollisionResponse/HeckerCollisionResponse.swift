//
//  HeckerCollisionResponse.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

// From https://www.chrishecker.com/images/e/e7/Gdmphys3.pdf
// and: https://www.youtube.com/watch?v=vQO_hPOE-1Y

extension float3 {
    var magnitude: Float {
        sqrt(x * x + y * y + z * z)
    }
    
    func normalize() -> float3 {
        return self / magnitude
    }
}

final class HeckerCollisionResponse {
    static func resolveCollisions(deltaTime: Float, entities: inout [PhysicsEntity]) {
        for a in 0..<entities.count {
            for b in 0..<entities.count {
                if a != b {
                    let entityA = entities[a]
                    let entityB = entities[b]
                    
                    if PhysicsWorld.collided(entityA: entityA, entityB: entityB) {
                        let collisionVector = PhysicsWorld.getCollisionVector(entityA, entityB)
                        
                        let penetrationMagnitude = entityA.radius + entityB.radius - collisionVector.magnitude
                        let collisionNormal = collisionVector.normalize()
                        entities[a].setPosition(entities[a].getPosition() + collisionNormal * (penetrationMagnitude / 2))
                        entities[b].setPosition(entities[b].getPosition() - collisionNormal * (penetrationMagnitude / 2))
                        
                        let relativeVelo = entityA.velocity - entityB.velocity
                        let e = min(entityA.restitution, entityB.restitution)
                        var j = -(1 + e) * dot(relativeVelo, collisionNormal)
                        j /= ((1.0 / entityA.mass) + (1.0 / entityB.mass))
                        
                        let entityADeltaVelo = j / entityA.mass * collisionNormal
                        let entityBDeltaVelo = j / entityB.mass * collisionNormal
                        
                        entities[a].velocity += entityADeltaVelo.magnitude > 1.0 ? entityADeltaVelo : .zero
                        entities[b].velocity -= entityBDeltaVelo.magnitude > 1.0 ? entityBDeltaVelo : .zero
                    }
                }
            }
        }
    }
}
