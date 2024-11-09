//
//  BallPhysicsScene.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 10/26/24.
//

import AppKit

let colors: [NSColor] = [
    .blue,
    .black,
    .brown,
    .cyan,
    .darkGray,
    .gray,
    .green,
    .highlightColor,
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
    static let ballCount: Int = 25
    let debugCamera = DebugCamera()
    var physicsWorld: PhysicsWorld!
    
    let spheres: [Sphere] = {
        var sphrs = [Sphere]()
        for i in 0..<BallPhysicsScene.ballCount {
            let pos = float3(x: .random(in: -10...10),
                             y: .random(in: 1...10),
                             z: .random(in: -10...0))
            
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
            
            let sp = Sphere()
            sp.radius = 1.0
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
        let ground = Quad()
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
        
//        physicsWorld = PhysicsWorld(entities: spheres, updateType: .NaiveEuler)
        physicsWorld = PhysicsWorld(entities: spheres, updateType: .HeckerVerlet)
        
        for sphere in spheres {
            self.addChild(sphere)
        }
    }
    
    override func doUpdate() {
        if GameTime.DeltaTime <= 1.0 {
            physicsWorld.update(deltaTime: Float(GameTime.DeltaTime))
        }
    }
}
