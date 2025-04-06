//
//  BallPhysicsScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

#if os(macOS)
import AppKit
typealias TFSColor = NSColor
#else
import UIKit
typealias TFSColor = UIColor
#endif

let colors: [TFSColor] = [
    .blue,
    .black,
    .brown,
    .cyan,
    .darkGray,
    .gray,
    .green,
    .lightGray,
    .magenta,
    .orange,
    .purple,
    .red,
    .systemRed,
    .systemBlue,
    .systemPink,
    .systemTeal,
    .systemGreen,
    .systemCyan,
    .systemMint,
    .systemIndigo,
    .systemYellow,
    .white,
    .yellow
]

class BallPhysicsScene: GameScene {
    static let ballCount: Int = 27
    var ground: CollidablePlane!
    let debugCamera = DebugCamera()
    var physicsWorld: PhysicsWorld!
    
    let spheres: [CollidableSphere] = {
        var sphrs = [CollidableSphere]()
        for i in 0..<BallPhysicsScene.ballCount {
            let pos = float3(x: .random(in: -7...7),
                             y: .random(in: 1...10),
                             z: .random(in: -7...0))
            
            let color: float4
            let randColor = colors.randomElement()!.cgColor
            if randColor.colorSpace?.model != .monochrome,
               let colorComponents = randColor.components {
                color = float4(x: Float(colorComponents[0]),
                               y: Float(colorComponents[1]),
                               z: Float(colorComponents[2]),
                               w: Float(colorComponents[3]))
            } else {
                color = GRABBER_BLUE_COLOR
            }
            
            let sphereRadiusScale: Float = 0.4
            let sp = CollidableSphere()
            sp.collisionRadius = sphereRadiusScale
            sp.collisionShape = .Sphere
            sp.isStatic = false
            sp.setScale(sphereRadiusScale)
            sp.mass = 1.0
            sp.restitution = 0.9
            sp.setPosition(pos)
            sp.setColor(color)
            sphrs.append(sp)
        }
        return sphrs
    }()
    
    private func addGround() {
        let groundColor = float4(0.3, 0.7, 0.1, 1.0)
        ground = CollidablePlane()
        ground.collisionNormal = [0, 1, 0]
        ground.collisionShape = .Plane
        ground.restitution = 1.0
        ground.isStatic = true
        ground.setColor(groundColor)
        ground.rotateZ(Float(270).toRadians)
        ground.setScale(1000)
        addChild(ground)
    }
    
    private func addSun() {
        let sun = Sun()
        sun.isStatic = true
        sun.setPosition(0, 100, 4)
        sun.setLightBrightness(1.0)
        sun.setLightColor(1, 1, 1)
        sun.setLightAmbientIntensity(0.04)
        sun.setLightDiffuseIntensity(0.15)
        addLight(sun)
    }
    
    override func buildScene() {
        addGround()
        addSun()
        
        debugCamera.setPosition([0, 5, 15])
        addCamera(debugCamera)
        
        let entities: [PhysicsEntity] = spheres + [ground]
//        physicsWorld = PhysicsWorld(entities: entities, updateType: .NaiveEuler)
        physicsWorld = PhysicsWorld(entities: entities, updateType: .HeckerVerlet)
        
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
