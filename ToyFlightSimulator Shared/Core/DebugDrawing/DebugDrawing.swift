//
//  DebugDrawing.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 10/24/22.
//

import MetalKit

//class DebugDrawing: Node, Renderable {
//    let renderPipelineStateType: RenderPipelineStateType = .DebugDrawing
//    private var _modelConstants = ModelConstants()
//    
//    override init(name: String) {
//        super.init(name: name)
//    }
//    
//    override func update() {
//        _modelConstants.modelMatrix = self.modelMatrix
//        super.update()
//    }
//    
//    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
//        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
//        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
//        
//        // Vertex Shader
//        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
//        
//        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
//    }
//}
