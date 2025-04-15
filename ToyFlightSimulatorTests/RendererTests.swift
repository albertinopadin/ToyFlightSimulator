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
        let renderer = Renderer(type: .TiledDeferredMSAA)
        let semaphore = DispatchSemaphore(value: 0)
        renderer.updateSemaphore = semaphore

        // Create an expectation
        let expectation = XCTestExpectation(description: "Semaphore should be signaled")

        // Start a background thread to wait for the semaphore
        DispatchQueue.global().async {
            let result = semaphore.wait(timeout: .now() + 1.0)
            if result == .success {
                expectation.fulfill()
            }
        }

        // Call render which should signal the semaphore
        renderer.render {}

        // Wait for the expectation to be fulfilled
        wait(for: [expectation], timeout: 2.0)
    }
}
