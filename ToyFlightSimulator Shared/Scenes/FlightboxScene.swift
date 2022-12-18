//
//  FlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/4/22.
//

class FlightboxScene: Scene {
    var f16Camera = F16Camera()
    
    var sun = Sun()
    var f16: F16!
    var quad = Quad()
    
    var paused: Bool = false
    
    override func buildScene() {
        f16 = F16(camera: f16Camera)
        
        addCamera(f16Camera)
        
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
        
        var material = Material()
        material.color = float4(0, 0.4, 1.0, 1.0)
        material.shininess = 10
        quad.useMaterial(material)
        quad.setPositionZ(1)
        quad.setPositionY(10)
        addChild(quad)
        
        f16.setScale(2)
        f16.setPositionZ(4)
        f16.setPositionY(10)
        addChild(f16)
        
        let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
        addChild(sky)
        
        let debugLine = DebugLine(name: "Red Line",
                                  startPoint: float3(0, 0, 0),
                                  endPoint: float3(0, 50, 0),
                                  color: float4(1, 0, 0, 1))
        addChild(debugLine)
        
//        let debugSphere = DebugSphere(name: "Red Sphere",
//                                      position: f16.getPosition(),
//                                      radius: 1.0,
//                                      color: float4(1, 0, 0, 0.5))
        
//        let debugSphere = DebugSphere(name: "Blue Sphere",
//                                      position: f16.getPosition(),
//                                      radius: 1.0,
//                                      color: float4(0, 0, 1, 0.5))
        
//        addChild(debugSphere)
        
        print("Sandbox scene children:")
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


