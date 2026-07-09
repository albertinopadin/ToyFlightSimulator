//
//  AircraftThumbnailSpecTests.swift
//  ToyFlightSimulatorTests
//

import Foundation
import Testing
@testable import ToyFlightSimulator

@Suite("Aircraft thumbnail spec", .tags(.assetPipeline))
struct AircraftThumbnailSpecTests {

    // MARK: - Spec table completeness

    @Test("Every AircraftType has a spec whose aircraft matches and whose case name is unique")
    func specTableCoversRoster() {
        var caseNames: Set<String> = []
        for aircraft in AircraftType.allCases {
            let spec = AircraftThumbnailSpec.spec(for: aircraft)
            #expect(spec.aircraft == aircraft)
            #expect(!spec.modelName.isEmpty)
            caseNames.insert(spec.caseName)
        }
        #expect(caseNames.count == AircraftType.allCases.count)
    }

    // MARK: - Camera framing math

    @Test("Camera distance matches d = r / sin(min half-FOV) * margin for the default config")
    func cameraDistanceGoldenValue() {
        var config = ThumbnailCameraConfig()
        config.verticalFovDegrees = 30
        config.framingMargin = 1.08
        config.pixelWidth = 1280
        config.pixelHeight = 800

        // Landscape frame: vertical half-FOV (15°) is the limiting one.
        let expected = (1.0 / sin(Float(15).toRadians)) * 1.08
        #expect(approxEqual(config.cameraDistance(boundingRadius: 1), expected, tolerance: 1e-3))
    }

    @Test("Camera distance is linear in bounding radius and finite")
    func cameraDistanceScalesLinearly() {
        let config = ThumbnailCameraConfig()
        let d1 = config.cameraDistance(boundingRadius: 1)
        let d2 = config.cameraDistance(boundingRadius: 2)
        #expect(d1.isFinite && d1 > 0)
        #expect(approxEqual(d2, d1 * 2, tolerance: 1e-3))
    }

    @Test("Portrait aspect makes the horizontal half-FOV the limiting one")
    func cameraDistanceUsesMinHalfFov() {
        var landscape = ThumbnailCameraConfig()
        landscape.pixelWidth = 1280
        landscape.pixelHeight = 800

        var portrait = landscape
        portrait.pixelWidth = 800
        portrait.pixelHeight = 1280

        // Portrait's horizontal half-FOV is narrower than the vertical one,
        // so the camera must back off farther for the same sphere.
        #expect(portrait.cameraDistance(boundingRadius: 1) > landscape.cameraDistance(boundingRadius: 1))
    }

    // MARK: - Cache keys

    @Test("Cache key is stable across repeated computation")
    func cacheKeyIsStable() {
        let spec = AircraftThumbnailSpec.spec(for: .f16)
        let config = ThumbnailCameraConfig()
        #expect(spec.cacheKey(config: config) == spec.cacheKey(config: config))
    }

    @Test("Cache keys differ between aircraft")
    func cacheKeyDiffersPerAircraft() {
        let config = ThumbnailCameraConfig()
        let keys = AircraftType.allCases.map {
            AircraftThumbnailSpec.spec(for: $0).cacheKey(config: config)
        }
        #expect(Set(keys).count == keys.count)
    }

    @Test("Cache key changes when pose or output-size constants change")
    func cacheKeyTracksConfig() {
        let spec = AircraftThumbnailSpec.spec(for: .f35)
        let base = ThumbnailCameraConfig()

        var heading = base
        heading.headingDegrees = -30
        #expect(spec.cacheKey(config: heading) != spec.cacheKey(config: base))

        var size = base
        size.pixelWidth = 640
        size.pixelHeight = 400
        #expect(spec.cacheKey(config: size) != spec.cacheKey(config: base))
    }
}
