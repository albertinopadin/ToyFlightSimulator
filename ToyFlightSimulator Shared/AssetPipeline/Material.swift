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
                            let texture = TextureLoader.Texture(name: stringValue,
                                                                srgb: Self.isSRGBSemantic(semantic))
                            populateTexture(texture, for: semantic)
                        }

                    case .URL:
                        if let textureURL = property.urlValue {
                            let texture = TextureLoader.Texture(url: textureURL,
                                                                srgb: Self.isSRGBSemantic(semantic))
                            populateTexture(texture, for: semantic)
                        }

                    case .texture:
                        guard let sampler = property.textureSamplerValue,
                              let sourceTexture = sampler.texture else { break }

                        let texture = TextureLoader.Texture(mdlTexture: sourceTexture,
                                                            srgb: Self.isSRGBSemantic(semantic))
                        populateTexture(texture, for: semantic)

                        let uvAffine = Self.uvAffine(from: sampler.transform, materialName: name)
                        populateTextureTransform(uvAffine, for: semantic)

                    case .color, .float3, .float4:
                        // FIXME (2026-09-21 review): the LAST .baseColor value wins here, and Model I/O
                        // lists the authored USD `diffuseColor` FIRST and its own scattering-function
                        // default (0.18, 0.18, 0.18, named "baseColor") after it. Every untextured USD
                        // material therefore ends up 0.18 gray: the Sketchfab F-22 canopy authors
                        // (1.0, 0.44, 0.07) at opacity 0.6, the HUD glass (0.01, 0.29, 0.0), the landing
                        // lights 0.8. OBJ files have one property per semantic (Kd and map_Kd are merged),
                        // so "first wins" is right for both dialects; `MDLMaterial.property(with:)`
                        // returns exactly that first one. Fix: call setBaseColor only for the first
                        // .baseColor property. See research/claude/
                        // modelio_material_semantics_blinn_phong_2026-09-21.md §2.2 and
                        // scripts/inspect_mdl_materials.swift (prints MISMATCH for the affected materials).
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
    
    /// Only color-like maps are sRGB-encoded and should be created with an sRGB pixel format.
    /// Data maps (normal, roughness, metallic, AO, opacity) must load linear — an sRGB pixel
    /// format would gamma-decode them on sample and skew the values. Explicit false (rather than
    /// nil = "trust file metadata") so a mis-tagged PNG can't sneak a data map in as sRGB.
    static func isSRGBSemantic(_ semantic: MDLMaterialSemantic) -> Bool {
        switch semantic {
            case .baseColor, .emission:
                return true
            default:
                return false
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
                        // Legacy: `ambient` is no longer read by the lighting path (ambient is
                        // albedo × ambientIntensity in Lighting::ShadeDirectionalBlinnPhong). The slot is
                        // also not an emissive color for OBJ files: Model I/O's OBJ importer stores the MTL
                        // `Ka` line (ambient reflectivity; Blender writes 1 1 1) under .emission and drops
                        // `Ke`, so treating it as emission would paint the F-16 white. For USD it is the
                        // authored `emissiveColor` (the Sketchfab F-22 landing lights). A real emission
                        // term needs a shader change first; see research/claude/
                        // modelio_material_semantics_blinn_phong_2026-09-21.md §1.2.
                        let ambient = materialProp.float3Value
                        if ambient != .zero {
                            properties.ambient = ambient
                        }
                    case .baseColor:
                        // Legacy: `diffuse` is not read by the shading path. The albedo fallback the shaders
                        // use is `properties.color`, set by populateMaterial. `property(with:)` returns the
                        // FIRST .baseColor property, so this reads the authored value even for USD files.
                        let diffuse = materialProp.float3Value
                        if diffuse != .zero {
                            properties.diffuse = diffuse
                        }
                    case .roughness:
                        // FIXME (2026-09-21 review): this case never runs today because `.roughness` is
                        // not in the semantics list passed from init, and it is not yet correct:
                        // 1. The derived value is an EXPONENT and belongs in `properties.shininess`;
                        //    `properties.specular` is the highlight strength.
                        // 2. Karis 2013 is α = roughness², power = 2/α² − 2, i.e. 2 / roughness⁴ − 2.
                        //    `2 / pow(roughness, 2) - 2` skips the α step (roughness 0.5 gives 6, not 30).
                        // 3. Only derive when the file authored no `.specularExponent` (the USD dialect):
                        //    Model I/O gives EVERY OBJ material a roughness of 0.9 that is not in the MTL
                        //    file, which would replace an authored `Ns` with an exponent of about 1.
                        // 4. Clamp to [1, 1024]: roughness 0 gives infinity, roughness 1 gives 0.
                        // A texture-typed roughness (the F-22 and F-35 airframes) reads floatValue 0 and is
                        // skipped by the guard, which is right: nothing samples roughnessTexture yet.
                        // Numbers: scripts/blinn_phong_roughness_table.swift.
                        let roughness = materialProp.floatValue
                        if roughness != .zero {
                            properties.specular = float3(repeating: (2 / pow(roughness, 2)) - 2)
                        }
                    case .specular:
                        // MTL `Ks`. A texture-typed .specular (map_Ks) is loaded into specularTexture by
                        // populateMaterial; float3Value is meaningful only for the .float3 type. USD
                        // materials arrive with a scalar float 0 placeholder here (metallic workflow, no
                        // specularColor), which the non-zero guard skips so the 0.25 default survives. The
                        // same guard also skips an authored `Ks 0 0 0`, so a matte MTL material cannot
                        // switch its highlight off yet; checking `materialProp.type == .float3` instead
                        // would allow that.
                        let specular = materialProp.float3Value
                        if specular != .zero {
                            properties.specular = specular
                        }
                    case .specularExponent:
                        // MTL `Ns` (0...1000). USD files have no exponent, so the property is absent and
                        // the default 32 stays. `Ns 0` means "no highlight", not "exponent 0": the shader
                        // clamps the exponent to at least 1, so an Ns below 1 should zero the strength.
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
