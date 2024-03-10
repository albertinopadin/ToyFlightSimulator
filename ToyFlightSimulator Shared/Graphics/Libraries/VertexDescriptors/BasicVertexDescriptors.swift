//
//  BasicVertexDescriptors.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

public struct BaseVertexDescriptor: VertexDescriptor {
    var name: String = "Base Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var bufferIndex: Int = 0
    var offset: Int = 0
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        for vertexAttribute in TFSVertexAttributes.allCases {
            addAttributeWithOffset(format: getFormatForVertexAttribute(vertexAttribute), bufferIndex: 0)
        }
        
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}

public struct PositionOnlyVertexDescriptor: VertexDescriptor {
    var name: String = "Position Only Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var bufferIndex: Int = 0
    var offset: Int = 0
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        addAttributeWithOffset(format: getFormatForVertexAttribute(TFSVertexAttributePosition), bufferIndex: 0)
        vertexDescriptor.layouts[0].stride = float4.stride
    }
}

public struct SkyboxVertexDescriptor: VertexDescriptor {
    var name: String = "Skybox Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var bufferIndex: Int = 0
    var offset: Int = 0
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        addAttribute(attributeIdx: 0,
                     format: .float3,
                     bufferIndex: 0,
                     m_offset: 0)

        addAttribute(attributeIdx: 1,
                     format: .float3,
                     bufferIndex: 0,
                     m_offset: getOffsetForFormat(.float3))

        vertexDescriptor.layouts[0].stride = 36
    }
}
