//
//  ObjMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/13/24.
//

import Foundation
import MetalKit

class ObjMesh: Mesh {
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
        
        for child in asset.childObjects(of: MDLObject.self) {
            print("[ObjMesh init] \(modelName) child name: \(child.name)")
            _childMeshes.append(contentsOf: ObjMesh.makeMeshes(object: child, vertexDescriptor: descriptor))
        }
        
        print("Num child meshes for \(modelName): \(_childMeshes.count)")
        for cm in _childMeshes {
            print("Mesh named \(name); Child mesh name: \(cm.name)")
            for sm in cm._submeshes {
                print("Child mesh \(cm.name); Submesh name: \(sm.name)")
            }
        }
    }
    
    private static func makeMeshes(object: MDLObject, vertexDescriptor: MDLVertexDescriptor) -> [Mesh] {
        var meshes = [Mesh]()
        
        print("[ObjMesh makeMeshes] object named \(object.name): \(object)")
        
        if let mesh = object as? MDLMesh {
            print("[ObjMesh makeMeshes] object named \(object.name) is MDLMesh")
            let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
            meshes.append(newMesh)
        }
        
        if object.conforms(to: MDLObjectContainerComponent.self) {
            print("[ObjMesh makeMeshes] object named \(object.name) conforms to MDLObjectContainerComponent and has \(object.children.objects.count) children")
            for child in object.children.objects {
                let childMeshes = ObjMesh.makeMeshes(object: child, vertexDescriptor: vertexDescriptor)
                meshes.append(contentsOf: childMeshes)
            }
        } else {
            print("[ObjMesh makeMeshes] object \(object.name) does not conform to MDLObjectContainerComponent")
        }
        
        return meshes
    }
}
