//
//  TextureLoaderOptionsTests.swift
//  ToyFlightSimulatorTests
//

import Testing
import MetalKit
import ModelIO
@testable import ToyFlightSimulator

@Suite("TextureLoader options", .tags(.assetPipeline))
struct TextureLoaderOptionsTests {

    // MARK: - MakeTextureLoaderOptions sRGB handling

    @Test("srgb defaults to nil and omits the .SRGB key, deferring to file gamma metadata")
    func srgbOmittedByDefault() {
        let options = TextureLoader.MakeTextureLoaderOptions(textureOrigin: .bottomLeft,
                                                             generateMipmaps: true)
        #expect(options[.SRGB] == nil)
    }

    @Test("srgb: true forces the .SRGB option on")
    func srgbTrueSetsKey() {
        let options = TextureLoader.MakeTextureLoaderOptions(textureOrigin: .bottomLeft,
                                                             generateMipmaps: true,
                                                             srgb: true)
        #expect(options[.SRGB] as? Bool == true)
    }

    @Test("srgb: false forces the .SRGB option off (linear pixel format)")
    func srgbFalseSetsKey() {
        let options = TextureLoader.MakeTextureLoaderOptions(textureOrigin: .bottomLeft,
                                                             generateMipmaps: false,
                                                             srgb: false)
        #expect(options[.SRGB] as? Bool == false)
    }

    @Test("srgb parameter leaves the other options untouched")
    func otherOptionsUnchanged() {
        let options = TextureLoader.MakeTextureLoaderOptions(textureOrigin: .topLeft,
                                                             generateMipmaps: true,
                                                             srgb: true)
        #expect(options[.origin] as? MTKTextureLoader.Origin == .topLeft)
        #expect(options[.generateMipmaps] as? Bool == true)
        #expect(options[.textureUsage] as? UInt == MTLTextureUsage.shaderRead.rawValue)
        #expect(options[.textureStorageMode] as? UInt == MTLStorageMode.private.rawValue)
    }

    // MARK: - Material semantic classification

    @Test("color-like semantics load as sRGB")
    func colorSemanticsAreSRGB() {
        #expect(Material.isSRGBSemantic(.baseColor) == true)
        #expect(Material.isSRGBSemantic(.emission) == true)
    }

    @Test("data semantics load linear")
    func dataSemanticsAreLinear() {
        #expect(Material.isSRGBSemantic(.tangentSpaceNormal) == false)
        #expect(Material.isSRGBSemantic(.roughness) == false)
        #expect(Material.isSRGBSemantic(.metallic) == false)
        #expect(Material.isSRGBSemantic(.ambientOcclusion) == false)
        #expect(Material.isSRGBSemantic(.opacity) == false)
        #expect(Material.isSRGBSemantic(.specular) == false)
    }
}
