//
//  VertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum VertexDescriptorType {
    case Base
}

class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor> {
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseVertexDescriptor(), forKey: .Base)
    }
    
    override subscript(type: VertexDescriptorType) -> MTLVertexDescriptor {
        return _library[type]!.vertexDescriptor
    }
}

protocol VertexDescriptor {
    var name: String { get }
    var vertexDescriptor: MTLVertexDescriptor! { get }
}

public struct BaseVertexDescriptor: VertexDescriptor {
    var name: String = "Base Vertex Descriptor"
    
    var vertexDescriptor: MTLVertexDescriptor!
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        // TODO: This can be error prone, if you forget to change the attribute index.
        //       Maybe refactor into a stateful 'addAttribute(format, index, offset)' method?
        
        var offset: Int = 0
        
        // Position
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = offset
        offset += float3.size
        
        // Color
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].offset = offset
        offset += float4.size
        
        // Texture Coordinate
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[2].offset = offset
        offset += float3.size  // Use float3 because of padding
        
        // Normal
        vertexDescriptor.attributes[3].format = .float3
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.attributes[3].offset = offset
        offset += float3.size
        
        // Tangent
        vertexDescriptor.attributes[4].format = .float3
        vertexDescriptor.attributes[4].bufferIndex = 0
        vertexDescriptor.attributes[4].offset = offset
        offset += float3.size
        
        // Bitangent
        vertexDescriptor.attributes[5].format = .float3
        vertexDescriptor.attributes[5].bufferIndex = 0
        vertexDescriptor.attributes[5].offset = offset
        offset += float3.size
        
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}
