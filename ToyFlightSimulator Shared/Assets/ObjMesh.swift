//
//  ObjMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

class ObjMesh: Mesh {
//    init(_ modelName: String) {
//        super.init()
//        
//        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: MeshExtension.OBJ.rawValue) else {
//            fatalError("Asset \(modelName) does not exist.")
//        }
//        
//        let descriptor = Mesh.createMdlVertexDescriptor()
//    
//        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
//    
//        let asset = MDLAsset(url: assetUrl,
//                             vertexDescriptor: descriptor,
//                             bufferAllocator: bufferAllocator,
//                             preserveTopology: false,
//                             error: nil)
//        
//        asset.loadTextures()
//        
//        let object0 = asset.object(at: 0)
//        if let objMesh = object0 as? MDLMesh {
//            objMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.0)
//            
//            let vertexData = objMesh.vertexBuffers[0].map().bytes.bindMemory(to: Vertex.self, capacity: objMesh.vertexCount)
//            _vertices = Array(UnsafeBufferPointer(start: vertexData, count: objMesh.vertexCount))
//            _vertexBuffer = (objMesh.vertexBuffers[0] as! MTKMeshBuffer).buffer
//            
//            _childMeshes.append(contentsOf: ObjMesh.makeMeshes(object: objMesh, vertexDescriptor: descriptor))
//
////            guard let submeshes = objMesh.submeshes,
////                    let first = submeshes.firstObject,
////                    let sub: MDLSubmesh = first as? MDLSubmesh else { return }
////            let indexDataPtr = sub.indexBuffer(asIndexType: .uInt32).map().bytes.bindMemory(to: UInt32.self,
////                                                                                            capacity: sub.indexCount)
////            let indexData = Array(UnsafeBufferPointer(start: indexDataPtr, count: sub.indexCount))
//            
//        }
//    }
    
    init(_ modelName: String) {
        super.init()
        
        guard let assetUrl = Bundle.main.url(forResource: modelName, withExtension: MeshExtension.OBJ.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let descriptor = Mesh.createMdlVertexDescriptor()
    
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
    
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: bufferAllocator,
                             preserveTopology: false,
                             error: nil)
        
        print("[ObjMesh init] Created asset: \(asset)")
        asset.loadTextures()
        print("[ObjMesh init] Loaded asset textures")
        
        for i in 0..<asset.count {
            let child = asset.object(at: i)
            print("[ObjMesh init] \(modelName) child name: \(child.name)")
            _childMeshes.append(contentsOf: ObjMesh.makeMeshes(object: child, vertexDescriptor: descriptor))
        }
        
        invertMeshZ()
    }
    
    private static func makeMeshes(object: MDLObject, vertexDescriptor: MDLVertexDescriptor) -> [Mesh] {
        var meshes = [Mesh]()
        
        print("[ObjMesh makeMeshes] object named \(object.name): \(object)")
        
        if let mesh = object as? MDLMesh {
            print("[ObjMesh makeMeshes] object named \(object.name) is MDLMesh")
            let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
            meshes.append(newMesh)
        }
        
        for child in object.children.objects {
            let childMeshes = ObjMesh.makeMeshes(object: child, vertexDescriptor: vertexDescriptor)
            meshes.append(contentsOf: childMeshes)
        }
        
        return meshes
    }
    
    private func invertMeshZ() {
        for mesh in _childMeshes {
            let vertexBuffer = mesh._vertexBuffer!
            let count = vertexBuffer.length / Vertex.stride
            var pointer = vertexBuffer.contents().bindMemory(to: Vertex.self, capacity: count)
            for _ in 0..<count {
                pointer.pointee.position.z = -pointer.pointee.position.z
                pointer = pointer.advanced(by: 1)
            }
        }
    }
}
