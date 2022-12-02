//
//  Line.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 10/24/22.
//

import MetalKit

class DebugLine: DebugDrawing {
    var startVertex: Vertex
    var endVertex: Vertex
    
    
    private var _vertices: [Vertex]
    private var _vertexBuffer: MTLBuffer!
    
    init(name: String, startPoint: float3, endPoint: float3, color: float4 = RED_COLOR) {
        startVertex = Vertex(position: startPoint, color: color)
        endVertex = Vertex(position: endPoint, color: color)
        _vertices = [startVertex, endVertex]
        _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count))
        super.init(name: name)
    }
    
    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        super.doRender(renderCommandEncoder)
        renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: _vertices.count)
    }
}
