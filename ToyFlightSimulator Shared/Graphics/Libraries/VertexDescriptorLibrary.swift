//
//  VertexDescriptorLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

extension TFSBaseVertexAttributes: CaseIterable {
    // allCases must return sorted to make adding vertex attributes easy:
    public static var allCases: [TFSBaseVertexAttributes] {
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

extension TFSGltfVertexAttributes: CaseIterable {
    public static var allCases: [TFSGltfVertexAttributes] {
        return [
            TFSGltfVertexAttributePosition,
            TFSGltfVertexAttributeTexcoord,
            TFSGltfVertexAttributeNormal,
            TFSGltfVertexAttributeTangent,
            TFSGltfVertexAttributeBitangent,
            TFSGltfVertexAttributeColor
        ].sorted(by: { $0.rawValue < $1.rawValue })
    }
}

enum VertexDescriptorType {
    case Base
    case USD
    case GLTF
    case Skybox
}

class VertexDescriptorLibrary: Library<VertexDescriptorType, MTLVertexDescriptor> {
    private var _library: [VertexDescriptorType: VertexDescriptor] = [:]
    
    override func makeLibrary() {
        _library.updateValue(BaseVertexDescriptor(), forKey: .Base)
        _library.updateValue(UsdVertexDescriptor(), forKey: .USD)
        _library.updateValue(GltfVertexDescriptor(), forKey: .GLTF)
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
    var bufferIndex: Int { get set }
    var offset: Int { get set }
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
    
    mutating func addAttributeWithLayoutStride(format: MTLVertexFormat) {
        self.addAttribute(attributeIdx: attributeIndex, format: format, bufferIndex: bufferIndex, m_offset: 0)
//        vertexDescriptor.layouts[bufferIndex].stride = getOffsetForFormat(format)
        vertexDescriptor.layouts[bufferIndex].stride = getStrideForFormat(format)
        attributeIndex += 1
        bufferIndex += 1
    }
    
    func getFormatForBaseVertexAttribute(_ vertexAttribute: TFSBaseVertexAttributes) -> MTLVertexFormat {
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
    
    func getFormatForGltfVertexAttribute(_ vertexAttribute: TFSGltfVertexAttributes) -> MTLVertexFormat {
        switch vertexAttribute {
            case TFSGltfVertexAttributeTexcoord:
                return .float2
            case TFSGltfVertexAttributePosition, TFSGltfVertexAttributeNormal, TFSGltfVertexAttributeTangent, TFSGltfVertexAttributeBitangent:
                return .float3
            case TFSGltfVertexAttributeColor:
                return .float4
            default:
                return .float3
        }
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
    
    func getStrideForFormat(_ format: MTLVertexFormat) -> Int {
        switch format {
        case .float2:
            return float2.stride
        case .float3:
            return float3.stride
        case .float4:
            return float4.stride
        default:
            return float4.stride
        }
    }
}

public struct BaseVertexDescriptor: VertexDescriptor {
    var name: String = "Base Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var bufferIndex: Int = 0
    var offset: Int = 0
    
//    init() {
//        vertexDescriptor = MTLVertexDescriptor()
//        
//        // Position
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Color
//        addAttributeWithOffset(format: .float4, bufferIndex: 0)
//        
//        // Texture Coordinate
//        addAttributeWithOffset(format: .float2, bufferIndex: 0)
//        
//        // Normal
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Tangent
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Bitangent
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        vertexDescriptor.layouts[0].stride = Vertex.stride
//    }
    
//    init() {
//        vertexDescriptor = MTLVertexDescriptor()
//        
//        // Normal
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Texture Coordinate
//        addAttributeWithOffset(format: .float2, bufferIndex: 0)
//        
//        // Position
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Color
//        addAttributeWithOffset(format: .float4, bufferIndex: 0)
//        
//        // Tangent
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Bitangent
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        vertexDescriptor.layouts[0].stride = Vertex.stride
//    }
    
//    init() {
//        vertexDescriptor = MTLVertexDescriptor()
//        
//        // Position
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Texture Coordinate
//        addAttributeWithOffset(format: .float2, bufferIndex: 0)
//        
//        // Normal
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Tangent
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Bitangent
//        addAttributeWithOffset(format: .float3, bufferIndex: 0)
//        
//        // Color
//        addAttributeWithOffset(format: .float4, bufferIndex: 0)
//        
//        vertexDescriptor.layouts[0].stride = Vertex.stride
//    }
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        print("[BaseVertexDescriptor init] TFSBaseVertexAttributes.allCases: \(TFSBaseVertexAttributes.allCases)")
        for vertexAttribute in TFSBaseVertexAttributes.allCases {
            addAttributeWithOffset(format: getFormatForBaseVertexAttribute(vertexAttribute), bufferIndex: 0)
        }
        
        vertexDescriptor.layouts[0].stride = Vertex.stride
    }
}

public struct UsdVertexDescriptor: VertexDescriptor {
    var name: String = "USD Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var bufferIndex: Int = 0
    var offset: Int = 0
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        // Position
        addAttributeWithLayoutStride(format: .float3)
        
        // Texcoord
        addAttributeWithLayoutStride(format: .float2)
        
        // Normal
        addAttributeWithLayoutStride(format: .float3)
    }
}

public struct GltfVertexDescriptor: VertexDescriptor {
    var name: String = "GLTF Vertex Descriptor"
    var vertexDescriptor: MTLVertexDescriptor!
    var attributeIndex: Int = 0
    var bufferIndex: Int = 0
    var offset: Int = 0
    
//    init() {
//        vertexDescriptor = MTLVertexDescriptor()
//        // Normal
//        addAttributeWithLayoutStride(format: .float3)
//        
//        // Texcoord
//        addAttributeWithLayoutStride(format: .float2)
//        
//        // Position
//        addAttributeWithLayoutStride(format: .float3)
//    }
    
//    init() {
//        vertexDescriptor = MTLVertexDescriptor()
//        
//        // Position
//        addAttributeWithLayoutStride(format: .float3)
//        
//        // Normal
//        addAttributeWithLayoutStride(format: .float3)
//        
//        // Texcoord
//        addAttributeWithLayoutStride(format: .float2)
//    }
    
    init() {
        vertexDescriptor = MTLVertexDescriptor()
        
        for vertexAttribute in TFSGltfVertexAttributes.allCases {
            let idx = Int(vertexAttribute.rawValue)
            let format = getFormatForGltfVertexAttribute(vertexAttribute)
            addAttribute(attributeIdx: idx,
                         format: format,
                         bufferIndex: idx,
                         m_offset: 0)
            vertexDescriptor.layouts[idx].stride = getStrideForFormat(format)
        }
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
        
        // Position
//        addAttribute(format: .float3, bufferIndex: 0)
//
//        // Normal
//        addAttribute(format: .float3, bufferIndex: 0)
//
//        vertexDescriptor.layouts[0].stride = 24
        
//        let position = vertexDescriptor.attributes[Int(TFSVertexAttributePosition.rawValue)]!
//        position.format = .float3
//        position.offset = 0
//        position.bufferIndex = Int(TFSBufferIndexMeshPositions.rawValue)
//        
//        vertexDescriptor.layouts[Int(TFSBufferIndexMeshPositions.rawValue)].stride = 12
//        
//        let normals = vertexDescriptor.attributes[Int(TFSVertexAttributeNormal.rawValue)]!
//        normals.format = .float3
//        normals.offset = 0
//        normals.bufferIndex = Int(TFSBufferIndexMeshGenerics.rawValue)
//        
//        vertexDescriptor.layouts[Int(TFSBufferIndexMeshGenerics.rawValue)].stride = 12
        
//        attributeIndex = 2
        
//        addAttribute(attributeIdx: Int(TFSVertexAttributePosition.rawValue),
//                     format: .float3,
//                     bufferIndex: Int(TFSBufferIndexMeshPositions.rawValue),
//                     m_offset: 0)
//        vertexDescriptor.layouts[Int(TFSBufferIndexMeshPositions.rawValue)].stride = 12
//
//        addAttribute(attributeIdx: Int(TFSVertexAttributeNormal.rawValue),
//                     format: .float3,
//                     bufferIndex: Int(TFSBufferIndexMeshGenerics.rawValue),
//                     m_offset: 0)
//        vertexDescriptor.layouts[Int(TFSBufferIndexMeshGenerics.rawValue)].stride = 12
        
//        addAttribute(attributeIdx: 0,
//                     format: .float3,
//                     bufferIndex: 0,
//                     m_offset: 0)
//        vertexDescriptor.layouts[0].stride = 12
//
//        addAttribute(attributeIdx: 1,
//                     format: .float3,
//                     bufferIndex: 1,
//                     m_offset: 0)
//        vertexDescriptor.layouts[1].stride = 12
        
        addAttribute(attributeIdx: 0,
                     format: .float3,
                     bufferIndex: 0,
                     m_offset: 0)

        addAttribute(attributeIdx: 1,
                     format: .float3,
                     bufferIndex: 0,
                     m_offset: getOffsetForFormat(.float3))

        vertexDescriptor.layouts[0].stride = 36
//
//        attributeIndex = 2
//        offset = getOffsetForFormat(.float3) * 2
//        print("Skybox Vertex Descriptor offset: \(offset)")
        
//        addAttribute(attributeIdx: 0,
//                     format: .float3,
//                     bufferIndex: 0,
//                     m_offset: 0)
//        vertexDescriptor.layouts[0].stride = 16
//
//        addAttribute(attributeIdx: 1,
//                     format: .float3,
//                     bufferIndex: 1,
//                     m_offset: 0)
//        vertexDescriptor.layouts[1].stride = 16
//
//        attributeIndex = 2
//        offset = getOffsetForFormat(.float3) * 2
    }
}
