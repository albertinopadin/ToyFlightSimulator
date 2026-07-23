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
    /// Free-fly camera, slot 1 in the 'C' cycle (chase camera is slot 0).
    /// Unparented, so CameraManager.Update drives it.
    let debugCamera = DebugCamera()
    var sun = Sun(modelType: .Sphere)

//    let physicsWorld = PhysicsWorld(updateType: .NaiveEuler)
    let physicsWorld = PhysicsWorld(updateType: .HeckerVerlet)
    var entities: [RigidBody] = []

    private let groundSize: Int = 1_000_000

    private let aircraftStartPosition: float3 = [0, 100, 0]

    /// Aircraft swap requested from the UI thread, applied on the update thread
    /// at the top of `doUpdate`. Keeps the scene-graph / physics mutation off
    /// the main thread — see `PendingAircraftSwap`.
    private let pendingSwap = PendingAircraftSwap()

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
        
        // Default. Applied immediately (not deferred): buildScene runs before
        // the update loop spins, and there's no aircraft to render until it does.
        // Entity install is skipped: buildScene keeps appending rigid bodies
        // below and installs the full list once via setEntities at the end.
        applyAircraftSwap(.f22_cgtrader, installEntities: false)
        
        let jetPos = aircraftStartPosition

        // Cycle target; the chase camera stays the default view. Registered
        // AFTER the chase camera (which buildScene registers via
        // applyAircraftSwap → addCamera) so cycle order is chase → free. +Z is
        // forward, so the -Z offset spawns it behind the jet looking at it.
        debugCamera.setPosition(jetPos + float3(0, 5, -40))
        addCamera(debugCamera, false)

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
        f16.rotateY(Float(90).toRadians)
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
        
        physicsWorld.setEntities(entities)
    }

    /// Called from the SwiftUI menu on the main thread. Does NOT mutate the
    /// scene graph or physics world here — those are owned by the UpdateThread.
    /// The request is recorded and applied on the update thread in `doUpdate`.
    override func setPlayerAircraft(_ aircraft: AircraftType) {
        pendingSwap.request(aircraft)
    }

    /// Performs the actual aircraft swap. Runs on the update thread (via
    /// `doUpdate`) or during scene construction (via `buildScene`) — never
    /// directly from the UI callback.
    ///
    /// `installEntities` controls whether the updated entity list is pushed to
    /// the physics world here. Runtime swaps need that (the default) so the new
    /// rigid body joins the next physics step; `buildScene` passes `false`
    /// because it keeps appending entities afterward and installs the complete
    /// list once at the end.
    private func applyAircraftSwap(_ aircraft: AircraftType, installEntities: Bool = true) {
        let prevAc: Aircraft? = playerAircraft
        let prevAcRigidBody: RigidBody? = playerAircraft?.rigidBody

        // Models are meterized at import (1 unit = 1 m), so aircraft use scale 1.0.
        switch aircraft {
            case .f16:
                playerAircraft = F16()
            case .f18:
                playerAircraft = F18()
            case .f22:
                playerAircraft = getPlayerAcF22()
            case .f22_cgtrader:
                playerAircraft = getPlayerAcCGTraderF22()
            case .f35:
                playerAircraft = F35()
        }

        if let playerAircraft {
            let acRigidBody = SphereRigidBody(gameObject: playerAircraft)
            acRigidBody.collisionRadius = 2.0
            acRigidBody.restitution = 0.2

            entities = Self.swappedEntities(entities, removing: prevAcRigidBody, adding: acRigidBody)
            if installEntities {
                physicsWorld.setEntities(entities)
            }

            addCamera(attachedCamera)
            attachedCamera.attach(to: playerAircraft, offset: playerAircraft.cameraOffset)
            playerAircraft.setPosition(aircraftStartPosition)

            if let prevAc {
                SceneManager.RemoveObject(prevAc)
            }

            addChild(playerAircraft)
        }
    }

    /// Entity-list bookkeeping for an aircraft swap: drops the previous
    /// aircraft's rigid body (if present) and appends the new one. Removing
    /// before appending guarantees the physics world is never left with two
    /// aircraft bodies, even across repeated swaps. Pure and `static` so it's
    /// unit-testable without constructing a (Metal-backed) scene.
    static func swappedEntities(_ entities: [RigidBody],
                                removing prev: RigidBody?,
                                adding new: RigidBody) -> [RigidBody] {
        var updated = entities
        if let prev {
            updated.removeAll { $0 === prev }
        }
        updated.append(new)
        return updated
    }

    private func getPlayerAcF22() -> F22 {
        let ac = F22()
        ac.flightModel = F22SimpleFlightModel()
        return ac
    }

    private func getPlayerAcCGTraderF22() -> F22_CGTrader {
        let ac = F22_CGTrader()
        ac.flightModel = F22SimpleFlightModel()
        return ac
    }
    
    override func doUpdate() {
        super.doUpdate()

        // Apply any UI-requested aircraft swap here, on the update thread,
        // before stepping physics so the new rigid body is part of this step.
        if let pending = pendingSwap.take() {
            applyAircraftSwap(pending)
        }

        let fdTime = Float(GameTime.DeltaTime)

        if GameTime.DeltaTime < 1.0 {
            physicsWorld.update(deltaTime: fdTime)
        }
    }
}
