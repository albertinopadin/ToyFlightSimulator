//
//  FlightboxWithTerrain.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/28/25.
//

final class FlightboxWithTerrain: GameScene {
    static let proceduralTerrainParams = ProceduralTerrainParameters()
    /// Which terrain this scene builds. `.heightMapImage` gives the older terrain, made from
    /// the image `mountain.png`.
    let terrainHeightSource: TerrainHeightSource = .procedural(params: proceduralTerrainParams)
    /// The terrain, set by `addTerrain`. Kept as a property so that the scene can reach it
    /// after `buildScene` (Milestone 4 of the terrain plan moves it with the aircraft).
    var ground: TerrainObject!
    
    var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                        near: 0.01,
                                        far: 1000000.0)
    var sun = Sun(modelType: .Sphere)
    var quad = Quad()
    var capsule = CapsuleObject()
    let pointLight = PointLightObject()
    
    let jet = F22()
    
    private func addTerrain(heightSource: TerrainHeightSource) {
        switch heightSource {
            case .heightMapImage:
                let groundColor = float4(0.3, 0.7, 0.1, 1.0)
                ground = TerrainObject(size: [8, 8])
                ground.setColor(groundColor)
                ground.rotateX(Float(-20).toRadians)
                ground.setScale(100)
                addChild(ground)
            case .procedural(params: let params):
                // No scale and no rotation here. The heights are already meters, so a scale
                // would multiply them, and on a tilted terrain the height is no longer a
                // function of world x and z.
                //
                // 12,800 m on a side. With 129 samples per side that is one sample every
                // 100 m, the spacing the terrain's default parameters are chosen for: the
                // narrowest of the 4 octaves has cells 400 m wide, which is 4 samples.
                ground = TerrainObject.makeProceduralTerrain(params: params, sideLength: 12_800)
                addChild(ground)
        }
    }

    override func buildScene() {
        addTerrain(heightSource: terrainHeightSource)
        
        addCamera(attachedCamera)
        attachedCamera.attach(to: jet, offset: jet.cameraOffset)
        jet.chaseCamera = attachedCamera
        
        // The height the jet starts at and the height of its flat floor, both in meters in the
        // frame this scene is built in.
        let jetHeight: Float
        let kinematicFloorHeightInOriginalFrame: Float
        switch terrainHeightSource {
            case .procedural(params: let params):
                // Procedural heights lie between -heightAmplitude and +heightAmplitude. The jet
                // starts 200 m above the highest ground there can be, and the floor is at the
                // lowest: a floor at 0 would stop the jet in mid-air above every valley.
                jetHeight = (params.heightAmplitude + 200).toFloat()
                kinematicFloorHeightInOriginalFrame = -params.heightAmplitude.toFloat()
            case .heightMapImage:
                // The floor is at the height of the terrain's centre. This terrain is tilted,
                // so the jet can pass under its high side and stops above its low side.
                jetHeight = 100
                kinematicFloorHeightInOriginalFrame = 0
        }

        jet.setPosition(0, jetHeight, 0)
        // The floor is not ground contact. The terrain is displaced on the GPU and the jet
        // knows nothing about its shape, so the jet can still fly through a hill. The floor
        // only keeps it from falling forever.
        jet.kinematicFloorHeightInOriginalFrame = kinematicFloorHeightInOriginalFrame
        addChild(jet)
        let jetPos = jet.getPosition()
        
        capsule.setPosition(-8, jetPos.y, -10)
        capsule.rotateZ(Float(90).toRadians)
        addChild(capsule)
        
        setupDefaultSky()
        
        // TODO: Why does position with z = 0 result in much darker lighting ???
        sun.setPosition(0, jetPos.y + 100, 4)
        // Explicit direction: the sun node then shifts with the floating origin like any other
        // node, so its stored position stays equal to sunBall's. The sun node itself is not
        // drawn (sunBall is its visible marker). Must come after setPosition: it reads the position.
        sun.setLightDirection(sun.getPosition())
        sun.setLightBrightness(1.0)
//        sun.setLightBrightness(0.2)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.4)
        sun.setLightDiffuseIntensity(0.5)
//        sun.setLightDiffuseIntensity(0)
        addLight(sun)
        
        let sunBall = Sphere()
        sunBall.setColor(RED_COLOR)
        sunBall.setPosition(sun.getPosition())
        addChild(sunBall)
        
        let f16 = F16(shouldUpdateOnPlayerInput: false)
        f16.setPosition(0, jetPos.y + 10, jetPos.z - 15)
        f16.rotateY(Float(-90).toRadians)
        addChild(f16)
        
//        quadMaterial.shininess = 10
        quad.setColor([0, 0.4, 1.0, 1.0])
        quad.setPositionZ(1)
        quad.setPositionY(jetPos.y + 14)
        addChild(quad)
        
        let debugLine = Line(startPoint: [0, 0, 0],
                             endPoint: [0, jetPos.y + 50, 0],
                             color: [1, 0, 0, 1])
        addChild(debugLine)
        
        let sphereBluePos = float3(x: jetPos.x + 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereBlue = Sphere()
        sphereBlue.setPosition(sphereBluePos)
        sphereBlue.setScale(1.5)
        sphereBlue.setColor([0.0, 0.0, 1.0, 0.4])
        addChild(sphereBlue)
        
        let sphereRedPos = float3(x: jetPos.x - 1, y: jetPos.y, z: jetPos.z - 2)
        let sphereRed = Sphere()
        sphereRed.setPosition(sphereRedPos)
        sphereRed.setScale(1.5)
        sphereRed.setColor([1.0, 0.0, 0.0, 0.4])
        addChild(sphereRed)
        
        pointLight.setPosition(jetPos.x, jetPos.y + 1, jetPos.z + 1)
        pointLight.setColor(RED_COLOR)
        pointLight.setLightColor(RED_COLOR.xyz)
        addLight(pointLight)
        
        print("Flightbox scene children:")
        for child in children {
            print(child.getName())
        }
        
        TextureLoader.PrintCacheInfo()
        print("Total Submesh count: \(SceneManager.SubmeshCount)")
    }
    
    override func doUpdate() {
        super.doUpdate()
        
//        InputManager.HasDiscreteCommandDebounced(command: .Pause) {
//            paused.toggle()
//        }
        
        let fdTime = Float(GameTime.DeltaTime)
        
        quad.rotateZ(fdTime)
        pointLight.setPosition(jet.getPositionX(),
                               jet.getPositionY() + (sin(Float(GameTime.TotalGameTime)) * 0.5),
                               jet.getPositionZ())
        
//        InputManager.handleMouseClickDebounced(command: .ClickSelect) {
//            print("Mouse position in window: \(Mouse.GetMouseWindowPosition())")
//            print("Mouse position in viewport: \(Mouse.GetMouseViewportPosition())")
//        }
    }
}


