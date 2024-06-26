//
//  Line.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/8/23.
//

import MetalKit

class Line: GameObject {
    var startVertex: Vertex
    var endVertex: Vertex
    
    private var _vertices: [Vertex]
    private var _vertexBuffer: MTLBuffer!
    
    init(startPoint: float3, endPoint: float3, color: float4 = RED_COLOR) {
        startVertex = Vertex(position: startPoint, color: color)
        endVertex = Vertex(position: endPoint, color: color)
        _vertices = [startVertex, endVertex]
        _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices, length: Vertex.stride(_vertices.count))
        super.init(name: "Line", meshType: .None)
        if color.w < 1.0 {
            _renderPipelineStateType = .OrderIndependentTransparent
        }
    }
    
    override func doRender(_ renderEncoder: MTLRenderCommandEncoder,
                           applyMaterials: Bool,
                           submeshesToRender: [String: Bool]? = nil) {
        super.doRender(renderEncoder)
        renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: _vertices.count)
    }
}
