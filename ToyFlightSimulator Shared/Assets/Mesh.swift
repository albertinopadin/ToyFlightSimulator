//
//  Mesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit

// Vertex Information
class Mesh {
    public var name: String = "Mesh"
    private var _vertices: [Vertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    private var _submeshes: [Submesh] = []
    private var _childMeshes: [Mesh] = []
    var metalKitMesh: MTKMesh? = nil
    
    init() {
        createMesh()
        createBuffer()
    }
    
    init(modelName: String) {
        name = modelName
        createMeshFromModel(modelName)
    }
    
    init(mdlMesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor) {
        name = mdlMesh.name
        
        mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                normalAttributeNamed: MDLVertexAttributeNormal,
                                tangentAttributeNamed: MDLVertexAttributeTangent)
        
        mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                tangentAttributeNamed: MDLVertexAttributeTangent,
                                bitangentAttributeNamed: MDLVertexAttributeBitangent)
        
        mdlMesh.vertexDescriptor = vertexDescriptor
        do {
            metalKitMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
            if metalKitMesh!.vertexBuffers.count > 1 {
                print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
            }
            self._vertexBuffer = metalKitMesh!.vertexBuffers[0].buffer
            self._vertexCount = metalKitMesh!.vertexCount
            for i in 0..<metalKitMesh!.submeshes.count {
                let mtkSubmesh = metalKitMesh!.submeshes[i]
                let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
                addSubmesh(submesh)
            }
        } catch {
            print("ERROR::LOADING_MDLMESH::__::\(error.localizedDescription)")
        }
        
        print("Num submeshes for \(mdlMesh.name): \(_submeshes.count)")
    }
    
    init(mtkMesh: MTKMesh, mdlMesh: MDLMesh, addTangentBases: Bool = true) {
        name = mtkMesh.name
        
        if addTangentBases {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    normalAttributeNamed: MDLVertexAttributeNormal,
                                    tangentAttributeNamed: MDLVertexAttributeTangent)
            
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    tangentAttributeNamed: MDLVertexAttributeTangent,
                                    bitangentAttributeNamed: MDLVertexAttributeBitangent)
        }
        
        self.metalKitMesh = mtkMesh
        if metalKitMesh!.vertexBuffers.count > 1 {
            print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
        }
    }
    
    func createMesh() { }
    
    private func createBuffer() {
        if _vertices.count > 0 {
            _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices,
                                                     length: Vertex.stride(_vertices.count),
                                                     options: [])
        }
    }
    
    private static func makeMeshes(object: MDLObject, vertexDescriptor: MDLVertexDescriptor) -> [Mesh] {
        var meshes = [Mesh]()
        
        if let mesh = object as? MDLMesh {
            print("[makeMeshes] object is MDLMesh")
            let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
            meshes.append(newMesh)
        }
        
        if object.conforms(to: MDLObjectContainerComponent.self) {
            print("[makeMeshes] object conforms to MDLObjectContainerComponent and has \(object.children.objects.count) children")
            for child in object.children.objects {
                let childMeshes = makeMeshes(object: child, vertexDescriptor: vertexDescriptor)
                meshes.append(contentsOf: childMeshes)
            }
        }
        
        return meshes
    }
    
    private func createMeshFromModel(_ modelName: String, ext: String = "obj") {
        print("[createMeshFromModel] model name: \(modelName)")
        
        guard let assetURL = Bundle.main.url(forResource: modelName, withExtension: ext) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Base])
        descriptor.attribute(TFSVertexAttributePosition.rawValue).name  = MDLVertexAttributePosition
        descriptor.attribute(TFSVertexAttributeColor.rawValue).name     = MDLVertexAttributeColor
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name  = MDLVertexAttributeTextureCoordinate
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).name    = MDLVertexAttributeNormal
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).name   = MDLVertexAttributeTangent
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name = MDLVertexAttributeBitangent
        
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
        let asset: MDLAsset = MDLAsset(url: assetURL,
                                       vertexDescriptor: descriptor,
                                       bufferAllocator: bufferAllocator,
                                       preserveTopology: false,
                                       error: nil)
        asset.loadTextures()
        
        for child in asset.childObjects(of: MDLObject.self) {
            print("[createMeshFromModel] \(modelName) child name: \(child.name)")
            _childMeshes = Mesh.makeMeshes(object: child, vertexDescriptor: descriptor)
        }
        
        print("Num child meshes for \(modelName): \(_childMeshes.count)")
        for cm in _childMeshes {
            print("Mesh named \(name); Child mesh name: \(cm.name)")
            for sm in cm._submeshes {
                print("Child mesh \(cm.name); Submesh name: \(sm.name)")
            }
        }
    }
    
    func setInstanceCount(_ count: Int) {
        self._instanceCount = count
    }
    
    func addSubmesh(_ submesh: Submesh) {
        _submeshes.append(submesh)
    }
    
    func addVertex(position: float3,
                   color: float4 = float4(1, 0, 1, 1),
                   textureCoordinate: float2 = float2(0, 0),
                   normal: float3 = float3(0, 1, 0),
                   tangent: float3 = float3(1, 0, 0),
                   bitangent: float3 = float3(0, 0, 1)) {
        _vertices.append(Vertex(position: position,
                                color: color,
                                textureCoordinate: textureCoordinate,
                                normal: normal,
                                tangent: tangent,
                                bitangent: bitangent))
    }
    
    func applyMaterial(renderCommandEncoder: MTLRenderCommandEncoder, material: Material?) {
        var mat = material
        renderCommandEncoder.setFragmentBytes(&mat, length: Material.stride, index: Int(TFSBufferIndexMaterial.rawValue))
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        material: Material? = nil,
                        applyMaterials: Bool = true,
                        baseColorTextureType: TextureType = .None,
                        normalMapTextureType: TextureType = .None,
                        specularTextureType: TextureType = .None) {
        if let _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                for submesh in _submeshes {
                    if applyMaterials {
                        submesh.applyTextures(renderCommandEncoder: renderCommandEncoder,
                                              customBaseColorTextureType: baseColorTextureType,
                                              customNormalMapTextureType: normalMapTextureType,
                                              customSpecularTextureType: specularTextureType)
                        submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
                    }
                    
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                               indexCount: submesh.indexCount,
                                                               indexType: submesh.indexType,
                                                               indexBuffer: submesh.indexBuffer,
                                                               indexBufferOffset: submesh.indexBufferOffset,
                                                               instanceCount: _instanceCount)
                }
            } else {
                if applyMaterials, let material {
                    applyMaterial(renderCommandEncoder: renderCommandEncoder, material: material)
                }
                
                renderCommandEncoder.drawPrimitives(type: .triangle,
                                                    vertexStart: 0,
                                                    vertexCount: _vertices.count,
                                                    instanceCount: _instanceCount)
            }
        }
        
        for child in _childMeshes {
            child.drawPrimitives(renderCommandEncoder,
                                 material: material,
                                 applyMaterials: applyMaterials,
                                 baseColorTextureType: baseColorTextureType,
                                 normalMapTextureType: normalMapTextureType,
                                 specularTextureType: specularTextureType)
        }
    }
    
    func drawShadowPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder) {
        if let _vertexBuffer = _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                for submesh in _submeshes {
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                               indexCount: submesh.indexCount,
                                                               indexType: submesh.indexType,
                                                               indexBuffer: submesh.indexBuffer,
                                                               indexBufferOffset: submesh.indexBufferOffset,
                                                               instanceCount: _instanceCount)
                }
            } else {
                renderCommandEncoder.drawPrimitives(type: .triangle,
                                                    vertexStart: 0,
                                                    vertexCount: _vertices.count,
                                                    instanceCount: _instanceCount)
            }
        }
        
        for child in _childMeshes {
            child.drawShadowPrimitives(renderCommandEncoder)
        }
    }
}
