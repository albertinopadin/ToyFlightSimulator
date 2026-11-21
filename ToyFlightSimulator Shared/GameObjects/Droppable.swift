//
//  Droppable.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/2/23.
//

class Droppable: SubMeshGameObject, AircraftStore {
    /// World gravity along −Y, from the physics world's one written value.
    /// This is the legacy kinematic drop path, not a RigidBody.
    let gravity: Float = -PhysicsWorld.standardGravity
    var velocityVector: float3 = [0, 0, 0]
    var forwardVelocityComponent: Float = 0.0
    /// Distance traveled since release. Counted from the steps doUpdate applies
    /// (velocityVector, meters per tick), not from the position, so a floating-origin shift
    /// neither reaps the store nor keeps it alive. Nothing stops the fall at the ground, so
    /// most of the 100 km (`AircraftStore`) is below it.
    var travelLimit = TravelDistanceLimit(maxDistance: Droppable.MAX_DISTANCE_BEFORE_REAP)
    
    init(name: String, modelType: ModelType, meshType: SingleSMMeshType) {
        super.init(name: name, modelType: modelType, meshType: meshType)
    }
    
    func drop(forwardComponent: Float) {
        self.forwardVelocityComponent = forwardComponent
    }
    
    override func doUpdate() {
        if travelLimit.reachedLimit {
            // Reap from scene (graph + SceneManager collections)
            print("Removing self {\(self.getName()), \(self.getID())} from scene.")
            self.removeFromScene()
        } else {
            super.doUpdate()
            if velocityVector.y < 1000 {
                // TODO: This is probably slightly off
                var gravityInc: Float
                if velocityVector.y > 0 {
                    gravityInc = velocityVector.y + (velocityVector.y * (gravity / 60.0))
                } else {
                    gravityInc = gravity / 60
                }
                
                velocityVector = float3(x: 0.0, y: gravityInc, z: -forwardVelocityComponent)
            }
            
            let newPos = self.getPosition() + velocityVector
            self.setPosition(newPos)
            travelLimit.move(by: velocityVector)
        }
    }
}
