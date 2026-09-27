//
//  CockpitModelTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import simd
@testable import ToyFlightSimulator

/// The F-22 cockpit asset as the engine imports it (Milestone 1 of
/// plans/claude/f22_cockpit_first_person_view_2026-09-25.md). App-hosted: loading a USD model
/// needs the Metal device and the app bundle's resources. Nothing here touches Engine.renderer.
@Suite("F-22 cockpit model", .tags(.assetPipeline))
struct CockpitModelTests {
    /// The rig from the asset's `bc_controls.py`, as `MDLSkeleton.jointPaths` prints it.
    static let rigJointPaths: Set<String> = [
        "CockpitRoot",
        "CockpitRoot/StickRoll",
        "CockpitRoot/StickRoll/StickPitch",
        "CockpitRoot/ThrottleLeft",
        "CockpitRoot/ThrottleRight",
        "CockpitRoot/GearHandle",
        "CockpitRoot/PedalLeft",
        "CockpitRoot/PedalRight",
    ]

    @Test("the registered model carries the rig: one skeleton, eight joints, six skinned meshes")
    func skeletonHasTheRigJoints() throws {
        // Read-only use of the shared library instance the scene draws.
        let model = try #require(Assets.Models[.F22_Cockpit] as? UsdModel)
        #expect(model.skeletons.count == 1)
        let skeleton = try #require(model.skeletons.values.first)
        #expect(skeleton.jointPaths.count == 8)
        #expect(Set(skeleton.jointPaths) == Self.rigJointPaths)
        // Stick, both throttles, the gear handle and both pedals.
        #expect(model.meshes.filter { $0.skin != nil }.count == 6)
    }

    @Test("the rest-pose joint palette is the identity for every skinned mesh")
    func restPosePaletteIsIdentity() throws {
        // A fresh instance, not Assets.Models[.F22_Cockpit]: the scene shares that one, and an
        // animator driving the controls would rewrite its palettes.
        let model = UsdModel("F22_Cockpit", fileExtension: .USDZ, basisTransform: Transform.transformXZYToXYZ)
        let skeleton = try #require(model.skeletons.values.first)
        // The rig ships no animation clip, so only Skeleton.init's rest-pose evaluation fills
        // currentPose. Before dd36871 it stayed empty and Skin.updatePalette crashed indexing it.
        #expect(skeleton.currentPose.count == 8)

        let skins = model.meshes.compactMap(\.skin)
        #expect(skins.count == 6)
        for skin in skins {
            // Each joint's composed rest transform equals its bind transform, so
            // world rest × inverse bind = I, and conjugating I by the basis leaves I.
            let palette = skin.jointMatrixPaletteBuffer.contents()
                .bindMemory(to: float4x4.self, capacity: skin.jointPaths.count)
            for jointIndex in 0..<skin.jointPaths.count {
                #expect(approxEqual(palette[jointIndex], matrix_identity_float4x4),
                        "joint \(skin.jointPaths[jointIndex])")
            }
        }
    }
}
