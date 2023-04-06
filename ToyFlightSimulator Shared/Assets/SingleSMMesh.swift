//
//  SingleSMMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/5/23.
//

import MetalKit

class SingleSMMesh {
    public var name: String = "SingleSMMesh"
    private var _vertices: [Vertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    private var _submesh: Submesh!
    private var _childMesh: SingleSMMesh!

    init(modelName: String, submeshName: String) {
        name = modelName
        createSingleSMMeshFromModel(modelName: modelName, submeshName: submeshName)
    }

    init(mtkMesh: MTKMesh, submesh: Submesh) {
        name = mtkMesh.name

        if mtkMesh.vertexBuffers.count > 1 {
            print("[SingleSMMesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        _submesh = submesh
    }

    private func createBuffer() {
        if _vertices.count > 0 {
            _vertexBuffer = Engine.Device.makeBuffer(bytes: _vertices,
                                                     length: Vertex.stride(_vertices.count),
                                                     options: [])
        }
    }
    
    private static func getMdlSubmeshNamed(_ submeshName: String, mdlMesh: MDLMesh) -> MDLSubmesh? {
        for i in 0..<mdlMesh.submeshes!.count {
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            if mdlSubmesh.name == submeshName {
                return mdlSubmesh
            }
        }
        
        return nil
    }

    private static func makeSingleSMMeshWithSubmeshNamed(_ submeshName: String,
                                                         object: MDLObject,
                                                         vertexDescriptor: MDLVertexDescriptor) -> SingleSMMesh? {
        if let mesh = object as? MDLMesh {
            if let mdlSubmesh = getMdlSubmeshNamed(submeshName, mdlMesh: mesh) {
                let metalKitMesh = try! MTKMesh(mesh: mesh, device: Engine.Device)
                let mtkSubmesh = metalKitMesh.submeshes.filter({ $0.name == submeshName })[0]
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
                return SingleSMMesh(mtkMesh: metalKitMesh, submesh: submesh)
            }
        }

        if object.conforms(to: MDLObjectContainerComponent.self) {
            for child in object.children.objects {
                if let mesh = makeSingleSMMeshWithSubmeshNamed(submeshName,
                                                               object: child,
                                                               vertexDescriptor: vertexDescriptor) {
                    return mesh
                }
            }
        }
        
        return nil
    }

    private func createSingleSMMeshFromModel(modelName: String, submeshName: String, ext: String = "obj") {
        print("[createSingleSMMeshFromModel] model name: \(modelName)")

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

        let child = asset.childObjects(of: MDLObject.self)[0]
        print("[createSingleSMMeshFromModel] \(modelName) child name: \(child.name)")
        
        guard let cMesh = SingleSMMesh.makeSingleSMMeshWithSubmeshNamed(submeshName,
                                                                        object: child,
                                                                        vertexDescriptor: descriptor) else {
            fatalError("[SingleSMMesh makeMeshWithSubmeshNamed] Could not find any submesh named \(submeshName)")
        }
        
        _childMesh = cMesh
    }

    func setInstanceCount(_ count: Int) {
        self._instanceCount = count
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
        if let _vertexBuffer = _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)

            if applyMaterials {
                _submesh.applyTextures(renderCommandEncoder: renderCommandEncoder,
                                       customBaseColorTextureType: baseColorTextureType,
                                       customNormalMapTextureType: normalMapTextureType,
                                       customSpecularTextureType: specularTextureType)
                _submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
            }

            renderCommandEncoder.drawIndexedPrimitives(type: _submesh.primitiveType,
                                                       indexCount: _submesh.indexCount,
                                                       indexType: _submesh.indexType,
                                                       indexBuffer: _submesh.indexBuffer,
                                                       indexBufferOffset: _submesh.indexBufferOffset,
                                                       instanceCount: _instanceCount)
        }

        if let cm = _childMesh {
            cm.drawPrimitives(renderCommandEncoder,
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

            renderCommandEncoder.drawIndexedPrimitives(type: _submesh.primitiveType,
                                                       indexCount: _submesh.indexCount,
                                                       indexType: _submesh.indexType,
                                                       indexBuffer: _submesh.indexBuffer,
                                                       indexBufferOffset: _submesh.indexBufferOffset,
                                                       instanceCount: _instanceCount)
        }
        
        if let cm = _childMesh {
            cm.drawShadowPrimitives(renderCommandEncoder)
        }
    }
}

