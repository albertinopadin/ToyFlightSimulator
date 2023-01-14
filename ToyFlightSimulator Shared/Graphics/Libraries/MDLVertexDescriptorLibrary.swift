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

class MDLVertexDescriptorLibrary: Library<MDLVertexDescriptorType, MDLVertexDescriptor> {
    private var _library: [MDLVertexDescriptorType: MDLVertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseMDLVertexDescriptor().mdlVertexDescriptor, forKey: .Base)
    }
    
    override subscript(type: MDLVertexDescriptorType) -> MDLVertexDescriptor {
        return _library[type]!
    }
}

public struct BaseMDLVertexDescriptor {
    var name: String = "Base MDL Vertex Descriptor"
    
    var mdlVertexDescriptor: MDLVertexDescriptor!
    var attributeIndex: Int = 0
    var offset: Int = 0
    
    init() {
        mdlVertexDescriptor = MDLVertexDescriptor()
        
        // Position
        addAttribute(name: MDLVertexAttributePosition, format: .float3, bufferIndex: 0)
        
        // Color
        addAttribute(name: MDLVertexAttributeColor, format: .float4, bufferIndex: 0)
        
        // Texture Coordinate
        addAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, bufferIndex: 0)
        
        // Normal
        addAttribute(name: MDLVertexAttributeNormal, format: .float3, bufferIndex: 0)
        
        // Tangent
        addAttribute(name: MDLVertexAttributeTangent, format: .float3, bufferIndex: 0)
        
        // Bitangent
        addAttribute(name: MDLVertexAttributeBitangent, format: .float3, bufferIndex: 0)
        
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
        default:
            return float4.size
        }
    }
}

