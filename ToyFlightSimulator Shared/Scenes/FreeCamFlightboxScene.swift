//
//  FreeCamFlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/23.
//

class FreeCamFlightboxScene: GameScene {
    var camera = DebugCamera()
//    var jet = F22(shouldUpdateOnPlayerInput: false)
    var jet = CollidableF22(shouldUpdateOnPlayerInput: false)
    var sun = Sun(modelType: .Sphere)
    var ground = Quad()
    var sidewinderMissile = Sidewinder()
    var aim120 = AIM120()
    
//    let physicsWorld = PhysicsWorld(updateType: .NaiveEuler)
    let physicsWorld = PhysicsWorld(updateType: .HeckerVerlet)
    var entities: [PhysicsEntity] = []
    
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
        
        entities.append(ground)
    }
    
    override func buildScene() {
        sun.setPosition(1, 25, 5)
        sun.setLightColor(1, 1, 1)
        addLight(sun)
        
        print("Sun light type: \(sun.lightType)")
        
        if _rendererType == .OrderIndependentTransparency {
            let sky = SkySphere(textureType: .Clouds_Skysphere)
            addChild(sky)
        } else {
            let sky = SkyBox(textureType: .SkyMap)
            addChild(sky)
        }
        
        addGround()
        
//        camera.setPosition(4, 12, 20)
        camera.setPosition(24, 6, 5)
//        camera.setRotationX(Float(15).toRadians)
        camera.setRotationY(Float(75).toRadians)
        addCamera(camera)
        
//        f18.setScale(0.25)  // TODO: setScale doesn't work
        jet.setPosition(0, 10, 0)
        
        jet.collisionRadius = 2.5
        
        jet.setScale(0.125)
        
        jet.restitution = 0.8
        addChild(jet)
        
        sidewinderMissile.setScale(4.0)
        sidewinderMissile.setPosition(0, 2, -12)
        let sidewinderSubmeshMetadata = sidewinderMissile.getSubmeshVertexMetadata()
        let newOrigin = float3(0, 0, sidewinderSubmeshMetadata.maxZ / 2)
        sidewinderMissile.setSubmeshOrigin(newOrigin)
        sidewinderMissile.rotateY(Float(90).toRadians)
        addChild(sidewinderMissile)
        
        aim120.setScale(4.0)
        aim120.setPosition(0, 4, -24)
        aim120.rotateY(Float(90).toRadians)
        addChild(aim120)
        
        TextureLoader.PrintCacheInfo()
        
        entities.append(jet)
        physicsWorld.setEntities(entities)
    }
    
    private var shouldUpdatePhysics = false
    
    override func doUpdate() {
        super.doUpdate()
        
        sidewinderMissile.rotateY(Float(GameTime.DeltaTime))
        aim120.rotateY(Float(GameTime.DeltaTime))
        
        if GameTime.DeltaTime < 1.0 {
            physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
        }
        
//        if GameTime.DeltaTime < 1.0 && shouldUpdatePhysics {
//            physicsWorld.update(deltaTime: Float(GameTime.DeltaTime) * 2.0)
//        }
//        
//        shouldUpdatePhysics.toggle()
    }
}
