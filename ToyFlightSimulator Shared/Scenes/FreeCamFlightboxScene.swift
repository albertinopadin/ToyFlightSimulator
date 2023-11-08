//
//  FreeCamFlightboxScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/29/23.
//

class FreeCamFlightboxScene: GameScene {
    var camera = DebugCamera()
//    var jet = F18()
    var jet = F35()
//    var jet = F18Usdz()
    var sun = Sun(meshType: .Sphere)
    var ground = Quad()
    var sidewinderMissile = Sidewinder()
    var aim120 = AIM120()
    
    override func buildScene() {
        sun.setPosition(1, 25, 5)
//        sun.setPosition(-50, 14, 50)
        sun.setLightColor(WHITE_COLOR.xyz)
        addLight(sun)
        
//        print("Sun light type: \(sun.type)")
        
        if _rendererType == .OrderIndependentTransparency {
            let sky = SkySphere(skySphereTextureType: .Clouds_Skysphere)
            addChild(sky)
        } else {
            let sky = SkyBox(skyBoxTextureType: .SkyMap)
            addChild(sky)
        }
        
        var groundMaterial = Material()
        groundMaterial.color = float4(0.3, 0.7, 0.1, 1.0)
        ground.useMaterial(groundMaterial)
        ground.rotateX(Float(90).toRadians)
        ground.setScale(float3(100, 100, 100))
        addChild(ground)
        
//        camera.setPosition(4, 12, 20)
//        camera.setPosition(12, 14, 5)
//        camera.setPosition(12, 14, 5)
        camera.setPosition(-12, 14, 7)
//        camera.setRotationX(Float(15).toRadians)
//        camera.setRotationY(Float(75).toRadians)
        camera.setRotationY(Float(-75).toRadians)
        addCamera(camera)
        
//        f18.setScale(0.25)  // TODO: setScale doesn't work
        jet.setPosition(0, 10, 0)
//        jet.setScale(0.025)
        addChild(jet)
        
        // TODO: Other lights don't work:
//        let sLight = LightObject(name: "sLight", type: .Directional, meshType: .Sphere)
//        sLight.setLightColor(WHITE_COLOR.xyz)
//        sLight.setLightBrightness(100)
//        sLight.setPosition(-5, 14, 0)
//        addLight(sLight)
        
//        let rudderLineAxis = jet.leftRudderControlSurfaceRotationAxis
//        let rudderOrigin = jet.leftRudder.getPosition() + jet.getPosition() + float3(-0.2, 0, 0)
//        let rudderLine = Line(startPoint: rudderOrigin, endPoint: rudderLineAxis * 100, color: RED_COLOR)
//        addChild(rudderLine)
        
        let ball = Sphere()
        var ballMaterial = Material()
        ballMaterial.color = BLUE_COLOR
        ball.useMaterial(ballMaterial)
        ball.setScale(0.5)
        ball.setPosition(jet.getPosition())
        addChild(ball)
        
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
    }
    
    override func doUpdate() {
        super.doUpdate()
        
        sidewinderMissile.rotateY(GameTime.DeltaTime)
        aim120.rotateY(GameTime.DeltaTime)
    }
}
