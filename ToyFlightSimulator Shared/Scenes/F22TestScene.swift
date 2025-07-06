//
//  F22TestScene.swift
//  ToyFlightSimulator
//
//  Test scene for F22 landing gear animation
//

final class F22TestScene: GameScene {
    var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                        near: 0.01,
                                        far: 1000000.0)
    
    private func addGround() {
        let groundColor = float4(0.3, 0.7, 0.1, 1.0)
        let ground = CollidablePlane()
        ground.collisionNormal = [0, 1, 0]
        ground.collisionShape = .Plane
        ground.restitution = 1.0
        ground.isStatic = true
        ground.setColor(groundColor)
        ground.rotateZ(Float(270).toRadians)
        ground.setScale(1000)
        addChild(ground)
    }
    
    override func buildScene() {
        addGround()
        
        // Use the enhanced F22 with rotation animation
        let jet = CollidableF22_Enhanced(scale: 0.25)
        
        addCamera(attachedCamera)
        
        let container = ContainerNode(camera: attachedCamera, cameraOffset: jet.cameraOffset)
        container.addChild(jet)
        addChild(container)
        
        jet.hasFocus = true
        
        // Add some reference objects
        let sphere = Sphere()
        sphere.setColor(float4(1, 0, 0, 1))
        sphere.setPosition(10, 5, 0)
        sphere.setScale(2.0)
        addChild(sphere)
        
        // Add instructions text (would need UI implementation)
        print("=== F22 Landing Gear Test ===")
        print("Press 'G' to toggle landing gear")
        print("Watch for rotation animation (3 seconds)")
    }
}