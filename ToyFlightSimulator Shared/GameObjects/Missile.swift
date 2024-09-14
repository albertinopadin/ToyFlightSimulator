//
//  Missile.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/21/23.
//

class Missile: SubMeshGameObject {
    var direction: float3 = [0, 0, 0]
    var speed: Float = 0.0
    
    init(name: String,
         modelType: ModelType,
         meshType: SingleSMMeshType,
         renderPipelineStateType: RenderPipelineStateType = .OpaqueMaterial) {
        super.init(name: name,
                   modelType: modelType,
                   meshType: meshType,
                   renderPipelineStateType: renderPipelineStateType)
    }
    
    init(name: String,
         modelName: String,
         submeshName: String,
         renderPipelineStateType: RenderPipelineStateType = .OpaqueMaterial) {
        super.init(name: name,
                   modelName: modelName,
                   submeshName: submeshName,
                   renderPipelineStateType: renderPipelineStateType)
    }
    
    func fire(direction: float3, speed: Float) {
        self.direction = direction
        self.speed = speed
    }
    
    override func doUpdate() {
        let currentPos = self.getPosition()
//        print("[Missile doUpdate] currentPos: \(currentPos)")
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

