//
//  SandboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

class SandboxScene: Scene {
    var debugCamera = DebugCamera()
    
    var sun = Sun()
//    var quad = Quad()
    
    override func buildScene() {
        debugCamera.setPosition(0, 0, 0)
        addCamera(debugCamera)
        
        sun.setPosition(0, 5, 5)
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        addLight(sun)
        
        let quad1 = createQuad(color: float4(0, 0, 1.0, 1.0), position: float3(0, 0, 5))
        let quad2 = createQuad(color: float4(0, 1.0, 0, 1.0), position: float3(5, 0, 0))
        quad2.rotateY(Float(90).toRadians)
        let quad3 = createQuad(color: float4(1, 0, 0, 1.0), position: float3(-5, 0, 0))
        quad3.rotateY(Float(90).toRadians)
        let quad4 = createQuad(color: float4(0, 0.2, 0.8, 1.0), position: float3(0, 0, -5))
        
        addChild(quad1)
        addChild(quad2)
        addChild(quad3)
        addChild(quad4)
        
        print("Sandbox scene children:")
        for child in children {
            print(child.getName())
        }
    }
    
    func createQuad(color: float4, position: float3) -> Quad {
        var material = Material()
        material.color = color
        material.shininess = 100
        material.specular = float3(10, 10, 10)
        material.diffuse = float3(10, 10, 10)
        let quad = Quad()
        quad.useMaterial(material)
        quad.setPosition(position)
        return quad
    }
    
    override func doUpdate() {
//        if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
//            quad.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
//            quad.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
//        }
    }
}

