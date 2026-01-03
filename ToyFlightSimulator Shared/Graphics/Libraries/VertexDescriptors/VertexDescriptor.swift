//
//  VertexDescriptor.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

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
        case .ushort4:
            return simd_ushort4.size
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
            case TFSVertexAttributeJoints:
                return .ushort4
            case TFSVertexAttributeJointWeights:
                return .float4
            default:
                return .float3
        }
    }
}
