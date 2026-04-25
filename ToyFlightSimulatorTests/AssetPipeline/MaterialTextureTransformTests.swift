//
//  MaterialTextureTransformTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import ModelIO
import simd
@testable import ToyFlightSimulator

@Suite("Material texture UV transforms", .tags(.assetPipeline))
struct MaterialTextureTransformTests {

    // MARK: - MaterialTextureTransforms default

    @Test("MaterialTextureTransforms() defaults to all-identity and hasTextureTransforms == false")
    func defaultsAreIdentity() {
        let t = MaterialTextureTransforms()
        #expect(approxEqual(t.baseColorUVTransform, matrix_identity_float3x3))
        #expect(approxEqual(t.normalUVTransform,    matrix_identity_float3x3))
        #expect(approxEqual(t.specularUVTransform,  matrix_identity_float3x3))
        #expect(approxEqual(t.opacityUVTransform,   matrix_identity_float3x3))
        #expect(t.hasTextureTransforms == false)
    }

    @Test("Material from an empty MDLMaterial has identity texture transforms")
    func materialFromEmptyMDLMaterialIsIdentity() {
        let mdlMaterial = MDLMaterial(name: "empty", scatteringFunction: MDLScatteringFunction())
        let m = Material(mdlMaterial)

        #expect(approxEqual(m.textureTransforms.baseColorUVTransform, matrix_identity_float3x3))
        #expect(approxEqual(m.textureTransforms.normalUVTransform,    matrix_identity_float3x3))
        #expect(approxEqual(m.textureTransforms.specularUVTransform,  matrix_identity_float3x3))
        #expect(approxEqual(m.textureTransforms.opacityUVTransform,   matrix_identity_float3x3))
        #expect(m.textureTransforms.hasTextureTransforms == false)
    }

    // MARK: - uvAffine extraction

    @Test("uvAffine(from: nil) returns identity")
    func uvAffineNilIsIdentity() {
        let result = Material.uvAffine(from: nil, materialName: "test")
        #expect(approxEqual(result, matrix_identity_float3x3))
    }

    @Test("uvAffine extracts translation + scale (no rotation) from a 4x4")
    func uvAffineTranslationScale() {
        // Column-major 4x4 with translation=(0.5, 0.25, 0), scale=(2, 3, 1), rotation=0:
        let m4 = matrix_float4x4(
            simd_float4(2,    0,    0, 0),
            simd_float4(0,    3,    0, 0),
            simd_float4(0,    0,    1, 0),
            simd_float4(0.5,  0.25, 0, 1)
        )
        let transform = MDLTransform(matrix: m4)

        let result = Material.uvAffine(from: transform, materialName: "test")

        let expected = matrix_float3x3(
            simd_float3(2,    0,    0),
            simd_float3(0,    3,    0),
            simd_float3(0.5,  0.25, 1)
        )
        #expect(approxEqual(result, expected))
    }

    @Test("uvAffine extracts Z-axis rotation by π/2")
    func uvAffineRotationZ() {
        // Column-major 4x4 for a +π/2 rotation about Z:
        //   column 0 = (cos, sin, 0, 0) = (0,  1, 0, 0)
        //   column 1 = (-sin, cos, 0, 0) = (-1, 0, 0, 0)
        let m4 = matrix_float4x4(
            simd_float4( 0, 1, 0, 0),
            simd_float4(-1, 0, 0, 0),
            simd_float4( 0, 0, 1, 0),
            simd_float4( 0, 0, 0, 1)
        )
        let transform = MDLTransform(matrix: m4)

        let result = Material.uvAffine(from: transform, materialName: "test")

        let expected = matrix_float3x3(
            simd_float3( 0, 1, 0),
            simd_float3(-1, 0, 0),
            simd_float3( 0, 0, 1)
        )
        #expect(approxEqual(result, expected))
    }

    @Test("uvAffine extracts combined T·R·S")
    func uvAffineCombinedTRS() {
        // T·R·S where R is +π/2 about Z, S = (2, 1, 1), T = (1, 2, 0):
        //   R·S column 0 = R_col0 * S.x = (0, 2, 0, 0)
        //   R·S column 1 = R_col1 * S.y = (-1, 0, 0, 0)
        //   T·(R·S) just sets translation column to (1, 2, 0, 1).
        let m4 = matrix_float4x4(
            simd_float4( 0, 2, 0, 0),
            simd_float4(-1, 0, 0, 0),
            simd_float4( 0, 0, 1, 0),
            simd_float4( 1, 2, 0, 1)
        )
        let transform = MDLTransform(matrix: m4)

        let result = Material.uvAffine(from: transform, materialName: "test")

        let expected = matrix_float3x3(
            simd_float3( 0, 2, 0),
            simd_float3(-1, 0, 0),
            simd_float3( 1, 2, 1)
        )
        #expect(approxEqual(result, expected))
    }

    // MARK: - isIdentity

    @Test("isIdentity true for matrix_identity_float3x3")
    func isIdentityTrueOnIdentity() {
        #expect(Material.isIdentity(matrix_identity_float3x3))
    }

    @Test("isIdentity false when any of the 6 affine cells is perturbed",
          arguments: [
            (col: 0, row: 0, value: Float(2.0)),  // scale.x changed
            (col: 0, row: 1, value: Float(0.1)),  // shear / sin changed
            (col: 1, row: 0, value: Float(0.1)),  // shear / -sin changed
            (col: 1, row: 1, value: Float(0.5)),  // scale.y changed
            (col: 2, row: 0, value: Float(0.5)),  // translation.x
            (col: 2, row: 1, value: Float(0.5)),  // translation.y
          ])
    func isIdentityFalseOnPerturbation(args: (col: Int, row: Int, value: Float)) {
        var m = matrix_identity_float3x3
        switch (args.col, args.row) {
        case (0, 0): m.columns.0.x = args.value
        case (0, 1): m.columns.0.y = args.value
        case (1, 0): m.columns.1.x = args.value
        case (1, 1): m.columns.1.y = args.value
        case (2, 0): m.columns.2.x = args.value
        case (2, 1): m.columns.2.y = args.value
        default: Issue.record("unhandled cell")
        }
        #expect(Material.isIdentity(m) == false,
                "Perturbation at column \(args.col), row \(args.row) should not be identity")
    }

    // MARK: - Material(MDLMaterial) integration

    @Test(".string property leaves textureTransforms at identity")
    func materialFromStringPropertyIsIdentity() {
        let mdlMaterial = MDLMaterial(name: "test", scatteringFunction: MDLScatteringFunction())
        let prop = MDLMaterialProperty(name: "baseColor",
                                       semantic: .baseColor,
                                       string: "nonexistent_test_texture")
        mdlMaterial.setProperty(prop)

        let material = Material(mdlMaterial)

        #expect(material.textureTransforms.hasTextureTransforms == false)
        #expect(approxEqual(material.textureTransforms.baseColorUVTransform, matrix_identity_float3x3))
    }

    @Test(".URL property leaves textureTransforms at identity")
    func materialFromURLPropertyIsIdentity() {
        let mdlMaterial = MDLMaterial(name: "test", scatteringFunction: MDLScatteringFunction())
        let url = URL(fileURLWithPath: "/tmp/_tfs_nonexistent_test_texture.png")
        let prop = MDLMaterialProperty(name: "baseColor",
                                       semantic: .baseColor,
                                       url: url)
        mdlMaterial.setProperty(prop)

        let material = Material(mdlMaterial)

        #expect(material.textureTransforms.hasTextureTransforms == false)
        #expect(approxEqual(material.textureTransforms.baseColorUVTransform, matrix_identity_float3x3))
    }

    @Test(".texture property with a non-identity sampler transform populates the matching slot")
    func materialFromTexturePropertyPopulatesTransform() {
        let sampler = makeSampler(transformMatrix: matrix_float4x4(
            simd_float4(2,   0,   0, 0),
            simd_float4(0,   3,   0, 0),
            simd_float4(0,   0,   1, 0),
            simd_float4(0.1, 0.2, 0, 1)
        ))
        let mdlMaterial = MDLMaterial(name: "test", scatteringFunction: MDLScatteringFunction())
        let prop = MDLMaterialProperty(name: "baseColor",
                                       semantic: .baseColor,
                                       textureSampler: sampler)
        mdlMaterial.setProperty(prop)

        let material = Material(mdlMaterial)

        #expect(material.textureTransforms.hasTextureTransforms)

        let expected = matrix_float3x3(
            simd_float3(2,   0,   0),
            simd_float3(0,   3,   0),
            simd_float3(0.1, 0.2, 1)
        )
        #expect(approxEqual(material.textureTransforms.baseColorUVTransform, expected))
        // Other slots remain identity
        #expect(approxEqual(material.textureTransforms.normalUVTransform,   matrix_identity_float3x3))
        #expect(approxEqual(material.textureTransforms.specularUVTransform, matrix_identity_float3x3))
        #expect(approxEqual(material.textureTransforms.opacityUVTransform,  matrix_identity_float3x3))
    }

    @Test("Different transforms across baseColor, normal, specular, opacity slots produce different mat3s")
    func materialMultipleSlotsHaveDistinctTransforms() {
        let baseSampler = makeSampler(transformMatrix: scaleMatrix(2, 2))
        let normalSampler = makeSampler(transformMatrix: scaleMatrix(3, 3))
        let specSampler = makeSampler(transformMatrix: scaleMatrix(4, 4))
        let opacitySampler = makeSampler(transformMatrix: scaleMatrix(5, 5))

        let mdlMaterial = MDLMaterial(name: "test", scatteringFunction: MDLScatteringFunction())
        mdlMaterial.setProperty(MDLMaterialProperty(name: "baseColor",
                                                    semantic: .baseColor,
                                                    textureSampler: baseSampler))
        mdlMaterial.setProperty(MDLMaterialProperty(name: "normal",
                                                    semantic: .tangentSpaceNormal,
                                                    textureSampler: normalSampler))
        mdlMaterial.setProperty(MDLMaterialProperty(name: "specular",
                                                    semantic: .specular,
                                                    textureSampler: specSampler))
        mdlMaterial.setProperty(MDLMaterialProperty(name: "opacity",
                                                    semantic: .opacity,
                                                    textureSampler: opacitySampler))

        let material = Material(mdlMaterial)

        #expect(material.textureTransforms.hasTextureTransforms)
        #expect(material.textureTransforms.baseColorUVTransform.columns.0.x == 2)
        #expect(material.textureTransforms.normalUVTransform.columns.0.x    == 3)
        #expect(material.textureTransforms.specularUVTransform.columns.0.x  == 4)
        #expect(material.textureTransforms.opacityUVTransform.columns.0.x   == 5)
    }

    // MARK: - helpers

    /// Builds a column-major 4x4 with uniform 2D scale on x/y and identity elsewhere.
    private func scaleMatrix(_ sx: Float, _ sy: Float) -> matrix_float4x4 {
        return matrix_float4x4(
            simd_float4(sx, 0,  0, 0),
            simd_float4(0,  sy, 0, 0),
            simd_float4(0,  0,  1, 0),
            simd_float4(0,  0,  0, 1)
        )
    }

    /// Constructs an MDLTextureSampler with a 1x1 RGBA8 texture and the given transform matrix.
    /// The MTKTextureLoader path may fail to convert the synthetic MDLTexture, but the import
    /// code path still extracts the transform regardless.
    private func makeSampler(transformMatrix m: matrix_float4x4) -> MDLTextureSampler {
        let pixelData = Data([255, 0, 0, 255])
        let mdlTexture = MDLTexture(data: pixelData,
                                    topLeftOrigin: false,
                                    name: "test_pixel",
                                    dimensions: SIMD2<Int32>(1, 1),
                                    rowStride: 4,
                                    channelCount: 4,
                                    channelEncoding: .uInt8,
                                    isCube: false)
        let sampler = MDLTextureSampler()
        sampler.texture = mdlTexture
        sampler.transform = MDLTransform(matrix: m)
        return sampler
    }
}
