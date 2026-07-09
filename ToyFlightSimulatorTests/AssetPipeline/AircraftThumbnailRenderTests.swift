//
//  AircraftThumbnailRenderTests.swift
//  ToyFlightSimulatorTests
//
//  End-to-end smoke test of the SceneKit thumbnail path: renders every
//  aircraft offscreen inside the app host (Bundle.main = the app, so model
//  resources resolve) and writes the PNGs through the real cache code path.
//  Requires a Metal device; skipped where none exists.
//

import Foundation
import Metal
import Testing
@testable import ToyFlightSimulator

@Suite("Aircraft thumbnail rendering",
       .tags(.assetPipeline),
       .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct AircraftThumbnailRenderTests {

    @Test("Every aircraft renders to a correctly sized PNG through the cache path",
          .timeLimit(.minutes(1)))
    func rendersAllAircraft() throws {
        let config = ThumbnailCameraConfig()
        for aircraft in AircraftType.allCases {
            let spec = AircraftThumbnailSpec.spec(for: aircraft)
            let image = try AircraftThumbnailGenerator.render(spec: spec, config: config)
            #expect(image.width == config.pixelWidth,
                    "unexpected width for \(spec.caseName)")
            #expect(image.height == config.pixelHeight,
                    "unexpected height for \(spec.caseName)")

            let key = spec.cacheKey(config: config)
            AircraftThumbnailCache.store(image, caseName: spec.caseName, key: key)
            #expect(AircraftThumbnailCache.load(caseName: spec.caseName, key: key) != nil,
                    "PNG round-trip failed for \(spec.caseName)")
            if let url = AircraftThumbnailCache.fileURL(caseName: spec.caseName, key: key) {
                print("[AircraftThumbnailRenderTests] wrote \(url.path)")
            }
        }
    }
}
