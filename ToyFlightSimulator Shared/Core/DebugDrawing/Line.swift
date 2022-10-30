//
//  Line.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 10/24/22.
//

import MetalKit

class Line: Node {
    var renderPipelineStateType: RenderPipelineStateType = .DebugDrawing
    var startVertex: Vertex
    var endVertex: Vertex
    
    private var _modelConstants = ModelConstants()
    private var _vertices: [Vertex]
    private var _vertexBuffer: MTLBuffer!
    
    init(name: String, startPoint: float3, endPoint: float3, color: float4 = RED_COLOR) {
        startVertex = Vertex(position: startPoint, color: color)
        endVertex = Vertex(position: endPoint, color: color)
        _vertices = [startVertex, endVertex]
        _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count))
        super.init(name: name)
    }
    
    override func update() {
        _modelConstants.modelMatrix = self.modelMatrix
        super.update()
    }
}

extension Line: Renderable {
    func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[renderPipelineStateType])
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
        
        // Vertex Shader
        renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder.setVertexBytes(&_modelConstants, length: ModelConstants.stride, index: 2)
        
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        renderCommandEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: _vertices.count)
    }
}
