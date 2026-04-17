//
//  FlightboxWithPhysics.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/16/26.
//

final class FlightboxWithPhysics: GameScene {
    var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                        near: 0.01,
                                        far: 1000000.0)
    var sun = Sun(modelType: .Sphere)
    
    let physicsWorld = PhysicsWorld(updateType: .NaiveEuler)
    var entities: [PhysicsEntity] = []
    
    private func addGround() {
        let groundColor = float4(0.3, 0.7, 0.1, 1.0)
        let ground = CollidablePlane()
        ground.collisionNormal = [0, 1, 0]
        ground.collisionShape = .Plane
        ground.restitution = 1.0
        ground.isStatic = true
        ground.setColor(groundColor)
        ground.rotateZ(Float(90).toRadians)
        ground.setScale(1000)
        addChild(ground)
        
        entities.append(ground)
    }
    
    override func buildScene() {
        addGround()
        
        let jet = CollidableF22(scale: 0.25)
        
        addCamera(attachedCamera)
        attachedCamera.attach(to: jet, offset: jet.cameraOffset)
        jet.setPosition(0, 100, 0)
        addChild(jet)
        let jetPos = jet.getPosition()
        
        switch _rendererType {
            case .OrderIndependentTransparency:
                let sky = SkySphere(textureType: .Clouds_Skysphere)
                addChild(sky)
            case .SinglePassDeferredLighting:
                let sky = SkyBox(textureType: .SkyMap)
                addChild(sky)
            default:
                print("No sky")
        }
        
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
        
        entities.append(jet)
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
