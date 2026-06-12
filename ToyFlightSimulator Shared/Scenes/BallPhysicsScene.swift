//
//  BallPhysicsScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

final class BallPhysicsScene: GameScene {
    static let ballCount: Int = 500
    var ground: Quad!
    var groundRigidBody: PlaneRigidBody!
    let debugCamera = DebugCamera()
    var physicsWorld: PhysicsWorld!
    
    let spheres: [Sphere] = {
        var sphrs = [Sphere]()
        for i in 0..<BallPhysicsScene.ballCount {
            let pos = float3(x: .random(in: -7...7),
                             y: .random(in: 1...10),
                             z: .random(in: -7...0))
            
            let color = randomPaletteColor(fallback: GRABBER_BLUE_COLOR)

            let sphereRadiusScale: Float = 0.4
            let sphere = Sphere()
            sphere.setScale(sphereRadiusScale)
            sphere.setColor(color)
            sphere.setPosition(pos)
            
            let rigidBody = SphereRigidBody(gameObject: sphere, collisionRadius: sphereRadiusScale)
            rigidBody.isStatic = false
            rigidBody.mass = 1.0
            rigidBody.restitution = 0.9
            
            sphrs.append(sphere)
        }
        return sphrs
    }()
    
    private func addSun() {
        let sun = Sun()
        sun.setPosition(0, 100, 4)
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        sun.setLightDiffuseIntensity(0.15)
        addLight(sun)
    }
    
    override func buildScene() {
        (ground, groundRigidBody) = addGround()
        addSun()

        debugCamera.setPosition([0, 5, -20])
        addCamera(debugCamera)

        let entities: [RigidBody] = spheres.map { $0.rigidBody! } + [groundRigidBody]
//        physicsWorld = PhysicsWorld(entities: entities, updateType: .NaiveEuler)
        physicsWorld = PhysicsWorld(entities: entities, updateType: .HeckerVerlet)
        physicsWorld.useBroadPhase = true
        
        for sphere in spheres {
            self.addChild(sphere)
        }
    }
    
    var counter: UInt64 = 0
    var accum: UInt64 = 0
    
    override func doUpdate() {
        if GameTime.DeltaTime <= 1.0 {
//            physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
            
            let time = timeit {
                physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
            }
            
            accum += time
            
            if counter % 120 == 0 {
                let avg = Double(accum) / Double(120) * 1e-9
                accum = 0
                print("[BallPhysiscsScene doUpdate] time: \(avg)")
            }
            
            counter += 1
        }
    }
}
