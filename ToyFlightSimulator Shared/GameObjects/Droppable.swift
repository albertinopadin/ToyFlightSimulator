//
//  Droppable.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/2/23.
//

class Droppable: SubMeshGameObject {
    let gravity: Float = -9.8  // TODO: This should probably go in a constants file somewhere...
    var velocityVector: float3 = [0, 0, 0]
    var forwardVelocityComponent: Float = 0.0
    
    init(name: String, modelType: ModelType, meshType: SingleSMMeshType) {
        super.init(name: name, modelType: modelType, meshType: meshType)
    }
    
    init(name: String, modelName: String, submeshName: String) {
        super.init(name: name, modelName: modelName, submeshName: submeshName)
    }
    
    func drop(forwardComponent: Float) {
        self.forwardVelocityComponent = forwardComponent
    }
    
    override func doUpdate() {
        let currentPos = self.getPosition()
        if abs(currentPos.x) > 1000 || abs(currentPos.y) > 1000 || abs(currentPos.z) > 1000 {
            // Reap from scene
            print("Removing self {\(self.getName()), \(self.getID())} from scene.")
            self.parent?.removeChild(self)
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
            
            let newPos = currentPos + velocityVector
            self.setPosition(newPos)
        }
    }
}
