//
//  F22SubmeshFilterTests.swift
//  ToyFlightSimulatorTests
//

import Testing
@testable import ToyFlightSimulator

/// The Sketchfab F-22 hides its own crude interior and HUD glass once the cockpit model is in
/// (Milestone 3 of plans/claude/f22_cockpit_first_person_view_2026-09-25.md).
@Suite("F-22 exterior submesh filter", .tags(.gameObjects))
struct F22SubmeshFilterTests {
    @Test("hides the interior and HUD glass only when a cockpit is present",
          arguments: ["f22a_cockpit", "HudGlass"])
    func hidesInteriorOnlyWhenCockpitPresent(materialName: String) {
        #expect(!F22.shouldRenderExteriorSubmesh(materialName: materialName, hasCockpit: true))
        #expect(F22.shouldRenderExteriorSubmesh(materialName: materialName, hasCockpit: false))
    }

    @Test("keeps the airframe, the canopy and the landing lights",
          arguments: ["f22a_airframe", "Glass", "f22a_landingLights"])
    func keepsTheExterior(materialName: String) {
        #expect(F22.shouldRenderExteriorSubmesh(materialName: materialName, hasCockpit: true))
    }

    @Test("a submesh without a material is kept")
    func keepsASubmeshWithoutAMaterial() {
        #expect(F22.shouldRenderExteriorSubmesh(materialName: nil, hasCockpit: true))
    }

    /// App-hosted (loads the Sketchfab model, so it needs Metal). Guards the names: if the asset
    /// or Model I/O ever renamed these materials, the filter would silently hide nothing.
    @Test("the Sketchfab model's submeshes carry the hidden names and the canopy")
    func sketchfabModelHasTheReplacedMaterials() {
        let model = Assets.Models[.Sketchfab_F22]
        let materialNames = Set(model.meshes.flatMap { mesh in
            mesh.submeshes.compactMap { $0.material?.name }
        })
        #expect(F22.materialsReplacedByCockpit.isSubset(of: materialNames))
        #expect(materialNames.contains("Glass"))
    }
}
