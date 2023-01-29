//
//  ShaderLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum ShaderType {
    case BaseVertex
    case InstancedVertex
    case SkySphereVertex
    case FinalVertex
    case QuadPassVertex
    
    case ShadowVertex
    case GBufferVertex
    case DeferredDirectionalLightingVertex
    case LightMaskVertex
    case DeferredPointLightVertex
    case SkyboxVertex
    
    case BaseFragment
    case MaterialFragment
    case SkySphereFragment
    case FinalFragment
    case TransparentFragment
    case TransparentMaterialFragment
    case BlendFragment
    
    case GBufferFragment
    case DeferredDirectionalLightingFragment
    case DeferredPointLightFragment
    case SkyboxFragment
    
    case TileKernel
}


class ShaderLibrary: Library<ShaderType, MTLFunction> {
    private var _library: [ShaderType: Shader] = [:]
    
    override func makeLibrary() {
        _library.updateValue(Shader(functionName: "base_vertex"), forKey: .BaseVertex)
        _library.updateValue(Shader(functionName: "instanced_vertex"), forKey: .InstancedVertex)
        _library.updateValue(Shader(functionName: "skysphere_vertex"), forKey: .SkySphereVertex)
        _library.updateValue(Shader(functionName: "final_vertex"), forKey: .FinalVertex)
        _library.updateValue(Shader(functionName: "quad_pass_vertex"), forKey: .QuadPassVertex)
        
        _library.updateValue(Shader(functionName: "shadow_vertex"), forKey: .ShadowVertex)
        _library.updateValue(Shader(functionName: "gbuffer_vertex"), forKey: .GBufferVertex)
        _library.updateValue(Shader(functionName: "deferred_directional_lighting_vertex"),
                             forKey: .DeferredDirectionalLightingVertex)
        _library.updateValue(Shader(functionName: "light_mask_vertex"), forKey: .LightMaskVertex)
        _library.updateValue(Shader(functionName: "deferred_point_lighting_vertex"), forKey: .DeferredPointLightVertex)
        _library.updateValue(Shader(functionName: "skybox_vertex"), forKey: .SkyboxVertex)
        
        _library.updateValue(Shader(functionName: "base_fragment"), forKey: .BaseFragment)
        _library.updateValue(Shader(functionName: "material_fragment"), forKey: .MaterialFragment)
        _library.updateValue(Shader(functionName: "skysphere_fragment"), forKey: .SkySphereFragment)
        _library.updateValue(Shader(functionName: "final_fragment"), forKey: .FinalFragment)
        _library.updateValue(Shader(functionName: "transparent_fragment"), forKey: .TransparentFragment)
        _library.updateValue(Shader(functionName: "transparent_material_fragment"), forKey: .TransparentMaterialFragment)
        _library.updateValue(Shader(functionName: "blend_fragments"), forKey: .BlendFragment)
        
        _library.updateValue(Shader(functionName: "gbuffer_fragment"), forKey: .GBufferFragment)
        _library.updateValue(Shader(functionName: "deferred_directional_lighting_fragment"),
                             forKey: .DeferredDirectionalLightingFragment)
        _library.updateValue(Shader(functionName: "deferred_point_lighting_fragment"), forKey: .DeferredPointLightFragment)
        _library.updateValue(Shader(functionName: "skybox_fragment"), forKey: .SkyboxFragment)
        
        _library.updateValue(Shader(functionName: "init_transparent_fragment_store"), forKey: .TileKernel)
    }
    
    override subscript(_ type: ShaderType) -> MTLFunction {
        return (_library[type]?.function)!
    }
}

class Shader {
    var function: MTLFunction!
    init(functionName: String) {
        self.function = Engine.DefaultLibrary.makeFunction(name: functionName)
        self.function.label = functionName
    }
}
