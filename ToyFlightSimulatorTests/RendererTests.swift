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
}
