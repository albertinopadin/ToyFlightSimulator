//
//  FlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/4/22.
//

class FlightboxScene: GameScene {
    var attachedCamera = AttachedCamera(fieldOfView: 60.0,
                                        near: 0.01,
                                        far: 1000000.0)
    var sun = Sun(modelType: .Sphere)
    var quad = Quad()
    var capsule = CapsuleObject()
    
    var pl2 = PointLightObject()
    let afterburner = Afterburner(name: "Afterburner")
    
    private func addGround() {
        var groundMaterial = MaterialProperties()
        let groundColor = float4(0.3, 0.7, 0.1, 1.0)
        groundMaterial.setColor(groundColor)
        let ground = Quad()
        ground.useMaterial(groundMaterial)
        ground.rotateZ(Float(270).toRadians)
        ground.setScale(1000)
        addChild(ground)
    }
    
    override func buildScene() {
        addGround()
        
//        let jet = F16(scale: 6.0)
//        let jet = F18()
//        let jet = F18Usdz()
//        let jet = F35(scale: 0.8)
        let jet = F22(scale: 0.125)
//        let jet = Temple(scale: 0.02)
        
        addCamera(attachedCamera)
        
        let container = ContainerNode(camera: attachedCamera, cameraOffset: jet.cameraOffset)
        container.addChild(jet)
        container.setPositionZ(4)
        container.setPositionY(10)
        addChild(container)
        
        capsule.setPosition(-8, 10, -10)
        capsule.rotateZ(Float(90).toRadians)
        addChild(capsule)
        
//        let fire = Fire(name: "Fire")
//        fire.setPosition(8, 1, -10)
//        addChild(fire)
        
//        let f16Sphere = Sphere()
//        var f16SphereMaterial = Material()
//        f16SphereMaterial.color = GRABBER_BLUE_COLOR
//        f16SphereMaterial.diffuse = float3(1,1,1)
//        f16SphereMaterial.specular = float3(1,1,1)
//        f16Sphere.useMaterial(f16SphereMaterial)
//        f16Sphere.setPosition(1.5, 0, 0)
//        f16Sphere.setScale(0.5)
//        f16.addChild(f16Sphere)
        
        if _rendererType == .OrderIndependentTransparency {
            let sky = SkySphere(textureType: .Clouds_Skysphere)
            addChild(sky)
        } else {
            let sky = SkyBox(textureType: .SkyMap)
            addChild(sky)
        }
        
        // TODO: Why does position with z = 0 result in much darker lighting ???
        sun.setPosition(0, 100, 4)
        sun.setLightBrightness(1.0)
//        sun.setLightBrightness(0.2)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
//        sun.setLightDiffuseIntensity(0.15)
        sun.setLightDiffuseIntensity(0)
        addLight(sun)
        
        var sunBallMat = MaterialProperties()
        sunBallMat.setColor(RED_COLOR)
        
        let sunBall = Sphere()
        sunBall.useMaterial(sunBallMat)
        sunBall.setPosition(sun.getPosition())
        addChild(sunBall)
        
        if _rendererType == .TiledDeferred {
            let pl = PointLightObject()
            pl.setPosition(capsule.getPositionX(), 0.5, capsule.getPositionZ())
            pl.setLightColor(BLUE_COLOR.xyz)
            pl.setLightBrightness(1.0)
            //        pl.setLightRadius(10.0)
            pl.setScale(2.0)
            addLight(pl)
            
            //        pl2.setPosition(-capsule.getPositionX(), capsule.getPositionY(), capsule.getPositionZ())
            pl2.setPosition(-capsule.getPositionX(), 0.5, capsule.getPositionZ())
            pl2.setLightColor(RED_COLOR.xyz)
            pl2.setLightBrightness(1.0)
            pl2.setScale(3.0)
            addLight(pl2)
        }
        
        let f16 = F16(shouldUpdate: false)
        f16.setPosition(0, container.getPositionY() + 10, container.getPositionZ() - 15)
        f16.rotateY(Float(-90).toRadians)
        f16.setScale(4.0)
        addChild(f16)
        
//        var icoMaterial = ShaderMaterial()
//        icoMaterial.setColor(BLUE_COLOR)
//        
//        let ico = Icosahedron()
//        ico.setPosition(-capsule.getPositionX(), 0.5, capsule.getPositionZ())
//        ico.setScale(2.0)
//        ico.useMaterial(icoMaterial)
//        addChild(ico)
        
//        var sphereGreenMaterial = ShaderMaterial()
//        sphereGreenMaterial.color = float4(0.0, 1.0, 0.2, 1.0)
        
//        let sphereGreen = Sphere()
//        sphereGreen.setPosition(pl.getPositionX() + 2.0, pl.getPositionY(), pl.getPositionZ())
//        sphereGreen.setScale(1.0)
//        sphereGreen.useMaterial(sphereGreenMaterial)
//        addChild(sphereGreen)
        
//        var sphereBluishMaterial = ShaderMaterial()
//        sphereBluishMaterial.color = float4(0.0, 0.2, 1.0, 1.0)
//        
//        let bluishSphere = Sphere()
//        bluishSphere.setPosition(float3.zero)
//        bluishSphere.setScale(1.0)
//        bluishSphere.useMaterial(sphereBluishMaterial)
//        addChild(bluishSphere)
        
//        addGround()
        
        var quadMaterial = MaterialProperties()
        quadMaterial.setColor([0, 0.4, 1.0, 1.0])
        quadMaterial.shininess = 10
        quad.useMaterial(quadMaterial)
        quad.setPositionZ(1)
        quad.setPositionY(14)
        addChild(quad)
        
        let debugLine = Line(startPoint: [0, 0, 0],
                             endPoint: [0, 50, 0],
                             color: [1, 0, 0, 1])
        addChild(debugLine)
        
        let jetPos = container.getPosition()
        
        var sphereBlueMaterial = MaterialProperties()
        sphereBlueMaterial.setColor(float4(0.0, 0.0, 1.0, 0.4))
        
        let sphereBluePos = float3(x: jetPos.x + 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereBlue = Sphere()
        sphereBlue.setPosition(sphereBluePos)
        sphereBlue.setScale(1.5)
        sphereBlue.useMaterial(sphereBlueMaterial)
        addChild(sphereBlue)
        
        var sphereRedMaterial = MaterialProperties()
        sphereRedMaterial.setColor([1.0, 0.0, 0.0, 0.4])
        
        let sphereRedPos = float3(x: jetPos.x - 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereRed = Sphere()
        sphereRed.setPosition(sphereRedPos)
        sphereRed.setScale(1.5)
        sphereRed.useMaterial(sphereRedMaterial)
        addChild(sphereRed)
        
        
        let testQuad = Quad()
        var testQuadMaterial = MaterialProperties()
        testQuadMaterial.isLit = true
        testQuadMaterial.setColor([1, 0, 0, 0.5])
        testQuadMaterial.shininess = 100000
        testQuadMaterial.diffuse = [1, 0.1, 0.1]
        testQuadMaterial.specular = [1, 1, 1]
        testQuad.useMaterial(testQuadMaterial)
        testQuad.setPositionZ(1)
        testQuad.setPositionY(10)
        testQuad.setPositionX(5)
        addChild(testQuad)
        
        var testCubeMaterial = MaterialProperties()
        testCubeMaterial.isLit = true
        testCubeMaterial.setColor(GRABBER_BLUE_COLOR)
        testCubeMaterial.diffuse = [0.1, 0.4, 1]
        testCubeMaterial.specular = [1, 1, 10]
        testCubeMaterial.shininess = 100
        
        let testCube = Cube()
        testCube.useMaterial(testCubeMaterial)
        testCube.setPosition(jetPos.x, 1, jetPos.z - 4)
        addChild(testCube)
        
//        let testQuad2 = Quad()
//        testQuad2.useMaterial(testCubeMaterial)
//        testQuad2.setPosition(f16Pos.x, 1, f16Pos.z - 8)
//        addChild(testQuad2)
        
        let testTri = Triangle()
//        testTri.useMaterial(testCubeMaterial)
        testTri.setPosition(jetPos.x, 1, jetPos.z - 12)
        addChild(testTri)
        
        let testQuad2 = Quad()
        testQuad2.useMaterial(testCubeMaterial)
        testQuad2.setPosition(jetPos.x, 1, jetPos.z - 8)
        addChild(testQuad2)
        
//        let testCube = Cube()
//        testCube.useMaterial(testCubeMaterial)
//        testCube.setPosition(f16Pos.x, 1, f16Pos.z - 4)
//        addChild(testCube)
        
        print("Flightbox scene children:")
        for child in children {
            print(child.getName())
        }
        
        TextureLoader.PrintCacheInfo()
        print("Total Submesh count: \(DrawManager.SubmeshCount)")
    }
    
    override func doUpdate() {
        super.doUpdate()
        
//        InputManager.HasDiscreteCommandDebounced(command: .Pause) {
//            paused.toggle()
//        }
        
        let fdTime = Float(GameTime.DeltaTime)
        
        quad.rotateZ(fdTime)
        
        let ftTime = Float(GameTime.TotalGameTime)
        pl2.moveX(cos(ftTime * 5))
        pl2.moveZ(sin(ftTime * 5))
        
//        InputManager.handleMouseClickDebounced(command: .ClickSelect) {
//            print("Mouse position in window: \(Mouse.GetMouseWindowPosition())")
//            print("Mouse position in viewport: \(Mouse.GetMouseViewportPosition())")
//        }
    }
}


