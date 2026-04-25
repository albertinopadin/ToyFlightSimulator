//
//  Material.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/7/24.
//

import MetalKit

struct Material: sizeable {
    public var name: String = "material"
    public var properties = MaterialProperties()
    public var textureTransforms = MaterialTextureTransforms()

    public var baseColorTexture: MTLTexture?
    public var normalMapTexture: MTLTexture?
    public var specularTexture: MTLTexture?
    public var roughnessTexture: MTLTexture?
    public var metallicTexture: MTLTexture?
    public var ambientOcclusionTexture: MTLTexture?
    public var opacityTexture: MTLTexture?
    
    public var isTransparent: Bool {
        return opacityTexture != nil || properties.opacity < 1.0 || properties.color.w < 1.0
    }
    
    init(_ mdlMaterial: MDLMaterial) {
        name = mdlMaterial.name
        setProperties(with: mdlMaterial, semantics: [.emission, .baseColor, .specular, .specularExponent, .opacity])
        populateMaterial(with: mdlMaterial)
    }
    
    private mutating func populateMaterial(with material: MDLMaterial) {
        for semantic in MDLMaterialSemantic.allCases {
            for property in material.properties(with: semantic) {
                switch property.type {
                    case .string:
                        if let stringValue = property.stringValue {
                            let texture = TextureLoader.Texture(name: stringValue)
                            populateTexture(texture, for: semantic)
                        }

                    case .URL:
                        if let textureURL = property.urlValue {
                            let texture = TextureLoader.Texture(url: textureURL)
                            populateTexture(texture, for: semantic)
                        }

                    case .texture:
                        guard let sampler = property.textureSamplerValue,
                              let sourceTexture = sampler.texture else { break }

                        let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                        populateTexture(texture, for: semantic)

                        let uvAffine = Self.uvAffine(from: sampler.transform, materialName: name)
                        populateTextureTransform(uvAffine, for: semantic)

                    case .color, .float3, .float4:
                        if semantic == .baseColor {
                            setBaseColor(from: property)
                        }

                    case .float:
                        if semantic == .opacity {
                            properties.opacity = property.floatValue
                        }
                        // ambient occlusion, ao scale, anisotropic rotation, clearcoat, clearcoat gloss,
                        // interface index of refraction, material index of refraction, none (WTF???),
                        // roughness, sheen, sheen tint, specular, specular tint, subsurface,

                    case .buffer, .matrix44, .float2, .none:
                        print("Material \(material.name) property is \(property.type) for semantic: \(semantic.toString())")
                        break

                    default:
                        break
                }
            }
        }
    }

    private mutating func setBaseColor(from property: MDLMaterialProperty) {
        switch property.type {
            case .color:
                guard let components = property.color?.components, components.count >= 3 else { return }
                let alpha: Float = components.count > 3 ? Float(components[3]) : 1.0
                properties.color = float4(Float(components[0]),
                                          Float(components[1]),
                                          Float(components[2]),
                                          alpha)
            case .float3:
                let rgb = property.float3Value
                properties.color = float4(rgb.x, rgb.y, rgb.z, 1.0)

            case .float4:
                properties.color = property.float4Value

            default:
                break
        }
    }
    
    private mutating func populateTexture(_ texture: MTLTexture?, for semantic: MDLMaterialSemantic) {
        switch semantic {
            case .baseColor:
                baseColorTexture = texture
            case .tangentSpaceNormal:
                normalMapTexture = texture
            case .specular:
                specularTexture = texture
            case .roughness:
                roughnessTexture = texture
            case .metallic:
                metallicTexture = texture
            case .ambientOcclusion:
                ambientOcclusionTexture = texture
            case .opacity:
                opacityTexture = texture
            case .emission:
                // TODO
                print("[Material populateTexture] Emission not implemented!")
            default:
                print("Got string for semantic \(semantic.toString())")

        }
    }

    private mutating func populateTextureTransform(_ uvAffine: matrix_float3x3,
                                                   for semantic: MDLMaterialSemantic) {
        guard !Self.isIdentity(uvAffine) else { return }

        switch semantic {
            case .baseColor:           textureTransforms.baseColorUVTransform = uvAffine
            case .tangentSpaceNormal:  textureTransforms.normalUVTransform    = uvAffine
            case .specular:            textureTransforms.specularUVTransform  = uvAffine
            case .opacity:             textureTransforms.opacityUVTransform   = uvAffine
            default:                   return  // semantic not yet wired to a transform slot
        }
        textureTransforms.hasTextureTransforms = true
    }

    /// Extracts a 2D affine UV transform from an MDLTransform. Returns identity when nil.
    /// Pulls the 2D effect from the resolved 4x4 (upper-left 2x2 + translation column) so it works
    /// regardless of which Euler axis the importer used to encode the 2D rotation.
    /// MDLTransform.matrix is documented as "the matrix at minimumTime", so for animated transforms
    /// this freezes to the earliest sample; v1 logs a warning when animation data is present.
    static func uvAffine(from transform: MDLTransform?, materialName: String) -> matrix_float3x3 {
        guard let transform else { return matrix_identity_float3x3 }

        if transform.minimumTime != transform.maximumTime || transform.keyTimes.count > 1 {
            print("[Material:\(materialName)] Animated MDLTextureSampler.transform is not supported yet; freezing to earliest sample.")
        }

        let m = transform.matrix
        return matrix_float3x3(
            simd_float3(m.columns.0.x, m.columns.0.y, 0),
            simd_float3(m.columns.1.x, m.columns.1.y, 0),
            simd_float3(m.columns.3.x, m.columns.3.y, 1)
        )
    }

    static func isIdentity(_ m: matrix_float3x3) -> Bool {
        let eps: Float = 1e-6
        return abs(m.columns.0.x - 1) < eps && abs(m.columns.0.y) < eps &&
               abs(m.columns.1.x)     < eps && abs(m.columns.1.y - 1) < eps &&
               abs(m.columns.2.x)     < eps && abs(m.columns.2.y)     < eps
    }
    
    private mutating func setProperties(with mdlMaterial: MDLMaterial, semantics: [MDLMaterialSemantic]) {
        for semantic in semantics {
            if let materialProp = mdlMaterial.property(with: semantic) {
                switch semantic {
                    case .emission:
                        let ambient = materialProp.float3Value
                        if ambient != .zero {
                            properties.ambient = ambient
                        }
                    case .baseColor:
                        let diffuse = materialProp.float3Value
                        if diffuse != .zero {
                            properties.diffuse = diffuse
                        }
                    case .specular:
                        let specular = materialProp.float3Value
                        if specular != .zero {
                            properties.specular = specular
                        }
                    case .specularExponent:
                        let shininess = materialProp.floatValue
                        if shininess != .zero {
                            properties.shininess = shininess
                        }
                    case .opacity:
                        properties.opacity = materialProp.floatValue
                    default:
                        print("[Material setShaderMaterialProperty] Unused semantic: \(semantic.toString())")
                }
            }
        }
    }
}
