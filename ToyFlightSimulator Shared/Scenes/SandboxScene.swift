//
//  SandboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/27/22.
//

class SandboxScene: GameScene {
    var debugCamera = DebugCamera()
    var f16Camera = AttachedCamera()
    var sun = Sun()
//    var quad = Quad()
    var quad1 = Quad()
    var quad2 = Quad()
    var quad3 = Quad()
    var quad4 = Quad()
    
    override func buildScene() {
//        debugCamera.setPosition(0, 0, 0)
//        addCamera(debugCamera)
        
        addCamera(f16Camera)
        
        sun.setPosition(0, 5, 5)
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        addLight(sun)
        
        quad1 = createQuad(color: BLUE_COLOR, position: float3(0, 0, 5))
        quad2 = createQuad(color: GREEN_COLOR, position: float3(5, 0, 0))
        quad2.rotateY(Float(90).toRadians)
        quad3 = createQuad(color: RED_COLOR, position: float3(-5, 0, 0))
        quad3.rotateY(Float(90).toRadians)
        quad4 = createQuad(color: float4(0, 0.2, 0.8, 1.0), position: float3(0, 0, -5))
        let quad5 = createQuad(color: RED_COLOR, position: float3(1, 1, -4))
        quad4.addChild(quad5)
        quad4.addChild(f16Camera)
        f16Camera.setPosition(0, 0, 5)
        
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
        var material = ShaderMaterial()
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
        super.doUpdate()
        
//        if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
//            for quad in [quad1, quad2, quad3, quad4] {
//                quad.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
//                quad.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
//            }
//        }
        
        quad4.rotateY(GameTime.DeltaTime)
        
        // TODO: Odd behavior, can only rotate one quad at a time (???)
        if (Mouse.IsMouseButtonPressed(button: .LEFT)) {
//            quad1.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
//            quad1.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
//
//            quad2.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
//            quad2.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
//
//            quad3.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
//            quad3.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
            
            quad4.rotateX(Mouse.GetDY() * GameTime.DeltaTime)
            quad4.rotateY(Mouse.GetDX() * GameTime.DeltaTime)
        }
        
        if Keyboard.IsKeyPressed(.q) {
            quad4.rotateY(GameTime.DeltaTime * 4)
        }
        
        if Keyboard.IsKeyPressed(.e) {
            quad4.rotateY(-GameTime.DeltaTime * 4)
        }
        
        if Keyboard.IsKeyPressed(.a) {
            quad4.moveX(-GameTime.DeltaTime * 4)
        }
        
        if Keyboard.IsKeyPressed(.d) {
            quad4.moveX(GameTime.DeltaTime * 4)
        }
        
        if Keyboard.IsKeyPressed(.w) {
            quad4.moveZ(-GameTime.DeltaTime * 4)
        }
        
        if Keyboard.IsKeyPressed(.s) {
            quad4.moveZ(GameTime.DeltaTime * 4)
        }
    }
}

