//
//  FlightboxWithPhysics.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/16/26.
//

final class FlightboxWithPhysics: GameScene {
    private enum RandomShape: CaseIterable {
        case sphere, cube, capsule
    }

    private enum CapsuleAxis: CaseIterable {
        case x, z
    }

    var attachedCamera = AttachedCamera(fieldOfView: 75.0,
                                        near: 0.01,
                                        far: 1_000_000.0)
    var sun = Sun(modelType: .Sphere)

//    let physicsWorld = PhysicsWorld(updateType: .NaiveEuler)
    let physicsWorld = PhysicsWorld(updateType: .HeckerVerlet)
    var entities: [RigidBody] = []

    private let groundSize: Int = 1_000_000

    private func makeRandomDispersedObjects(count: Int, clusterRadius: Int, withRigidBodies: Bool = false) {
        let halfClusterRadius: Int = clusterRadius / 2
        for _ in 0..<count {
            let randomSize = Float.random(in: 2.0..<10.0)

            let x: Float = Float(Int.random(in: -halfClusterRadius..<halfClusterRadius))
            let y: Float = Float.random(in: randomSize..<randomSize * 2)
            let z: Float = Float(Int.random(in: -halfClusterRadius..<halfClusterRadius))

            let randomPosition: float3 = [x, y, z]
            let color = randomPaletteColor()

            switch RandomShape.allCases.randomElement()! {
                case .sphere:
                    let sphere = Sphere()
                    sphere.setScale(randomSize)
                    sphere.setPosition(randomPosition)
                    sphere.setColor(color)
                    if withRigidBodies {
                        let rb = SphereRigidBody(gameObject: sphere)
                        rb.mass = 100
                        rb.isStatic = false
                        rb.collisionRadius = randomSize
                        sphere.rigidBody = rb
                        entities.append(rb)
                    }
                    self.addChild(sphere)
                case .cube:
                    let cube = Cube()
                    cube.setScale(randomSize * 2)
                    cube.setPosition(randomPosition)
                    cube.setColor(color)
                    if withRigidBodies {
                        let rb = SphereRigidBody(gameObject: cube)
                        rb.mass = 100
                        rb.isStatic = false
                        rb.collisionRadius = randomSize
                        cube.rigidBody = rb
                        entities.append(rb)
                    }
                    self.addChild(cube)
                case .capsule:
                    let capsule = CapsuleObject()
                    switch CapsuleAxis.allCases.randomElement()! {
                        case .x:
                            capsule.rotateX(Float(90).toRadians)
                        case .z:
                            capsule.rotateZ(Float(90).toRadians)
                    }
                    capsule.setScale(randomSize)
                    capsule.setPosition(randomPosition)
                    capsule.setColor(color)
                    if withRigidBodies {
                        let rb = SphereRigidBody(gameObject: capsule)
                        rb.mass = 100
                        rb.isStatic = false
                        rb.collisionRadius = randomSize
                        capsule.rigidBody = rb
                        entities.append(rb)
                    }
                    self.addChild(capsule)
            }
        }
    }

    override func buildScene() {
        let (_, groundRigidBody) = addGround(scale: Float(groundSize))
        entities.append(groundRigidBody)

//        let jet = F22(scale: 0.25)
//        let jet = F22_CGTrader(scale: 3.0)
        let jet = F18(scale: 1.4)
        let jetRigidBody = SphereRigidBody(gameObject: jet)
        jetRigidBody.collisionRadius = 2.0
        jetRigidBody.restitution = 0.2
        let flightModel = F22SimpleFlightModel()
        jet.flightModel = flightModel

        addCamera(attachedCamera)
        attachedCamera.attach(to: jet, offset: jet.cameraOffset)
        jet.setPosition(0, 100, 0)
        addChild(jet)
        let jetPos = jet.getPosition()

        setupDefaultSky()

        sun.setPosition(0, jetPos.y + 100, 4)
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
        f16.setPosition(0, jetPos.y + 10, jetPos.z + 15)
        f16.rotateY(Float(-90).toRadians)
//        f16.setScale(4.0)
        f16.setScale(10.0)
        addChild(f16)

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

//        makeRandomDispersedObjects(count: 1_000, clusterRadius: groundSize / 100)
        makeRandomDispersedObjects(count: 100, clusterRadius: groundSize / 1000, withRigidBodies: true)

        print("Flightbox scene children:")
        for child in children {
            print(child.getName())
        }

        TextureLoader.PrintCacheInfo()
        print("Total Submesh count: \(SceneManager.SubmeshCount)")

        entities.append(jetRigidBody)
        physicsWorld.setEntities(entities)
    }

    override func doUpdate() {
        super.doUpdate()

        let fdTime = Float(GameTime.DeltaTime)

        if GameTime.DeltaTime < 1.0 {
            physicsWorld.update(deltaTime: fdTime)
        }
    }
}
