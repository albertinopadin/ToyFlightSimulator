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
    
    case BaseFragment
    case MaterialFragment
    case SkySphereFragment
    case FinalFragment
    case DebugDrawingFragment
    case TransparentFragment
    case TransparentMaterialFragment
    case BlendFragment
    
    case TileKernel
}


class ShaderLibrary: Library<ShaderType, MTLFunction> {
    private var _library: [ShaderType: Shader] = [:]
    
    override func makeLibrary() {
        _library.updateValue(Shader(functionName: "base_vertex_shader"), forKey: .BaseVertex)
        _library.updateValue(Shader(functionName: "instanced_vertex_shader"), forKey: .InstancedVertex)
        _library.updateValue(Shader(functionName: "skysphere_vertex_shader"), forKey: .SkySphereVertex)
        _library.updateValue(Shader(functionName: "final_vertex_shader"), forKey: .FinalVertex)
        _library.updateValue(Shader(functionName: "quad_pass_vertex_shader"), forKey: .QuadPassVertex)
        
        _library.updateValue(Shader(functionName: "base_fragment_shader"), forKey: .BaseFragment)
        _library.updateValue(Shader(functionName: "material_fragment_shader"), forKey: .MaterialFragment)
        _library.updateValue(Shader(functionName: "skysphere_fragment_shader"), forKey: .SkySphereFragment)
        _library.updateValue(Shader(functionName: "final_fragment_shader"), forKey: .FinalFragment)
        _library.updateValue(Shader(functionName: "debug_fragment_shader"), forKey: .DebugDrawingFragment)
        _library.updateValue(Shader(functionName: "transparent_fragment_shader"), forKey: .TransparentFragment)
        _library.updateValue(Shader(functionName: "transparent_material_fragment_shader"), forKey: .TransparentMaterialFragment)
        _library.updateValue(Shader(functionName: "blend_fragments"), forKey: .BlendFragment)
        
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
