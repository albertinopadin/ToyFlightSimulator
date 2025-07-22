//
//  Missile.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/21/23.
//

class Missile: SubMeshGameObject {
    var direction: float3 = [0, 0, 0]
    var speed: Float = 0.0
    
    init(name: String, modelType: ModelType, meshType: SingleSMMeshType) {
        super.init(name: name, modelType: modelType, meshType: meshType)
    }
    
    func fire(direction: float3, speed: Float) {
        self.direction = direction
        self.speed = speed
    }
    
    override func doUpdate() {
        let currentPos = self.getPosition()
//        print("[Missile doUpdate] currentPos: \(currentPos)")
        // TODO: This is hardcoded from scene origin
        if abs(currentPos.x) > 1000 || abs(currentPos.y) > 1000 || abs(currentPos.z) > 1000 {
            // Reap from scene
            print("Removing self {\(self.getName()), \(self.getID())} from scene.")
            self.parent?.removeChild(self)
        } else {
            super.doUpdate()
            let delta = direction * speed
            let newPos = currentPos + delta
            self.setPosition(newPos)
        }
    }
}

