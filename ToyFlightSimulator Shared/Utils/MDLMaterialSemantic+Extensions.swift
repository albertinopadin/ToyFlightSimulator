//
//  MDLMaterialSemantic+Extensions.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/11/24.
//

import ModelIO

extension MDLMaterialSemantic {
    public static var allCases: [MDLMaterialSemantic] {
        get {
            return [
                .ambientOcclusion,
                .ambientOcclusionScale,
                .anisotropic,
                .anisotropicRotation,
                .baseColor,
                .bump,
                .clearcoat,
                .clearcoatGloss,
                .displacement,
                .displacementScale,
                .emission,
                .interfaceIndexOfRefraction,
                .materialIndexOfRefraction,
                .metallic,
                .none,
                .objectSpaceNormal,
                .opacity,
                .roughness,
                .sheen,
                .sheenTint,
                .specular,
                .specularExponent,
                .specularTint,
                .subsurface,
                .tangentSpaceNormal,
                .userDefined
            ]
        }
    }
    
    func toString() -> String {
        switch self {
            case .ambientOcclusion:
                return "Ambient Occlusion"
            case .ambientOcclusionScale:
                return "Ambient Occlusion Scale"
            case .anisotropic:
                return "Anisotropic"
            case .anisotropicRotation:
                return "Anisotropic Rotation"
            case .baseColor:
                return "Base Color"
            case .bump:
                return "Bump"
            case .clearcoat:
                return "Clearcoat"
            case .clearcoatGloss:
                return "Clearcoat Gloss"
            case .displacement:
                return "Displacement"
            case .displacementScale:
                return "Displacement Scale"
            case .emission:
                return "Emission"
            case .interfaceIndexOfRefraction:
                return "Interface Index Of Refraction"
            case .materialIndexOfRefraction:
                return "Material Index Of Refraction"
            case .metallic:
                return "Metallic"
            case .none:
                return "None"
            case .objectSpaceNormal:
                return "Object Space Normal"
            case .opacity:
                return "Opacity"
            case .roughness:
                return "Roughness"
            case .sheen:
                return "Sheen"
            case .sheenTint:
                return "Sheen Tint"
            case .specular:
                return "Specular"
            case .specularExponent:
                return "Specular Exponent"
            case .specularTint:
                return "Specular Tint"
            case .subsurface:
                return "Subsurface"
            case .tangentSpaceNormal:
                return "Tangent Space Normal"
            case .userDefined:
                return "User Defined"
            default:
                return "UNKNOWN SEMANTIC"
        }
    }
}
