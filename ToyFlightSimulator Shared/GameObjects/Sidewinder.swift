//
//  Sidewinder.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

class Sidewinder: SubMeshGameObject {
    var direction: float3 = float3(0, 0, 0)
    var speed: Float = 0.0
    
    init() {
        super.init(name: "Sidewinder", meshType: .F18_Sidewinder, renderPipelineStateType: .OpaqueMaterial)
    }
    
    func fire(direction: float3, speed: Float) {
        self.direction = direction
        self.speed = speed
    }
    
    override func doUpdate() {
        super.doUpdate()
        let currentPos = self.getPosition()
        let delta = direction * speed
        let newPos = currentPos + delta
        
        if abs(newPos.x) > 1000 || abs(newPos.y) > 1000 || abs(newPos.z) > 1000 {
            // Reap from scene
            print("Removing self {\(self.getName()), \(self.getID())} from scene.")
            self.parent?.removeChild(self)
        } else {
            self.setPosition(newPos)
        }
    }
}
