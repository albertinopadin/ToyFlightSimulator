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
                        let sourceTexture = property.textureSamplerValue!.texture!
                        let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                        populateTexture(texture, for: semantic)

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
