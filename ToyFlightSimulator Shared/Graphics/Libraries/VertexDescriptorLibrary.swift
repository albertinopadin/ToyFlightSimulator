//
//  VertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum VertexDescriptorType {
    case Base
    case Skybox
}

class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor> {
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseVertexDescriptor(), forKey: .Base)
        _library.updateValue(SkyboxVertexDescriptor(), forKey: .Skybox)
    }
    
    override subscript(type: VertexDescriptorType) -> MTLVertexDescriptor {
        return _library[type]!.vertexDescriptor
    }
}

protocol VertexDescriptor {
    var name: String { get }
    var vertexDescriptor: MTLVertexDescriptor! { get }
    var attributeIndex: Int { get set }
    var offset: Int { get set }
    mutating func addAttribute(format: MTLVertexFormat, bufferIndex: Int)
}

// Structs can't inherit defined methods, they can only implement protocols,
// so extracting out common functionality into an extension. Definitely feels janky tho...
extension VertexDescriptor {
    mutating func addAttribute(format: MTLVertexFormat, bufferIndex: Int) {
        vertexDescriptor.attributes[attributeIndex].format = format
        vertexDescriptor.attributes[attributeIndex].bufferIndex = bufferIndex
        vertexDescriptor.attributes[attributeIndex].offset = offset
        offset += getOffsetForFormat(format)
        attributeIndex += 1
    }
    
    func getOffsetForFormat(_ format: MTLVertexFormat) -> Int {
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

public struct BaseVertexDescriptor: VertexDescriptor {
    var name: String = "Base Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var offset: Int = 0
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        // Position
        addAttribute(format: .float3, bufferIndex: 0)
        
        // Color
        addAttribute(format: .float4, bufferIndex: 0)
        
        // Texture Coordinate
        addAttribute(format: .float2, bufferIndex: 0)
        
        // Normal
        addAttribute(format: .float3, bufferIndex: 0)
        
        // Tangent
        addAttribute(format: .float3, bufferIndex: 0)
        
        // Bitangent
        addAttribute(format: .float3, bufferIndex: 0)
        
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}

public struct SkyboxVertexDescriptor: VertexDescriptor {
    var name: String = "Skybox Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var offset: Int = 0
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        // Position
        addAttribute(format: .float3, bufferIndex: 0)
        
        // Normal
        addAttribute(format: .float3, bufferIndex: 0)
        
        vertexDescriptor.layouts[0].stride = 12
    }
}
