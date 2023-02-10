//
//  Mesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit

// Vertex Information
class Mesh {
    private var _vertices: [Vertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    private var _submeshes: [Submesh] = []
    
    init() {
        createMesh()
        createBuffer()
    }
    
    init(modelName: String) {
        createMeshFromModel(modelName)
    }
    
    init(mtkMesh: MTKMesh, mdlMesh: MDLMesh) {
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
    
    private func createMeshFromModel(_ modelName: String, ext: String = "obj") {
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
//                                       preserveTopology: true,
                                       preserveTopology: false,
                                       error: nil)
        asset.loadTextures()
        
        var mdlMeshes: [MDLMesh] = []
        do {
            mdlMeshes = try MTKMesh.newMeshes(asset: asset, device: Engine.Device).modelIOMeshes
        } catch {
            print("ERROR::LOADING_MESH::__\(modelName)__::\(error)")
        }
        
        var mtkMeshes: [MTKMesh] = []
        for mdlMesh in mdlMeshes {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    tangentAttributeNamed: MDLVertexAttributeTangent,
                                    bitangentAttributeNamed: MDLVertexAttributeBitangent)
            mdlMesh.vertexDescriptor = descriptor
            do {
                let mtkMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
                mtkMeshes.append(mtkMesh)
            } catch {
                print("ERROR::LOADING_MDLMESH::__\(modelName)__::\(error)")
            }
        }

        let mtkMesh = mtkMeshes[0]
        let mdlMesh = mdlMeshes[0]
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
            addSubmesh(submesh)
        }
        
        print("Num Submeshes for \(modelName): \(_submeshes.count)")
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
    
//    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder,
//                       customBaseColorTextureType: TextureType,
//                       customNormalMapTextureType: TextureType,
//                       customSpecularTextureType: TextureType) {
//        _material.useBaseTexture = customBaseColorTextureType != .None || _baseColorTexture != nil
//        _material.useNormalMapTexture = customNormalMapTextureType != .None || _normalMapTexture != nil
//        _material.useSpecularTexture = customSpecularTextureType != .None || _normalMapTexture != nil
//        
//        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
//        
//        let baseColorTex = customBaseColorTextureType == .None ?
//                            _baseColorTexture : Assets.Textures[customBaseColorTextureType]
//        if baseColorTex != nil {
//            renderCommandEncoder.setFragmentTexture(baseColorTex, index: Int(TFSTextureIndexBaseColor.rawValue))
//        }
//        
//        let normalMapTex = customNormalMapTextureType == .None ?
//                            _normalMapTexture : Assets.Textures[customNormalMapTextureType]
//        if normalMapTex != nil {
//            renderCommandEncoder.setFragmentTexture(normalMapTex, index: Int(TFSTextureIndexNormal.rawValue))
//        }
//        
//        let specularTex = customSpecularTextureType == .None ? _specularTexture : Assets.Textures[customSpecularTextureType]
//        if specularTex != nil {
//            renderCommandEncoder.setFragmentTexture(specularTex, index: Int(TFSTextureIndexSpecular.rawValue))
//        }
//    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        material: Material? = nil,
                        baseColorTextureType: TextureType = .None,
                        normalMapTextureType: TextureType = .None,
                        specularTextureType: TextureType = .None) {
        if let _vertexBuffer = _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                for submesh in _submeshes {
                    submesh.applyTextures(renderCommandEncoder: renderCommandEncoder,
                                          customBaseColorTextureType: baseColorTextureType,
                                          customNormalMapTextureType: normalMapTextureType,
                                          customSpecularTextureType: specularTextureType)
                    submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
                    
                    renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                               indexCount: submesh.indexCount,
                                                               indexType: submesh.indexType,
                                                               indexBuffer: submesh.indexBuffer,
                                                               indexBufferOffset: submesh.indexBufferOffset,
                                                               instanceCount: _instanceCount)
                }
            } else {
                if let material {
                    applyMaterial(renderCommandEncoder: renderCommandEncoder, material: material)
                }
                
                renderCommandEncoder.drawPrimitives(type: .triangle,
                                                    vertexStart: 0,
                                                    vertexCount: _vertices.count,
                                                    instanceCount: _instanceCount)
            }
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
    }
}
