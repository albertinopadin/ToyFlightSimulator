//
//  FlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/4/22.
//

class FlightboxScene: Scene {
    var debugCamera = DebugCamera()
    
    var sun = Sun()
//    var f16 = F16()
    var quad = Quad()
    
    override func buildScene() {
//        debugCamera.setPosition(0, 0, 8)
        addCamera(debugCamera)
        
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
        
        let f16 = F16(camera: debugCamera)
        f16.setScale(2)
        f16.setPositionZ(4)
        f16.setPositionY(10)
        addChild(f16)
        
        let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
        addChild(sky)
        
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
    }
}


