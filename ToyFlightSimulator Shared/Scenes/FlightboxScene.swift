//
//  FlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/4/22.
//

class FlightboxScene: Scene {
    var attachedCamera = AttachedCamera()
    
    var f16: F16!
    var f18: F18!
    var sun = Sun(meshType: .Sphere)
    var quad = Quad()
    
    var paused: Bool = false
    var _pPressed: Bool = false
    
    override func buildScene() {
//        f16 = F16(camera: attachedCamera)
//        addCamera(attachedCamera)
//        f16.setPositionZ(4)
//        f16.setPositionY(10)
//        addChild(f16)
        
        f18 = F18(camera: attachedCamera)
        addCamera(attachedCamera)
        f18.setPositionZ(4)
        f18.setPositionY(10)
//        f18.setScale(0.5)
        addChild(f18)
        
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
        
        sun.setPosition(1, 25, 5)
        sun.setLightBrightness(1.0)
//        sun.setLightBrightness(0.2)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        addLight(sun)
        
        var groundMaterial = Material()
        groundMaterial.color = float4(0.3, 0.7, 0.1, 1.0)
        let ground = Quad()
        ground.useMaterial(groundMaterial)
        ground.rotateX(Float(90).toRadians)
        ground.setScale(float3(100, 100, 100))
        addChild(ground)
        
        var quadMaterial = Material()
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
        
//        let jetPos = f16.getPosition()
        let jetPos = f18.getPosition()
        
        var sphereBlueMaterial = Material()
        sphereBlueMaterial.color = float4(0.0, 0.0, 1.0, 0.4)
        
        let sphereBluePos = float3(x: jetPos.x + 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereBlue = Sphere()
        sphereBlue.setPosition(sphereBluePos)
        sphereBlue.setScale(1.5)
        sphereBlue.useMaterial(sphereBlueMaterial)
        addChild(sphereBlue)
        
        var sphereRedMaterial = Material()
        sphereRedMaterial.color = float4(1.0, 0.0, 0.0, 0.4)
        
        let sphereRedPos = float3(x: jetPos.x - 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereRed = Sphere()
        sphereRed.setPosition(sphereRedPos)
        sphereRed.setScale(1.5)
        sphereRed.useMaterial(sphereRedMaterial)
        addChild(sphereRed)
        
        
        let testQuad = Quad()
        var testQuadMaterial = Material()
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
        
        var testCubeMaterial = Material()
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
    }
    
    override func doUpdate() {
        super.doUpdate()
        
            InputManager.HasDiscreteCommandDebounced(command: .Pause) {
            paused.toggle()
        }
        
        if !paused {
            quad.rotateZ(GameTime.DeltaTime)
//            f16.rotateZ(GameTime.DeltaTime)
        }
    }
}


