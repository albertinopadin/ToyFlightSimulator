//
//  FlightboxWithPhysics.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/16/26.
//

final class FlightboxWithPhysics: GameScene {
    var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                        near: 0.01,
                                        far: 1_000_000.0)
    var sun = Sun(modelType: .Sphere)
    
    let physicsWorld = PhysicsWorld(updateType: .NaiveEuler)
    var entities: [PhysicsEntity] = []
    
    override func buildScene() {
        let (_, groundRigidBody) = addGround()
        entities.append(groundRigidBody)
        
        let jet = F22(scale: 0.25)
        let jetRigidBody = SphereRigidBody(gameObject: jet)
        
        addCamera(attachedCamera)
        attachedCamera.attach(to: jet, offset: jet.cameraOffset)
        jet.setPosition(0, 100, 0)
        addChild(jet)
        let jetPos = jet.getPosition()
        
        setupDefaultSky()
        
        // TODO: Why does position with z = 0 result in much darker lighting ???
        sun.setPosition(0, jetPos.y + 100, 4)
        sun.setLightBrightness(1.0)
//        sun.setLightBrightness(0.2)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.4)
        sun.setLightDiffuseIntensity(0.5)
//        sun.setLightDiffuseIntensity(0)
        addLight(sun)
        
        let sunBall = Sphere()
        sunBall.setColor(RED_COLOR)
        sunBall.setPosition(sun.getPosition())
        addChild(sunBall)
        
        let f16 = F16(shouldUpdateOnPlayerInput: false)
        f16.setPosition(0, jetPos.y + 10, jetPos.z - 15)
        f16.rotateY(Float(-90).toRadians)
//        f16.setScale(4.0)
        f16.setScale(10.0)
        addChild(f16)
        
        let sphereBluePos = float3(x: jetPos.x + 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereBlue = Sphere()
        sphereBlue.setPosition(sphereBluePos)
        sphereBlue.setScale(1.5)
        sphereBlue.setColor([0.0, 0.0, 1.0, 0.4])
        addChild(sphereBlue)
        
        let sphereRedPos = float3(x: jetPos.x - 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereRed = Sphere()
        sphereRed.setPosition(sphereRedPos)
        sphereRed.setScale(1.5)
        sphereRed.setColor([1.0, 0.0, 0.0, 0.4])
        addChild(sphereRed)
        
        print("Flightbox scene children:")
        for child in children {
            print(child.getName())
        }
        
        TextureLoader.PrintCacheInfo()
        print("Total Submesh count: \(SceneManager.SubmeshCount)")
        
        entities.append(jetRigidBody)
        physicsWorld.setEntities(entities)
    }
    
    override func doUpdate() {
        super.doUpdate()
        
        let fdTime = Float(GameTime.DeltaTime)
        
        if GameTime.DeltaTime < 1.0 {
            physicsWorld.update(deltaTime: fdTime)
        }
    }
}
