//
//  FlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/4/22.
//

class FlightboxScene: Scene {
    var f16Camera = F16Camera()
    
    var f16: F16!
    var sun = Sun()
    var quad = Quad()
    
    var paused: Bool = false
    
    override func buildScene() {
        f16 = F16(camera: f16Camera)
        addCamera(f16Camera)
        f16.setScale(2)
        f16.setPositionZ(4)
        f16.setPositionY(10)
        addChild(f16)
        
        sun.setPosition(0, 5, 5)
        sun.setLightBrightness(1.0)
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
        
//        let debugLine = DebugLine(name: "Red Line",
//                                  startPoint: float3(0, 0, 0),
//                                  endPoint: float3(0, 50, 0),
//                                  color: float4(1, 0, 0, 1))
//        addChild(debugLine)
        
        let debugLine = Line(startPoint: float3(0, 0, 0),
                             endPoint: float3(0, 50, 0),
                             color: float4(1, 0, 0, 1))
        addChild(debugLine)
        
        
        let f16Pos = f16.getPosition()
        
//        let debugSphereBluePos = float3(x: f16Pos.x + 1, y: f16Pos.y, z: f16Pos.z - 2)
//        let debugSphereBlue = DebugSphere(name: "Blue Sphere",
//                                          position: debugSphereBluePos,
//                                          radius: 1.0,
//                                          color: float4(0, 0, 1, 0.5))
//        addChild(debugSphereBlue)
//        
//        let debugSphereRedPos = float3(x: f16Pos.x - 1, y: f16Pos.y, z: f16Pos.z - 2)
//        let debugSphereRed = DebugSphere(name: "Red Sphere",
//                                         position: debugSphereRedPos,
//                                         radius: 1.0,
//                                         color: float4(1, 0, 0, 0.4))
//        addChild(debugSphereRed)

//        let debugSphereBluePos = float3(x: f16Pos.x + 1, y: f16Pos.y, z: f16Pos.z - 2)
//        let debugSphereBlue = DebugSphere(name: "Blue Sphere",
//                                          position: debugSphereBluePos,
//                                          radius: 1.0,
//                                          color: float4(0, 0, 1, 0.5))
//        addChild(debugSphereBlue)
        
        
        var sphereBlueMaterial = Material()
        sphereBlueMaterial.color = float4(0.0, 0.0, 1.0, 0.4)
        
        let sphereBluePos = float3(x: f16Pos.x + 1, y: f16Pos.y, z: f16Pos.z - 2)
        let sphereBlue = Sphere()
        sphereBlue.setPosition(sphereBluePos)
        sphereBlue.setScale(1.5)
        sphereBlue.useMaterial(sphereBlueMaterial)
        addChild(sphereBlue)
        
        var sphereRedMaterial = Material()
        sphereRedMaterial.color = float4(1.0, 0.0, 0.0, 0.4)
        
        let sphereRedPos = float3(x: f16Pos.x - 1, y: f16Pos.y, z: f16Pos.z - 2)
        let sphereRed = Sphere()
        sphereRed.setPosition(sphereRedPos)
        sphereRed.setScale(1.5)
        sphereRed.useMaterial(sphereRedMaterial)
        addChild(sphereRed)
        
        
        let testQuad = Quad()
        var testQuadMaterial = Material()
        testQuadMaterial.isLit = true
//        testQuadMaterial.color = RED_COLOR
        testQuadMaterial.color = float4(1, 0, 0, 0.5)
        testQuadMaterial.shininess = 100000
        testQuadMaterial.diffuse = float3(1, 0.1, 0.1)
        testQuadMaterial.specular = float3(1, 1, 1)
        testQuadMaterial.useNormalMapTexture = false
        testQuad.useMaterial(testQuadMaterial)
//        testQuad.transparent = true
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
        testCube.setPosition(f16Pos.x, 1, f16Pos.z - 4)
        addChild(testCube)
        
//        let testQuad2 = Quad()
//        testQuad2.useMaterial(testCubeMaterial)
//        testQuad2.setPosition(f16Pos.x, 1, f16Pos.z - 8)
//        addChild(testQuad2)
        
        let testTri = Triangle()
//        testTri.useMaterial(testCubeMaterial)
        testTri.setPosition(f16Pos.x, 1, f16Pos.z - 12)
        addChild(testTri)
        
        let testQuad2 = Quad()
        testQuad2.useMaterial(testCubeMaterial)
        testQuad2.setPosition(f16Pos.x, 1, f16Pos.z - 8)
        addChild(testQuad2)
        
//        let testCube = Cube()
//        testCube.useMaterial(testCubeMaterial)
//        testCube.setPosition(f16Pos.x, 1, f16Pos.z - 4)
//        addChild(testCube)
        
        let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
        addChild(sky)
        
        print("Flightbox scene children:")
        for child in children {
            print(child.getName())
        }
    }
    
    override func doUpdate() {
//        if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
//            f16.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
//            f16.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
//        }
        
        if Keyboard.IsKeyPressed(.p) {
            paused.toggle()
        }
        
        if !paused {
            quad.rotateZ(GameTime.DeltaTime)
//            f16.rotateZ(GameTime.DeltaTime)
        }
    }
}


