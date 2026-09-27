//
//  CockpitGeometryTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

/// Where the cockpit model's points land in the aircraft body frame (Milestone 1 of
/// plans/claude/f22_cockpit_first_person_view_2026-09-25.md). Pure math, no Metal: the
/// helper is static and the basis is a constant. Numbers reproduced with the scratch
/// script `cockpit_test_numbers.swift`.
@Suite("Cockpit placement in the body frame", .tags(.gameObjects, .math))
struct CockpitGeometryTests {
    /// The stick pivot in the cockpit file's native frame (meters; +X right, +Y forward,
    /// +Z up, origin = design eye point), from the asset's `bc_controls.py`.
    static let stickPivotNative: float3 = [0.3635, 0.2330, -0.5810]

    @Test("the stick pivot lands on the right console of the Sketchfab F-22")
    func stickPivotLandsOnRightConsole() {
        let stickPivotInBody = Aircraft.cockpitNativeToBody(nativePoint: Self.stickPivotNative,
                                                            eyePointInBodyFrame: [0, 1.12, 7.00])
        // (x, y, z) -> (x, z, y), then + eye point: 0.54 m below and 0.23 m ahead of the eye.
        #expect(approxEqual(stickPivotInBody, [0.3635, 0.5390, 7.2330]))
        #expect(stickPivotInBody.x > 0)  // right side: the reflecting basis kept the handedness
    }

    @Test("the same pivot in the CGTrader F-22, whose eye point differs")
    func stickPivotInTheCGTraderF22() {
        let stickPivotInBody = Aircraft.cockpitNativeToBody(nativePoint: Self.stickPivotNative,
                                                            eyePointInBodyFrame: [0, 1.08, 5.50])
        #expect(approxEqual(stickPivotInBody, [0.3635, 0.4990, 5.7330]))
    }

    @Test("the helper's axis swap is the registered import basis (row-vector v · B)",
          arguments: [
            CockpitGeometryTests.stickPivotNative,
            float3(-0.3951, 0.1190, -0.7710),  // left throttle pivot
            float3(-0.3605, 0.4140, -0.5621),  // gear handle pivot
            float3(0.160, 0.960, -0.790),      // right pedal pivot
            float3(1, 2, 3),
          ])
    func helperMatchesTheImportBasis(nativePoint: float3) {
        // ModelLibrary bakes the basis into the vertices as v_engine = v_native · B.
        let bakedPoint = simd_mul(SIMD4<Float>(nativePoint, 1), Transform.transformXZYToXYZ)
        let helperPoint = Aircraft.cockpitNativeToBody(nativePoint: nativePoint, eyePointInBodyFrame: .zero)
        #expect(approxEqual(helperPoint, bakedPoint.xyz))
    }

    @Test("the cockpit basis is a reflection (determinant −1)")
    func basisIsAReflection() {
        // A reflection is what keeps the throttles left and the stick right when Blender's
        // right-handed axes become the engine's left-handed ones; det −1 also makes
        // Mesh.reverseTriangleWinding keep the faces front-facing.
        let basis = Transform.transformXZYToXYZ
        let basisRotationPart = float3x3(basis.columns.0.xyz, basis.columns.1.xyz, basis.columns.2.xyz)
        #expect(approxEqual(basisRotationPart.determinant, -1))
    }
}
