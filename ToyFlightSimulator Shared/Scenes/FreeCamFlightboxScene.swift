//
//  FreeCamFlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/23.
//

class FreeCamFlightboxScene: Scene {
    var camera = DebugCamera()
    var f18 = F18()
    var sun = Sun(meshType: .Sphere)
    var ground = Quad()
    var sidewinderMissile = Sidewinder()
    
    override func buildScene() {
        sun.setPosition(1, 25, 5)
        sun.setLightColor(1, 1, 1)
        addLight(sun)
        
        print("Sun light type: \(sun.type)")
        
//        let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
        let sky = SkyBox(skyBoxTextureType: .SkyMap)
        addChild(sky)
        
        var groundMaterial = Material()
        groundMaterial.color = float4(0.3, 0.7, 0.1, 1.0)
        ground.useMaterial(groundMaterial)
        ground.rotateX(Float(90).toRadians)
        ground.setScale(float3(100, 100, 100))
        addChild(ground)
        
//        camera.setPosition(0, 15, 25)
        camera.setPosition(4, 12, 20)
        camera.setRotationX(Float(15).toRadians)
        addCamera(camera)
        
//        f18.setScale(0.25)  // TODO: setScale doesn't work
        f18.setPosition(0, 2, 0)
        addChild(f18)
        
        var swMaterial = Material()
        swMaterial.color = BLUE_COLOR
        
//        sidewinderMissile.useMaterial(swMaterial)
//        sidewinderMissile.setPosition(1, 2, 0)
//        sidewinderMissile.setScale(0.25)
        
        sidewinderMissile.setScale(4.0)
        sidewinderMissile.setPosition(0, -2, 0)
        sidewinderMissile.rotateY(Float(90).toRadians)
        addChild(sidewinderMissile)
    }
    
    override func doUpdate() {
        // ?
    }
}