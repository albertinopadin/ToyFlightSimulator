//
//  VertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

extension TFSVertexAttributes: CaseIterable {
    // allCases must return sorted to make adding vertex attributes easy:
    public static var allCases: [TFSVertexAttributes] {
        return [
            TFSVertexAttributePosition,
            TFSVertexAttributeTexcoord,
            TFSVertexAttributeNormal,
            TFSVertexAttributeTangent,
            TFSVertexAttributeBitangent,
            TFSVertexAttributeColor
        ].sorted(by: { $0.rawValue < $1.rawValue })
    }
}

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
    mutating func addAttribute(attributeIdx: Int, format: MTLVertexFormat, bufferIndex: Int, m_offset: Int)
    mutating func addAttributeWithOffset(format: MTLVertexFormat, bufferIndex: Int)
}

// Structs can't inherit defined methods, they can only implement protocols,
// so extracting out common functionality into an extension. Definitely feels janky tho...
extension VertexDescriptor {
    mutating func addAttribute(attributeIdx: Int, format: MTLVertexFormat, bufferIndex: Int, m_offset: Int) {
        vertexDescriptor.attributes[attributeIdx].format = format
        vertexDescriptor.attributes[attributeIdx].bufferIndex = bufferIndex
        vertexDescriptor.attributes[attributeIdx].offset = m_offset
    }
    
    mutating func addAttributeWithOffset(format: MTLVertexFormat, bufferIndex: Int) {
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
    
    func getFormatForVertexAttribute(_ vertexAttribute: TFSVertexAttributes) -> MTLVertexFormat {
        switch vertexAttribute {
            case TFSVertexAttributeTexcoord:
                return .float2
            case TFSVertexAttributePosition, TFSVertexAttributeNormal, TFSVertexAttributeTangent, TFSVertexAttributeBitangent:
                return .float3
            case TFSVertexAttributeColor:
                return .float4
            default:
                return .float3
        }
    }
}

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
