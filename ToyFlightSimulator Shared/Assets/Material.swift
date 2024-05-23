//
//  Material.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/7/24.
//

import MetalKit

struct Material {
    public var name: String = "material"
    public var shaderMaterial = ShaderMaterial()
    public var baseColorTexture: MTLTexture?
    public var normalMapTexture: MTLTexture?
    public var specularTexture: MTLTexture?
    
    init(_ shaderMaterial: ShaderMaterial) {
        self.shaderMaterial = shaderMaterial
    }
    
    init(_ mdlMaterial: MDLMaterial) {
        name = mdlMaterial.name
        setShaderMaterialProperties(with: mdlMaterial, semantics: [.emission, .baseColor, .specular, .specularExponent])
        baseColorTexture = TextureLoader.Texture(for: .baseColor, in: mdlMaterial)
        normalMapTexture = TextureLoader.Texture(for: .tangentSpaceNormal, in: mdlMaterial)
        specularTexture = TextureLoader.Texture(for: .specular, in: mdlMaterial)
    }
    
    private mutating func setShaderMaterialProperties(with mdlMaterial: MDLMaterial, semantics: [MDLMaterialSemantic]) {
        for semantic in semantics {
            if let materialProp = mdlMaterial.property(with: semantic) {
                switch semantic {
                    case .emission:
                        let ambient = materialProp.float3Value
                        if ambient != .zero {
                            shaderMaterial.ambient = ambient
                        }
                    case .baseColor:
                        let diffuse = materialProp.float3Value
                        if diffuse != .zero {
                            shaderMaterial.diffuse = diffuse
                        }
                    case .specular:
                        let specular = materialProp.float3Value
                        if specular != .zero {
                            shaderMaterial.specular = specular
                        }
                    case .specularExponent:
                        let shininess = materialProp.floatValue
                        if shininess != .zero {
                            shaderMaterial.shininess = shininess
                        }
                    default:
                        print("[Material setShaderMaterialProperty] Unused semantic: \(semantic)")
                }
            }
        }
    }
    
    public mutating func applyTextures(with renderEncoder: MTLRenderCommandEncoder,
                                       baseColorTextureType: TextureType,
                                       normalMapTextureType: TextureType,
                                       specularTextureType: TextureType) {
        shaderMaterial.useBaseTexture = baseColorTextureType != .None || baseColorTexture != nil
        shaderMaterial.useNormalMapTexture = normalMapTextureType != .None || normalMapTexture != nil
        shaderMaterial.useSpecularTexture = specularTextureType != .None || specularTexture != nil
        
        renderEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        if let baseColorTex = baseColorTextureType == .None ? baseColorTexture : Assets.Textures[baseColorTextureType] {
            renderEncoder.setFragmentTexture(baseColorTex, index: TFSTextureIndexBaseColor.index)
        }
        
        if let normalMapTex = normalMapTextureType == .None ? normalMapTexture : Assets.Textures[normalMapTextureType] {
            renderEncoder.setFragmentTexture(normalMapTex, index: TFSTextureIndexNormal.index)
        }
        
        if let specularTex = specularTextureType == .None ? specularTexture : Assets.Textures[specularTextureType] {
            renderEncoder.setFragmentTexture(specularTex, index: TFSTextureIndexSpecular.index)
        }
    }
}
