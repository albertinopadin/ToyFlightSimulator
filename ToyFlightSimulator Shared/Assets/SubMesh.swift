//
//  SubMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit

class Submesh {
    public var name: String = "Submesh"
    public var material: Material?
    public var parentMesh: Mesh?
    
    private var _indices: [UInt32] = []
    
    private var _indexCount: Int = 0
    public var indexCount: Int { return _indexCount }
    
    private var _indexBuffer: MTLBuffer!
    public var indexBuffer: MTLBuffer { return _indexBuffer }
    
    private var _primitiveType: MTLPrimitiveType = .triangle
    public var primitiveType: MTLPrimitiveType { return _primitiveType }
    
    private var _indexType: MTLIndexType = .uint32
    public var indexType: MTLIndexType { return _indexType }
    
    private var _indexBufferOffset: Int = 0
    public var indexBufferOffset: Int { return _indexBufferOffset }
    
    init(indices: [UInt32]) {
        self._indices = indices
        self._indexCount = indices.count
        createIndexBuffer()
    }
    
    init(mtkSubmesh: MTKSubmesh, mdlSubmesh: MDLSubmesh, name: String? = nil) {
        _indexBuffer = mtkSubmesh.indexBuffer.buffer
        _indexBufferOffset = mtkSubmesh.indexBuffer.offset
        _indexCount = mtkSubmesh.indexCount
        _indexType = mtkSubmesh.indexType
        _primitiveType = mtkSubmesh.primitiveType
        
        if let name {
            self.name = name
        } else {
            self.name = mtkSubmesh.name
        }
        print("[Submesh init] Creating textures and material for \(self.name)")
        if let submeshMaterial = mdlSubmesh.material {
            material = Material(submeshMaterial)
        }
    }
    
    private func createIndexBuffer() {
        if _indices.count > 0 {
            _indexBuffer = Engine.Device.makeBuffer(bytes: _indices,
                                                    length: UInt32.stride(_indices.count),
                                                    options: [])
        }
    }
}

