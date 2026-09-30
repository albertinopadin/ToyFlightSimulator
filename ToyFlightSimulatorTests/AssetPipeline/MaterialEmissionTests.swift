//
//  MaterialEmissionTests.swift
//  ToyFlightSimulatorTests
//

import Foundation
import Testing
import ModelIO
import simd
@testable import ToyFlightSimulator

/// Emission import (Milestone 5 of plans/claude/f22_cockpit_first_person_view_2026-09-25.md).
/// Model I/O puts two different things under `.emission`: a USD file's authored
/// `emissiveColor`, and an OBJ file's MTL `Ka` line (ambient reflectivity). Both arrive as the
/// same float3 property, so `Material` reads `.emission` for USD files only.
///
/// The first four tests are Metal-free: they write a tiny OBJ + MTL or USDA file and import it
/// with Model I/O's default allocator, and no texture is loaded. The last four are app-hosted:
/// they read the models the app registers, which needs the Metal device.
@Suite("Material emission import", .tags(.assetPipeline))
struct MaterialEmissionTests {
    /// Emission colors the cockpit asset authors for its indicator lenses, as Model I/O reads
    /// them (reproduced with the scratch probe `probe_emission.swift`).
    static let cockpitLensEmission: [String: SIMD3<Float>] = [
        "Lens_Red":   [0.8, 0.02, 0.01],
        "Lens_Amber": [0.9, 0.35, 0.02],
        "Lens_Green": [0.05, 0.6, 0.1],
    ]

    /// Cockpit materials whose emissiveColor is a texture: the six displays, the ICP and the
    /// HUD combiner's symbology.
    static let cockpitEmissionMapMaterials: [String] = [
        "Display_PMFD",
        "Display_SMFD_Left",
        "Display_SMFD_Right",
        "Display_SMFD_Lower",
        "Display_UFD_Left",
        "Display_UFD_Right",
        "Display_ICP",
        "HUD_Combiner",
    ]

    // MARK: - Metal-free

    @Test("only the USD formats read .emission")
    func readsEmissionOnlyForUSD() {
        #expect(Material.readsEmission(from: .USDZ))
        #expect(Material.readsEmission(from: .USDC))
        #expect(!Material.readsEmission(from: .OBJ))
        #expect(!Material.readsEmission(from: nil))
    }

    @Test("an OBJ material with Ka 1 1 1 keeps emission 0")
    func objKaIsNotEmission() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mdlMaterial = try Self.importFirstMaterial(named: "painted.obj",
                                                       writing: [("painted.obj", Self.triangleOBJ),
                                                                 ("painted.mtl", Self.paintedMTL)],
                                                       in: directory)

        // Guard against a vacuous pass: the importer really did put Ka under .emission.
        let emissionProperty = try #require(mdlMaterial.property(with: .emission))
        #expect(emissionProperty.type == .float3)
        #expect(approxEqual(emissionProperty.float3Value, [1, 1, 1]))

        let material = Material(mdlMaterial, parentModelType: .OBJ)
        #expect(material.properties.emissive == .zero)
        #expect(material.emissiveTexture == nil)
    }

    @Test("a USD material's constant emissiveColor is read")
    func usdEmissiveColorIsRead() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mdlMaterial = try Self.importFirstMaterial(named: "lens.usda",
                                                       writing: [("lens.usda", Self.lensUSDA(emissiveColor: "(0.8, 0.02, 0.01)"))],
                                                       in: directory)

        let material = Material(mdlMaterial, parentModelType: .USDZ)
        #expect(approxEqual(material.properties.emissive, [0.8, 0.02, 0.01]))
        #expect(material.emissiveTexture == nil)
    }

    @Test("a USD material that authors no emissiveColor keeps emission 0")
    func usdWithoutEmissiveColorKeepsZero() throws {
        let directory = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mdlMaterial = try Self.importFirstMaterial(named: "panel.usda",
                                                       writing: [("panel.usda", Self.lensUSDA(emissiveColor: nil))],
                                                       in: directory)

        // Model I/O's own default ("emission", 0 0 0) is what property(with:) returns here.
        let material = Material(mdlMaterial, parentModelType: .USDZ)
        #expect(material.properties.emissive == .zero)
    }

    // MARK: - App-hosted (the registered models)

    @Test("the cockpit's displays, ICP and HUD have an emission map",
          arguments: MaterialEmissionTests.cockpitEmissionMapMaterials)
    func cockpitDisplaysHaveEmissionMaps(materialName: String) throws {
        let material = try #require(Self.cockpitMaterials()[materialName], "no material \(materialName)")
        #expect(material.emissiveTexture != nil)
    }

    @Test("the cockpit's indicator lenses have their emission colors")
    func cockpitLensesHaveEmissionColors() throws {
        let materials = Self.cockpitMaterials()
        for (materialName, expectedEmission) in Self.cockpitLensEmission {
            let material = try #require(materials[materialName], "no material \(materialName)")
            #expect(approxEqual(material.properties.emissive, expectedEmission), "\(materialName)")
            #expect(material.emissiveTexture == nil, "\(materialName)")
        }
    }

    @Test("the rest of the cockpit gives off no light")
    func cockpitStructureGivesOffNoLight() {
        let emissiveNames = Set(Self.cockpitEmissionMapMaterials).union(Self.cockpitLensEmission.keys)
        let darkMaterials = Self.cockpitMaterials().filter { !emissiveNames.contains($0.key) }
        #expect(!darkMaterials.isEmpty)
        for (materialName, material) in darkMaterials {
            #expect(material.properties.emissive == .zero, "\(materialName)")
            #expect(material.emissiveTexture == nil, "\(materialName)")
        }
    }

    /// The F-16's MTL authors `Ka 1 1 1` for both materials (Blender's export default), which
    /// Model I/O stores under .emission. Read as emission, it would paint the jet white.
    @Test("the F-16 OBJ reads no emission although its Ka is 1 1 1")
    func f16ObjReadsNoEmission() throws {
        let model = Assets.Models[.F16]
        let sourceMaterials = model.mdlMeshes.flatMap { mdlMesh in
            (mdlMesh.submeshes as? [MDLSubmesh] ?? []).compactMap(\.material)
        }
        let sourceEmission = try #require(sourceMaterials.first?.property(with: .emission))
        #expect(approxEqual(sourceEmission.float3Value, [1, 1, 1]))

        let materials = model.meshes.flatMap { $0.submeshes.compactMap(\.material) }
        #expect(!materials.isEmpty)
        for material in materials {
            #expect(material.properties.emissive == .zero, "\(material.name)")
            #expect(material.emissiveTexture == nil, "\(material.name)")
        }
    }

    // MARK: - Helpers

    /// Every material of the registered cockpit model, by name. Read-only use of the shared
    /// instance the scene draws.
    static func cockpitMaterials() -> [String: Material] {
        let materials = Assets.Models[.F22_Cockpit].meshes.flatMap { $0.submeshes.compactMap(\.material) }
        return Dictionary(materials.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaterialEmissionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes the files, imports `fileName` with Model I/O and returns its first submesh's material.
    static func importFirstMaterial(named fileName: String,
                                    writing files: [(name: String, contents: String)],
                                    in directory: URL) throws -> MDLMaterial {
        for file in files {
            try file.contents.write(to: directory.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
        }
        let asset = MDLAsset(url: directory.appendingPathComponent(fileName))
        let mesh = try #require(asset.childObjects(of: MDLMesh.self).first as? MDLMesh)
        let submesh = try #require(mesh.submeshes?.firstObject as? MDLSubmesh)
        return try #require(submesh.material)
    }

    static let triangleOBJ = """
        mtllib painted.mtl
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vt 0 0
        vt 1 0
        vt 0 1
        vn 0 0 1
        usemtl Painted
        f 1/1/1 2/2/1 3/3/1
        """

    /// The lines Blender writes for a plain painted material, including `Ka 1 1 1`.
    static let paintedMTL = """
        newmtl Painted
        Ka 1.000000 1.000000 1.000000
        Kd 0.500000 0.500000 0.500000
        Ks 0.250000 0.250000 0.250000
        Ke 0.000000 0.000000 0.000000
        Ns 32
        d 1.0
        illum 2
        """

    /// One triangle bound to a UsdPreviewSurface, with `emissiveColor` authored as a constant
    /// (like the cockpit's lenses) or not at all.
    static func lensUSDA(emissiveColor: String?) -> String {
        let emissiveLine = emissiveColor.map { "color3f inputs:emissiveColor = \($0)" } ?? ""
        return """
            #usda 1.0
            (
                defaultPrim = "Root"
                metersPerUnit = 1
                upAxis = "Z"
            )

            def Xform "Root"
            {
                def Mesh "Lens" (
                    prepend apiSchemas = ["MaterialBindingAPI"]
                )
                {
                    int[] faceVertexCounts = [3]
                    int[] faceVertexIndices = [0, 1, 2]
                    point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
                    rel material:binding = </Root/Materials/Lens>
                }

                def Scope "Materials"
                {
                    def Material "Lens"
                    {
                        token outputs:surface.connect = </Root/Materials/Lens/Surface.outputs:surface>

                        def Shader "Surface"
                        {
                            uniform token info:id = "UsdPreviewSurface"
                            color3f inputs:diffuseColor = (0.6, 0.02, 0.01)
                            \(emissiveLine)
                            token outputs:surface
                        }
                    }
                }
            }
            """
    }
}
