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
    case SinglePassDeferredGBufferVertex
    case SinglePassDeferredDirectionalLightVertex
    case LightMaskVertex
    case SinglePassDeferredPointLightVertex
    case SkyboxVertex
    
    case BaseFragment
    case MaterialFragment
    case SkySphereFragment
    case FinalFragment
    case TransparentFragment
    case TransparentMaterialFragment
    case BlendFragment
    
    case SinglePassDeferredGBufferFragmentBase
    case SinglePassDeferredGBufferFragmentMaterial
    case SinglePassDeferredDirectionalLightFragment
    case SinglePassDeferredPointLightFragment
    case SkyboxFragment
    
    case TileKernel
    
    case IcosahedronVertex
    case IcosahedronFragment
    
    case TiledDeferredGBufferVertex
    case TiledDeferredGBufferFragment
    case TiledDeferredQuadVertex
    case TiledDeferredDirectionalLightFragment
    case TiledDeferredPointLightVertex
    case TiledDeferredPointLightFragment
    case TiledDeferredTransparencyVertex
    case TiledDeferredTransparencyFragment
    
    case ComputeParticles
    
    case ParticlesVertex
    case ParticlesFragment
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
        _library.updateValue(Shader(functionName: "gbuffer_vertex"), forKey: .SinglePassDeferredGBufferVertex)
        _library.updateValue(Shader(functionName: "deferred_directional_lighting_vertex"),
                             forKey: .SinglePassDeferredDirectionalLightVertex)
        _library.updateValue(Shader(functionName: "light_mask_vertex"), forKey: .LightMaskVertex)
        _library.updateValue(Shader(functionName: "deferred_point_lighting_vertex"), 
                             forKey: .SinglePassDeferredPointLightVertex)
        _library.updateValue(Shader(functionName: "skybox_vertex"), forKey: .SkyboxVertex)
        
        _library.updateValue(Shader(functionName: "base_fragment"), forKey: .BaseFragment)
        _library.updateValue(Shader(functionName: "material_fragment"), forKey: .MaterialFragment)
        _library.updateValue(Shader(functionName: "skysphere_fragment"), forKey: .SkySphereFragment)
        _library.updateValue(Shader(functionName: "final_fragment"), forKey: .FinalFragment)
        _library.updateValue(Shader(functionName: "transparent_fragment"), forKey: .TransparentFragment)
        _library.updateValue(Shader(functionName: "transparent_material_fragment"), forKey: .TransparentMaterialFragment)
        _library.updateValue(Shader(functionName: "blend_fragments"), forKey: .BlendFragment)
        
        _library.updateValue(Shader(functionName: "gbuffer_fragment_base"), forKey: .SinglePassDeferredGBufferFragmentBase)
        _library.updateValue(Shader(functionName: "gbuffer_fragment_material"), forKey: .SinglePassDeferredGBufferFragmentMaterial)
        _library.updateValue(Shader(functionName: "deferred_directional_lighting_fragment"),
                             forKey: .SinglePassDeferredDirectionalLightFragment)
        _library.updateValue(Shader(functionName: "deferred_point_lighting_fragment"), forKey: .SinglePassDeferredPointLightFragment)
        _library.updateValue(Shader(functionName: "skybox_fragment"), forKey: .SkyboxFragment)
        
        _library.updateValue(Shader(functionName: "init_transparent_fragment_store"), forKey: .TileKernel)
        
        // For testing:
        _library.updateValue(Shader(functionName: "icosahedron_vertex"), forKey: .IcosahedronVertex)
        _library.updateValue(Shader(functionName: "icosahedron_fragment"), forKey: .IcosahedronFragment)
        
        // TiledDeferred:
        _library.updateValue(Shader(functionName: "tiled_deferred_gbuffer_vertex"), forKey: .TiledDeferredGBufferVertex)
        _library.updateValue(Shader(functionName: "tiled_deferred_gbuffer_fragment"), forKey: .TiledDeferredGBufferFragment)
        _library.updateValue(Shader(functionName: "tiled_deferred_vertex_quad"), forKey: .TiledDeferredQuadVertex)
        _library.updateValue(Shader(functionName: "tiled_deferred_directional_light_fragment"),
                             forKey: .TiledDeferredDirectionalLightFragment)
        _library.updateValue(Shader(functionName: "tiled_deferred_point_light_vertex"), 
                             forKey: .TiledDeferredPointLightVertex)
        _library.updateValue(Shader(functionName: "tiled_deferred_point_light_fragment"), 
                             forKey: .TiledDeferredPointLightFragment)
        _library.updateValue(Shader(functionName: "tiled_deferred_transparency_vertex"),
                             forKey: .TiledDeferredTransparencyVertex)
        _library.updateValue(Shader(functionName: "tiled_deferred_transparency_fragment"),
                             forKey: .TiledDeferredTransparencyFragment)
        
        _library.updateValue(Shader(functionName: "vertex_particle"), forKey: .ParticlesVertex)
        _library.updateValue(Shader(functionName: "fragment_particle"), forKey: .ParticlesFragment)
        
        // Compute Functions:
        _library.updateValue(Shader(functionName: "compute_particle"), forKey: .ComputeParticles)
    }
    
    override subscript(_ type: ShaderType) -> MTLFunction {
        return (_library[type]?.function)!
    }
}

struct Shader {
    var function: MTLFunction!
    init(functionName: String) {
        self.function = Engine.DefaultLibrary.makeFunction(name: functionName)
        self.function.label = functionName
    }
}
