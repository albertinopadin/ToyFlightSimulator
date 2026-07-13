//
//  CameraManagerCycleTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/12/26.
//

import Testing
@testable import ToyFlightSimulator

/// Exercises the pure cycle rule (`CameraManager.nextCameraIndex`) only.
/// These tests run app-hosted (like SceneManagerRegisterTests) while the
/// game's update thread owns the live CameraManager registry — mutating
/// `CurrentCamera`/`_cameras` here would hijack the running scene's camera,
/// so the stateful `CycleCamera()`/`SetCamera(at:)` wrappers are covered by
/// manual runtime verification instead.
@Suite("CameraManager cycle rule", .tags(.scenes))
struct CameraManagerCycleTests {

    @Test("Two cameras alternate (the classic Attached/Debug toggle)")
    func twoCamerasAlternate() {
        #expect(CameraManager.nextCameraIndex(after: 0, count: 2) == 1)
        #expect(CameraManager.nextCameraIndex(after: 1, count: 2) == 0)
    }

    @Test("N cameras advance in registration order and wrap")
    func nCamerasAdvanceAndWrap() {
        #expect(CameraManager.nextCameraIndex(after: 0, count: 3) == 1)
        #expect(CameraManager.nextCameraIndex(after: 1, count: 3) == 2)
        #expect(CameraManager.nextCameraIndex(after: 2, count: 3) == 0)
    }

    @Test("Fewer than two cameras is a no-op")
    func fewerThanTwoCamerasIsNoOp() {
        #expect(CameraManager.nextCameraIndex(after: 0, count: 1) == nil)
        #expect(CameraManager.nextCameraIndex(after: nil, count: 0) == nil)
    }

    @Test("No current camera is a no-op (pre-scene / mid-teardown)")
    func noCurrentCameraIsNoOp() {
        #expect(CameraManager.nextCameraIndex(after: nil, count: 3) == nil)
    }

    @Test("Out-of-range current index still lands in range (defensive modulo)")
    func outOfRangeCurrentWrapsIntoRange() {
        // Unreachable through the public API (firstIndex is always < count);
        // pins the defensive behavior of the raw rule.
        #expect(CameraManager.nextCameraIndex(after: 5, count: 3) == 0)
    }
}
