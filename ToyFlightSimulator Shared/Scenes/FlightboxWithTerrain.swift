//
//  FlightboxWithTerrain.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/28/25.
//

final class FlightboxWithTerrain: GameScene {
    var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                        near: 0.01,
                                        far: 1000000.0)
    var sun = Sun(modelType: .Sphere)
    var quad = Quad()
    var capsule = CapsuleObject()
    
    let afterburner = Afterburner(name: "Afterburner")
    
//    let physicsWorld = PhysicsWorld(updateType: .NaiveEuler)
    var entities: [PhysicsEntity] = []
    
    private func addGround() {
        let groundColor = float4(0.3, 0.7, 0.1, 1.0)
        let ground = TerrainObject(size: [8, 8])
        ground.setColor(groundColor)
        ground.rotateX(Float(-20).toRadians)
        ground.setScale(100)
        addChild(ground)
    }
    
    override func buildScene() {
        addGround()
        
//        let jet = F35(scale: 0.8)
//        let jet = F22(scale: 0.25)
        let jet = CollidableF22(scale: 0.25)
        
        // Set focus on jet to enable input handling
        jet.hasFocus = true
        
        addCamera(attachedCamera)
        
        let container = ContainerNode(camera: attachedCamera, cameraOffset: jet.cameraOffset)
        container.addChild(jet)
        container.setPositionZ(4)
        container.setPositionY(100)
        addChild(container)
        
        let jetPos = container.getPosition()
        
        capsule.setPosition(-8, jetPos.y, -10)
        capsule.rotateZ(Float(90).toRadians)
        addChild(capsule)
        
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
        sun.setLightAmbientIntensity(0.04)
//        sun.setLightDiffuseIntensity(0.15)
        sun.setLightDiffuseIntensity(0)
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
        
//        quadMaterial.shininess = 10
        quad.setColor([0, 0.4, 1.0, 1.0])
        quad.setPositionZ(1)
        quad.setPositionY(jetPos.y + 14)
        addChild(quad)
        
        let debugLine = Line(startPoint: [0, 0, 0],
                             endPoint: [0, jetPos.y + 50, 0],
                             color: [1, 0, 0, 1])
        addChild(debugLine)
        
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
//        physicsWorld.setEntities(entities)
    }
    
    override func doUpdate() {
        super.doUpdate()
        
//        InputManager.HasDiscreteCommandDebounced(command: .Pause) {
//            paused.toggle()
//        }
        
        let fdTime = Float(GameTime.DeltaTime)
        
        quad.rotateZ(fdTime)
        
//        InputManager.handleMouseClickDebounced(command: .ClickSelect) {
//            print("Mouse position in window: \(Mouse.GetMouseWindowPosition())")
//            print("Mouse position in viewport: \(Mouse.GetMouseViewportPosition())")
//        }
        
//        if GameTime.DeltaTime < 1.0 {
//            physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
//        }
    }
}


