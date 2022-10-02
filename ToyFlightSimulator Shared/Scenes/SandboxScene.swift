//
//  SandboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

class SandboxScene: Scene {
    var debugCamera = DebugCamera()
    
    var sun = Sun()
    var f16 = F16()
    
    override func buildScene() {
        debugCamera.setPosition(0, 0, 8)
        addCamera(debugCamera)
        
        sun.setPosition(0, 5, 5)
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        addLight(sun)
        
        f16.setScale(2)
        addChild(f16)
        
        let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
        addChild(sky)
        
        print("Sandbox scene children:")
        for child in children {
            print(child.getName())
        }
    }
    
    override func doUpdate() {
        if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
            f16.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
            f16.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
        }
    }
}

