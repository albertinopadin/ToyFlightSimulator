//
//  MDLVertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 11/30/22.
//

import MetalKit

enum MDLVertexDescriptorType {
    case Base
}

final class MDLVertexDescriptorLibrary: Library<MDLVertexDescriptorType, MDLVertexDescriptor>, @unchecked Sendable {
    private var _library: [MDLVertexDescriptorType: MDLVertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseMDLVertexDescriptor().mdlVertexDescriptor, forKey: .Base)
    }
    
    override subscript(type: MDLVertexDescriptorType) -> MDLVertexDescriptor {
        return _library[type]!
    }
}

public struct BaseMDLVertexDescriptor {
    let name: String = "Base MDL Vertex Descriptor"
    var mdlVertexDescriptor: MDLVertexDescriptor
    var attributeIndex: Int = 0
    var offset: Int = 0
    
    init() {
        let vertexBufferIdx = TFSBufferIndexMeshVertex.index
        
        mdlVertexDescriptor = MDLVertexDescriptor()
        
        // Position
        addAttribute(name: MDLVertexAttributePosition, format: .float3, bufferIndex: vertexBufferIdx)
        
        // Color
        addAttribute(name: MDLVertexAttributeColor, format: .float4, bufferIndex: vertexBufferIdx)
        
        // Texture Coordinate
        addAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, bufferIndex: vertexBufferIdx)
        
        // Normal
        addAttribute(name: MDLVertexAttributeNormal, format: .float3, bufferIndex: vertexBufferIdx)
        
        // Tangent
        addAttribute(name: MDLVertexAttributeTangent, format: .float3, bufferIndex: vertexBufferIdx)
        
        // Bitangent
        addAttribute(name: MDLVertexAttributeBitangent, format: .float3, bufferIndex: vertexBufferIdx)
        
        // Joint Indices
        addAttribute(name: MDLVertexAttributeJointIndices, format: .uShort4, bufferIndex: vertexBufferIdx)
        
        // Joint Weights
        addAttribute(name: MDLVertexAttributeJointWeights, format: .float4, bufferIndex: vertexBufferIdx)
        
        (mdlVertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride = Vertex.stride
    }
    
    mutating func addAttribute(name: String, format: MDLVertexFormat, bufferIndex: Int) {
        (mdlVertexDescriptor.attributes[attributeIndex] as! MDLVertexAttribute).name = name
        (mdlVertexDescriptor.attributes[attributeIndex] as! MDLVertexAttribute).format = format
        (mdlVertexDescriptor.attributes[attributeIndex] as! MDLVertexAttribute).bufferIndex = bufferIndex
        (mdlVertexDescriptor.attributes[attributeIndex] as! MDLVertexAttribute).offset = offset
        offset += getOffsetForFormat(format)
        attributeIndex += 1
    }
    
    func getOffsetForFormat(_ format: MDLVertexFormat) -> Int {
        switch format {
        case .float2:
            return float3.size  // Use float3 because of padding (???)
        case .float3:
            return float3.size
        case .float4:
            return float4.size
        case .uShort4:
            return simd_ushort4.size
        default:
            return float4.size
        }
    }
}

