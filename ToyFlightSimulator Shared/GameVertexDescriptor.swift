//
//  VertexDescriptorUtil.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/27/22.
//

import Metal
import MetalKit

struct GameVertexDescriptor {
    let sizeOfInt = MemoryLayout<Int>.size
    let sizeOfFloat = MemoryLayout<Float>.size
    let unknownFormatSize = MemoryLayout<SIMD4<Float>>.size
    
    let mdlVertexDescriptor = MDLVertexDescriptor()
    private var attributeIdx: Int = 0
    private var attributeOffset: Int = 0
    private var bufferIdx: Int = 0
    private var layoutIdx: Int = 0
    
    mutating func addAttribute(name: String, format: MDLVertexFormat) {
        mdlVertexDescriptor.attributes[attributeIdx] = MDLVertexAttribute(name: name,
                                                                          format: format,
                                                                          offset: attributeOffset,
                                                                          bufferIndex: bufferIdx)
        attributeIdx += 1
        attributeOffset += getFormatSize(format)
        mdlVertexDescriptor.layouts[layoutIdx] = MDLVertexBufferLayout(stride: attributeOffset)
    }
    
    func getFormatSize(_ format: MDLVertexFormat) -> Int {
        switch format {
            case .float:
                return sizeOfFloat
            
            case .float2:
                return sizeOfFloat * 2
            
            case .float3:
                return sizeOfFloat * 3
            
            case .float4:
                return sizeOfFloat * 4
            
            case .int:
                return sizeOfInt
                
            case .int2:
                return sizeOfInt * 2
                
            case .int3:
                return sizeOfInt * 3
                
            case .int4:
                return sizeOfInt * 4
                
            default:
                return unknownFormatSize
        }
    }
}
