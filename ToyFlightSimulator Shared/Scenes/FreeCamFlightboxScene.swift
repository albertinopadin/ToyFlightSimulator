//
//  FreeCamFlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/23.
//

class FreeCamFlightboxScene: GameScene {
    var camera = DebugCamera()
    var jet = F22(shouldUpdate: false)
    var sun = Sun(meshType: .Sphere)
    var ground = Quad()
    var sidewinderMissile = Sidewinder()
    var aim120 = AIM120()
    
    override func buildScene() {
        sun.setPosition(1, 25, 5)
        sun.setLightColor(1, 1, 1)
        addLight(sun)
        
        print("Sun light type: \(sun.lightType)")
        
        if _rendererType == .OrderIndependentTransparency {
            let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
            addChild(sky)
        } else {
            let sky = SkyBox(skyBoxTextureType: .SkyMap)
            addChild(sky)
        }
        
        var groundMaterial = ShaderMaterial()
        groundMaterial.color = [0.3, 0.7, 0.1, 1.0]
        ground.useMaterial(groundMaterial)
        ground.rotateX(Float(90).toRadians)
        ground.setScale([100, 100, 100])
        addChild(ground)
        
//        camera.setPosition(4, 12, 20)
        camera.setPosition(12, 14, 5)
//        camera.setRotationX(Float(15).toRadians)
        camera.setRotationY(Float(75).toRadians)
        addCamera(camera)
        
//        f18.setScale(0.25)  // TODO: setScale doesn't work
        jet.setPosition(0, 10, 0)
        
        jet.setScale(0.125)
        addChild(jet)
        
        sidewinderMissile.setScale(4.0)
        sidewinderMissile.setPosition(0, 2, -12)
        let sidewinderSubmeshMetadata = sidewinderMissile.getSubmeshVertexMetadata()
        let newOrigin = float3(0, 0, sidewinderSubmeshMetadata.maxZ / 2)
        sidewinderMissile.setSubmeshOrigin(newOrigin)
        sidewinderMissile.rotateY(Float(90).toRadians)
        addChild(sidewinderMissile)
        
        aim120.setScale(4.0)
        aim120.setPosition(0, 4, -24)
        aim120.rotateY(Float(90).toRadians)
        addChild(aim120)
        
        print("TextureLoader.StringToTextureCache.count: \(TextureLoader.StringToTextureCache.count)")
        print("TextureLoader.UrlToTextureCache.count: \(TextureLoader.UrlToTextureCache.count)")
        print("TextureLoader.MdlToTextureCache.count: \(TextureLoader.MdlToTextureCache.count)")
    }
    
    override func doUpdate() {
        super.doUpdate()
        
        sidewinderMissile.rotateY(GameTime.DeltaTime)
        aim120.rotateY(GameTime.DeltaTime)
    }
}
