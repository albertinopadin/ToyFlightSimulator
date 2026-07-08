//
//  SceneManagerRegisterTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/7/26.
//

import Testing
@testable import ToyFlightSimulator

/// `SceneManager.Register` must ignore `.none` objects entirely: no collection
/// membership, no `registeredObjectType` marker. The regression this guards:
/// the persistent AttachedCamera is reparented onto each new player aircraft
/// during an aircraft swap, so it re-enters `registerChildObject`'s subtree
/// recursion having already been registered once — with a marker, that tripped
/// the double-register assertion (its stale `.none` marker was never cleared,
/// because a plain Node reparent doesn't unregister).
///
/// Cameras declare `.none`, so nothing here touches SceneManager's live
/// batched collections — safe to run inside the app-hosted suite while the
/// game's update thread is running.
@Suite("SceneManager Register — unmanaged (.none) objects", .tags(.scenes))
struct SceneManagerRegisterTests {

    private func makeCamera(named name: String) -> Camera {
        Camera(name: name, cameraType: .Attached, aspectRatio: 1.0)
    }

    @Test("Register leaves no marker on a .none object")
    func registerLeavesNoMarker() {
        let camera = makeCamera(named: "TestCamera")
        SceneManager.Register(camera)
        #expect(camera.registeredObjectType == nil)
    }

    @Test("Registering a .none object twice is a no-op, not a double-register")
    func reRegisterIsNoOp() {
        let camera = makeCamera(named: "TwiceCamera")
        SceneManager.Register(camera)
        // Before the isManagedBySceneManager guard this hit the
        // double-register assertionFailure.
        SceneManager.Register(camera)
        #expect(camera.registeredObjectType == nil)
    }

    @Test("Aircraft-swap flow: attached camera reparented and re-registered")
    func attachedCameraSurvivesAircraftSwap() {
        // The production sequence from FlightboxWithPhysics.applyAircraftSwap:
        // attach(to:) detaches from the old aircraft (plain Node reparent — no
        // unregistration) and parents onto the new one; the new aircraft's
        // subtree is then registered, hitting the camera a second time.
        let camera = AttachedCamera()
        let aircraftA = Node(name: "AircraftA")
        let aircraftB = Node(name: "AircraftB")

        camera.attach(to: aircraftA)
        SceneManager.Register(camera)   // first swap: subtree registration

        camera.attach(to: aircraftB)    // second swap: detach + reparent
        SceneManager.Register(camera)   // re-registration under new aircraft

        #expect(camera.registeredObjectType == nil)
        #expect(camera.parent?.getID() == aircraftB.getID())
        #expect(aircraftA.children.isEmpty)
        #expect(aircraftB.children.count == 1)
    }

    @Test("Unregister on a .none object is a symmetric no-op")
    func unregisterIsNoOp() {
        let camera = makeCamera(named: "UnregisterCamera")
        SceneManager.Register(camera)
        SceneManager.Unregister(camera)
        #expect(camera.registeredObjectType == nil)
    }
}
