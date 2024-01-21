//
//  FlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/4/22.
//

class FlightboxScene: GameScene {
    var attachedCamera = AttachedCamera()
    var sun = Sun(meshType: .Sphere)
    var quad = Quad()
    var capsule = CapsuleObject()
    
    override func buildScene() {
//        let jet = F16(camera: attachedCamera)
        let jet = F18(scale: 1.0)
//        let jet = F18Usdz(camera: attachedCamera, scale: 1.0)
//        let jet = F35(camera: attachedCamera, scale: 0.1)
//        let jet = F35(camera: attachedCamera, scale: 1.0)
//        let jet = F22(scale: 0.125)
        
        addCamera(attachedCamera)
        
        let container = ContainerNode(camera: attachedCamera, cameraOffset: float3(0, 8, 18))
        container.addChild(jet)
        container.setPositionZ(4)
        container.setPositionY(10)
        addChild(container)
        
        capsule.setPosition(-8, 10, -10)
        capsule.rotateZ(Float(90).toRadians)
        addChild(capsule)
        
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
            let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
            addChild(sky)
        } else {
            let sky = SkyBox(skyBoxTextureType: .SkyMap)
            addChild(sky)
        }
        
        sun.setPosition(1, 50, 5)
        sun.setLightBrightness(1.0)
//        sun.setLightBrightness(0.2)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        addLight(sun)
        
        let pl = PointLightObject()
        pl.setPosition(capsule.getPositionX(), 0, capsule.getPositionZ())
        pl.setLightColor(BLUE_COLOR.xyz)
        pl.setLightBrightness(1.0)
//        pl.setLightRadius(10.0)
        pl.setScale(2.0)
        addLight(pl)
        
//        let pl2 = PointLightObject()
//        pl2.setPosition(-capsule.getPositionX(), 0.5, capsule.getPositionZ())
//        pl2.setLightColor(RED_COLOR.xyz)
//        pl2.setLightBrightness(1.0)
//        addLight(pl2)
        
        let f16 = F16(shouldUpdate: false)
        f16.setPosition(0, jet.getPositionY() + 10, jet.getPositionZ() - 15)
        f16.rotateY(Float(-90).toRadians)
        f16.setScale(4.0)
        addChild(f16)
        
        var icoMaterial = ShaderMaterial()
        icoMaterial.color = RED_COLOR
        
        let ico = Icosahedron()
        ico.setPosition(-capsule.getPositionX(), 0.5, capsule.getPositionZ())
        ico.setScale(2.0)
        ico.useMaterial(icoMaterial)
        addChild(ico)
        
        var sphereGreenMaterial = ShaderMaterial()
        sphereGreenMaterial.color = float4(0.0, 1.0, 0.2, 1.0)
        
        let sphereGreen = Sphere()
        sphereGreen.setPosition(pl.getPositionX() + 2.0, pl.getPositionY(), pl.getPositionZ())
        sphereGreen.setScale(1.0)
        sphereGreen.useMaterial(sphereGreenMaterial)
        addChild(sphereGreen)
        
//        var sphereBluishMaterial = ShaderMaterial()
//        sphereBluishMaterial.color = float4(0.0, 0.2, 1.0, 1.0)
//        
//        let bluishSphere = Sphere()
//        bluishSphere.setPosition(float3.zero)
//        bluishSphere.setScale(1.0)
//        bluishSphere.useMaterial(sphereBluishMaterial)
//        addChild(bluishSphere)
        
        
        var groundMaterial = ShaderMaterial()
        groundMaterial.color = float4(0.3, 0.7, 0.1, 1.0)
        let ground = Quad()
        ground.useMaterial(groundMaterial)
        ground.rotateX(Float(90).toRadians)
        ground.setScale(float3(100, 100, 100))
        addChild(ground)
        
        var quadMaterial = ShaderMaterial()
        quadMaterial.color = float4(0, 0.4, 1.0, 1.0)
        quadMaterial.shininess = 10
        quad.useMaterial(quadMaterial)
        quad.setPositionZ(1)
        quad.setPositionY(14)
        addChild(quad)
        
        let debugLine = Line(startPoint: float3(0, 0, 0),
                             endPoint: float3(0, 50, 0),
                             color: float4(1, 0, 0, 1))
        addChild(debugLine)
        
        let jetPos = jet.getPosition()
        
        var sphereBlueMaterial = ShaderMaterial()
        sphereBlueMaterial.color = float4(0.0, 0.0, 1.0, 0.4)
        
        let sphereBluePos = float3(x: jetPos.x + 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereBlue = Sphere()
        sphereBlue.setPosition(sphereBluePos)
        sphereBlue.setScale(1.5)
        sphereBlue.useMaterial(sphereBlueMaterial)
        addChild(sphereBlue)
        
        var sphereRedMaterial = ShaderMaterial()
        sphereRedMaterial.color = float4(1.0, 0.0, 0.0, 0.4)
        
        let sphereRedPos = float3(x: jetPos.x - 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereRed = Sphere()
        sphereRed.setPosition(sphereRedPos)
        sphereRed.setScale(1.5)
        sphereRed.useMaterial(sphereRedMaterial)
        addChild(sphereRed)
        
        
        let testQuad = Quad()
        var testQuadMaterial = ShaderMaterial()
        testQuadMaterial.isLit = true
        testQuadMaterial.color = float4(1, 0, 0, 0.5)
        testQuadMaterial.shininess = 100000
        testQuadMaterial.diffuse = float3(1, 0.1, 0.1)
        testQuadMaterial.specular = float3(1, 1, 1)
        testQuadMaterial.useNormalMapTexture = false
        testQuad.useMaterial(testQuadMaterial)
        testQuad.setPositionZ(1)
        testQuad.setPositionY(10)
        testQuad.setPositionX(5)
        addChild(testQuad)
        
        var testCubeMaterial = ShaderMaterial()
        testCubeMaterial.isLit = true
        testCubeMaterial.color = GRABBER_BLUE_COLOR
        testCubeMaterial.diffuse = float3(0.1,0.4,1)
        testCubeMaterial.specular = float3(1,1,10)
        testCubeMaterial.useNormalMapTexture = false
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
        
        print("Material.StringToTextureCache.count: \(Material.StringToTextureCache.count)")
        print("Material.UrlToTextureCache.count: \(Material.UrlToTextureCache.count)")
        print("Material.MdlToTextureCache.count: \(Material.MdlToTextureCache.count)")
    }
    
    override func doUpdate() {
        super.doUpdate()
        
//        InputManager.HasDiscreteCommandDebounced(command: .Pause) {
//            paused.toggle()
//        }
        
        quad.rotateZ(GameTime.DeltaTime)
    }
}


