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
    
    init(_ properties: MaterialProperties) {
        self.properties = properties
    }
    
    init(_ mdlMaterial: MDLMaterial) {
        name = mdlMaterial.name
        // TODO: 
//        setProperties(with: mdlMaterial, semantics: [.emission, .baseColor, .specular, .specularExponent])
        populateMaterial(with: mdlMaterial)
    }
    
    private mutating func populateMaterial(with material: MDLMaterial) {
        for semantic in MDLMaterialSemantic.allCases {
            for property in material.properties(with: semantic) {
                switch property.type {
                    case .string:
                        print("Material property is string!")
                        if let stringValue = property.stringValue {
                            print("Material property string value: \(stringValue)")
                            // TODO: This smells nasty
                            let texture = TextureLoader.Texture(name: stringValue)
                            populateTexture(texture, for: semantic)
                        }
                    case .URL:
                        print("Material property is url!")
                    
                        if let textureURL = property.urlValue {
                            let texture = TextureLoader.Texture(url: textureURL)
                            populateTexture(texture, for: semantic)
                        }
                    case .texture:
                        print("Material property is texture!")
                        let sourceTexture = property.textureSamplerValue!.texture!
                        let texture = TextureLoader.Texture(mdlTexture: sourceTexture)
                        populateTexture(texture, for: semantic)
                    
                    case .color:
                        print("Material property is color!")
                        
                        let color = float4(Float(property.color!.components![0]),
                                           Float(property.color!.components![1]),
                                           Float(property.color!.components![2]),
                                           Float(property.color!.components![3]))
                        
                        properties.setColor(color)
                        
                    case .buffer:
                        print("Material \(material.name) property is a buffer for semantic: \(semantic.toString())")
                    case .matrix44:
                        print("Material \(material.name) property is 4x4 matrix for semantic: \(semantic.toString())")
                    case .float:
                        print("Material \(material.name) property is float for semantic: \(semantic.toString())")
                        switch semantic {
                            case .opacity:
                                properties.opacity = property.floatValue
                            default:
                                print("Property was not opacity")
                        }
                    case .float2:
                        print("Material \(material.name) property is float2 for semantic: \(semantic.toString())")
                    case .float3:
                        print("Material \(material.name) property is float3 for semantic: \(semantic.toString())")
                    case .float4:
                        print("Material \(material.name) property is float4 for semantic: \(semantic.toString())")
                    case .none:
                        print("Material \(material.name) property is none for semantic: \(semantic.toString())")
                    default:
                        fatalError("Data for material property not found - name: \(material.name), class name: \(material.className), debug desc: \(material.debugDescription), for semantic: \(semantic.toString())")
                }
            }
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
                    default:
                        print("[Material setShaderMaterialProperty] Unused semantic: \(semantic.toString())")
                }
            }
        }
    }
    
    public mutating func applyTextures(with renderEncoder: MTLRenderCommandEncoder,
                                       baseColorTextureType: TextureType,
                                       normalMapTextureType: TextureType,
                                       specularTextureType: TextureType) {
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
