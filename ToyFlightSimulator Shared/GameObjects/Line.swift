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
    public var vertices: [Vertex]
    public var vertexBuffer: MTLBuffer!
    
    init(startPoint: float3, endPoint: float3, color: float4 = RED_COLOR) {
        startVertex = Vertex(position: startPoint, color: color)
        endVertex = Vertex(position: endPoint, color: color)
        vertices = [startVertex, endVertex]
        vertexBuffer = Engine.Device.makeBuffer(bytes: vertices, length: Vertex.stride(vertices.count))
        super.init(name: "Line", modelType: .None)
    }
}
