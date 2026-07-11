//
//  RendererTests.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/14/25.
//

import XCTest
@testable import ToyFlightSimulator

final class RendererTests: XCTestCase {
    func testSuccessfulInit() {
        let renderer = Renderer(type: .TiledDeferredMSAA)
        XCTAssertNotNil(renderer)
    }
    
    func testRendererTypeAssignment() {
        let tiledMsaaRenderer = Renderer(type: .TiledDeferredMSAA)
        XCTAssertEqual(tiledMsaaRenderer.rendererType, .TiledDeferredMSAA)

        let forwardRenderer = Renderer(type: .ForwardPlusTileShading)
        XCTAssertEqual(forwardRenderer.rendererType, .ForwardPlusTileShading)
        
        let oitRenderer = Renderer(type: .OrderIndependentTransparency)
        XCTAssertEqual(oitRenderer.rendererType, .OrderIndependentTransparency)

        let spdlRenderer = Renderer(type: .SinglePassDeferredLighting)
        XCTAssertEqual(spdlRenderer.rendererType, .SinglePassDeferredLighting)
        
        let tiledDeferredRenderer = Renderer(type: .TiledDeferred)
        XCTAssertEqual(tiledDeferredRenderer.rendererType, .TiledDeferred)
    }
    
    func testScreenSizeAndAspectRatio() {
        let renderer = Renderer(type: .TiledDeferredMSAA)
        let testSize = CGSize(width: 800, height: 600)

        renderer.updateScreenSize(size: testSize)

        XCTAssertEqual(Renderer.ScreenSize.x, Float(testSize.width))
        XCTAssertEqual(Renderer.ScreenSize.y, Float(testSize.height))
        XCTAssertEqual(Renderer.AspectRatio, Float(testSize.width) / Float(testSize.height))
    }
    
    func testInvalidScreenSizes() {
        let renderer = Renderer(type: .TiledDeferredMSAA)

        // Save original screen size
        let originalSize = Renderer.ScreenSize

        // Test with invalid sizes
        renderer.updateScreenSize(size: CGSize(width: -100, height: 100))
        XCTAssertEqual(Renderer.ScreenSize, originalSize)

        renderer.updateScreenSize(size: CGSize(width: 0, height: 0))
        XCTAssertEqual(Renderer.ScreenSize, originalSize)

        renderer.updateScreenSize(size: CGSize(width: CGFloat.nan, height: CGFloat.nan))
        XCTAssertEqual(Renderer.ScreenSize, originalSize)
    }
    
    func testUpdateSemaphoreSignaling() {
        // `xcodebuild test` hosts this bundle inside ToyFlightSimulator.app —
        // its MTKView is already running a full render loop. Driving
        // `renderer.render {}` on a second, MTKView-less Renderer from
        // parallel test workers competes with the host's CAMetalLayer
        // drawable acquisition and can deadlock the dispatch system
        // (XCTWaiter never wakes), which is why this test used to hang
        // locally in parallel mode. The contract we care about — that the
        // renderer's `updateSemaphore` is the wake-up channel reachable
        // through the property — is testable without invoking the draw
        // pipeline. Works identically headless (GitHub macos-26) and on a
        // local machine with a display.
        let renderer = Renderer(type: .TiledDeferredMSAA)
        let semaphore = DispatchSemaphore(value: 0)
        renderer.updateSemaphore = semaphore

        // Signaling through the property must wake a waiter on the
        // underlying DispatchSemaphore (proves the reference, not a copy,
        // is stored).
        renderer.updateSemaphore?.signal()
        XCTAssertEqual(semaphore.wait(timeout: .now() + 0.5), .success,
                       "renderer.updateSemaphore should be a reference to the assigned semaphore")

        // Reassignment swaps the channel without leaking the previous one.
        let replacement = DispatchSemaphore(value: 0)
        renderer.updateSemaphore = replacement
        renderer.updateSemaphore?.signal()
        XCTAssertEqual(replacement.wait(timeout: .now() + 0.5), .success)
        XCTAssertEqual(semaphore.wait(timeout: .now() + 0.05), .timedOut,
                       "old semaphore should no longer be signaled after reassignment")

        // Clearing detaches the channel entirely.
        renderer.updateSemaphore = nil
        XCTAssertNil(renderer.updateSemaphore)
    }

    func testInitRendererReturnsWiredRenderer() {
        // Regression: the runtime renderer-switch paths (MacMetalViewWrapper.
        // updateNSView / IOSMetalViewWrapper.updateUIView) install
        // Engine.InitRenderer's result directly as Engine.renderer. If the
        // factory returned an unwired renderer, render() would silently skip
        // the update handshake (nil-chained semaphores) and the simulation
        // would freeze after a live renderer switch.
        // .ForwardPlusTileShading: its init is a bare super.init(type:) —
        // no offscreen allocations (TiledDeferred's init allocates a
        // ~268 MB 4096²×4 shadow texture array).
        let renderer = Engine.InitRenderer(type: .ForwardPlusTileShading)
        XCTAssertNotNil(renderer.updateSemaphore)
        XCTAssertNotNil(renderer.updateDoneSemaphore)

        // Every factory result must share the ONE UpdateThread's channels —
        // that's what keeps a runtime-switched renderer driving the same
        // update loop as the renderer it replaced. Cross-instance identity
        // proves it without depending on host-app launch timing
        // (Engine.renderer may not be installed yet when this suite runs).
        // The NotNil asserts above keep nil === nil from passing vacuously.
        // Never signal these here: they are the live update thread's channels.
        let second = Engine.InitRenderer(type: .OrderIndependentTransparency)
        XCTAssertTrue(renderer.updateSemaphore === second.updateSemaphore)
        XCTAssertTrue(renderer.updateDoneSemaphore === second.updateDoneSemaphore)
    }
}
