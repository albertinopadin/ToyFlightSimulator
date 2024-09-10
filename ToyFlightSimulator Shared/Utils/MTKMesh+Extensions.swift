//
//  MTKMesh+Extensions.swift
//  ToyFlightSimulator iOS
//
//  Created by Albertino Padin on 9/10/24.
//

import MetalKit

extension MTKMesh {
    public func invertNormals<T: HasNormal>(vertexType: T.Type) {
        let vertexLayoutStride = (self.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        for meshBuffer in self.vertexBuffers {
            for i in 0..<self.vertexCount {
                let vertexPosition = (i * vertexLayoutStride)
                let vertexPtr = meshBuffer.buffer.contents()
                                                 .advanced(by: vertexPosition)
                                                 .bindMemory(to: vertexType.self, capacity: 1)
                var vertexValue: T = vertexPtr.pointee
                vertexValue.normal = -vertexValue.normal
                vertexPtr.pointee = vertexValue
            }
        }
    }
}
