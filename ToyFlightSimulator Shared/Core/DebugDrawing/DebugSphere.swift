//
//  Sphere.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 10/24/22.
//

import MetalKit

class DebugSphere: DebugDrawing {
    private var mesh: MTKMesh!
    private var color: float4
    
    init(name: String, position: float3, radius: Float, color: float4 = BLUE_COLOR) {
        let diameter = radius * 2
        self.color = color
        let allocator = MTKMeshBufferAllocator(device: Engine.Device)
        let mdlSphere = MDLMesh(sphereWithExtent: float3(diameter, diameter, diameter),
                                segments: SIMD2<UInt32>(100, 100),
                                inwardNormals: false,
                                geometryType: .triangles,
                                allocator: allocator)
        print("mdlSphere.vertexDescriptor before: \(mdlSphere.vertexDescriptor)")
//        mdlSphere.addAttribute(withName: MDLVertexAttributeColor,
//                               format: .float4,
//                               type: MDLVertexAttributeColor,
//                               data: withUnsafeBytes(of: &self.color, { Data($0) }),
//                               stride: float4.stride)
//        mdlSphere.addAttribute(withName: MDLVertexAttributeColor,
//                               format: .float4)
//        mdlSphere.vertexDescriptor.addOrReplaceAttribute(MDLVertexAttribute(name: MDLVertexAttributeColor,
//                                                                      format: .float4,
//                                                                      offset: 12,
//                                                                      bufferIndex: 0))
//        mdlSphere.removeAttributeNamed(MDLVertexAttributeNormal)
//        mdlSphere.removeAttributeNamed(MDLVertexAttributeTextureCoordinate)
//        (mdlSphere.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride += float4.stride
        
//        mdlSphere.addAttribute(withName: MDLVertexAttributeColor,
//                               format: .float4,
//                               type: MDLVertexAttributeColor,
//                               data: withUnsafeBytes(of: &self.color, { Data($0) }),
//                               stride: float4.stride)
        mdlSphere.vertexDescriptor = Graphics.MDLVertexDescriptors[.Base]
        
        print("mdlSphere.vertexDescriptor after: \(mdlSphere.vertexDescriptor)")
        mesh = try! MTKMesh(mesh: mdlSphere, device: Engine.Device)
        print("Mesh vertex buffers: \(mesh.vertexBuffers.count)")
        print("Mesh vertex count: \(mesh.vertexCount)")
        
        let vertexLayoutStride = (mesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        for meshBuffer in mesh.vertexBuffers {
            for i in 0..<mesh.vertexCount {
                let colorPosition = (i * vertexLayoutStride) + float4.stride
                meshBuffer.buffer.contents().advanced(by: colorPosition).copyMemory(from: &self.color, byteCount: float4.stride)
            }
        }
        
        super.init(name: name)
        self.setPosition(position)
    }
    
    override func doRender(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        super.doRender(renderCommandEncoder)
        
        for (i, meshBuffer) in mesh.vertexBuffers.enumerated() {
//            TODO: add color data to buffer?
//            meshBuffer.fill(withUnsafeBytes(of: &self.color, { Data($0) }), offset: 16)
//            meshBuffer.buffer.contents().advanced(by: float4.stride).copyMemory(from: &self.color, byteCount: float4.stride)
            renderCommandEncoder.setVertexBuffer(meshBuffer.buffer, offset: meshBuffer.offset, index: i)
        }

        for submesh in mesh.submeshes {
            let indexBuffer = submesh.indexBuffer
            renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                       indexCount: submesh.indexCount,
                                                       indexType: submesh.indexType,
                                                       indexBuffer: indexBuffer.buffer,
                                                       indexBufferOffset: indexBuffer.offset)
        }
    }
}
