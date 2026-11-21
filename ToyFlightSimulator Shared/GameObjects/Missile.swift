//
//  Missile.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/21/23.
//

class Missile: SubMeshGameObject, AircraftStore {
    var direction: float3 = [0, 0, 0]
    /// Meters moved per update tick (not per second).
    var speed: Float = 0.0
    /// Distance flown since release. Counted from the steps doUpdate applies, not from the
    /// position, so a floating-origin shift neither reaps the missile nor keeps it alive.
    var travelLimit = TravelDistanceLimit(maxDistance: Missile.MAX_DISTANCE_BEFORE_REAP)
    
    init(name: String, modelType: ModelType, meshType: SingleSMMeshType) {
        super.init(name: name, modelType: modelType, meshType: meshType)
    }
    
    func fire(direction: float3, speed: Float) {
        self.direction = direction
        self.speed = speed
    }
    
    override func doUpdate() {
        if travelLimit.reachedLimit {
            // Reap from scene (graph + SceneManager collections)
            print("Removing self {\(self.getName()), \(self.getID())} from scene.")
            self.removeFromScene()
        } else {
            super.doUpdate()
            let delta = direction * speed
            let newPos = self.getPosition() + delta
            self.setPosition(newPos)
            travelLimit.move(by: delta)
        }
    }
}

