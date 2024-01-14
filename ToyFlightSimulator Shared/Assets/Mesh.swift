//
//  Mesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit

enum MeshExtension: String {
    case OBJ = "obj"
    case USDC = "usdc"
    case USDZ = "usdz"
}

// Vertex Information
class Mesh {
    private static let loadingQueue = DispatchQueue(label: "mesh-model-loading-queue")
    
    public var name: String = "Mesh"
    private var _vertices: [Vertex] = []
    private var _vertexCount: Int = 0
    private var _vertexBuffer: MTLBuffer! = nil
    private var _instanceCount: Int = 1
    internal var _submeshes: [Submesh] = []
    internal var _childMeshes: [Mesh] = []
    var metalKitMesh: MTKMesh? = nil
    
    init() {
        createMesh()
        createBuffer()
    }
    
    // TODO: Implement loading function based on examples from Alloy or Satin
//    init(modelName: String, ext: MeshExtension = .OBJ) {
//        name = modelName
//        createMeshFromModel(modelName, ext: ext)
//    }
    
    init(mdlMesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor, addTangentBases: Bool = true) {
        print("[Mesh init] mdlMesh name: \(mdlMesh.name)")
        name = mdlMesh.name
        
        if addTangentBases {
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    normalAttributeNamed: MDLVertexAttributeNormal,
                                    tangentAttributeNamed: MDLVertexAttributeTangent)
            
            mdlMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                                    tangentAttributeNamed: MDLVertexAttributeTangent,
                                    bitangentAttributeNamed: MDLVertexAttributeBitangent)
        }
        
        mdlMesh.vertexDescriptor = vertexDescriptor
        do {
            print("[Mesh init] instantiating MTKMesh...")
            metalKitMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
            print("[Mesh init] MTKMesh: \(String(describing: metalKitMesh))")
            if metalKitMesh!.vertexBuffers.count > 1 {
                print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
            }
            self._vertexBuffer = metalKitMesh!.vertexBuffers[0].buffer
            self._vertexCount = metalKitMesh!.vertexCount
            let textureLoader = MTKTextureLoader(device: Engine.Device)
            for i in 0..<metalKitMesh!.submeshes.count {
                let mtkSubmesh = metalKitMesh!.submeshes[i]
                let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
                let submesh: Submesh
                submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh, textureLoader: textureLoader)
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
        let textureLoader = MTKTextureLoader(device: Engine.Device)
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh: Submesh
            submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh, textureLoader: textureLoader)
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
    
    internal static func createMdlVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MTKModelIOVertexDescriptorFromMetal(Graphics.VertexDescriptors[.Base])
        descriptor.attribute(TFSVertexAttributePosition.rawValue).name      = MDLVertexAttributePosition
        descriptor.attribute(TFSVertexAttributePosition.rawValue).format    = .float3
        descriptor.attribute(TFSVertexAttributeColor.rawValue).name         = MDLVertexAttributeColor
        descriptor.attribute(TFSVertexAttributeColor.rawValue).format       = .float4
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name      = MDLVertexAttributeTextureCoordinate
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).format    = .float2
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).name        = MDLVertexAttributeNormal
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).format      = .float3
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).name       = MDLVertexAttributeTangent
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).format     = .float3
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name     = MDLVertexAttributeBitangent
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).format   = .float3
        return descriptor
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
    
    func applyMaterial(with renderCommandEncoder: MTLRenderCommandEncoder, material: ShaderMaterial?) {
        var mat = material
        renderCommandEncoder.setFragmentBytes(&mat, length: ShaderMaterial.stride, index: Int(TFSBufferIndexMaterial.rawValue))
    }
    
    func drawIndexedPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder, submesh: Submesh, instanceCount: Int) {
        renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                   indexCount: submesh.indexCount,
                                                   indexType: submesh.indexType,
                                                   indexBuffer: submesh.indexBuffer,
                                                   indexBufferOffset: submesh.indexBufferOffset,
                                                   instanceCount: instanceCount)
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        material: ShaderMaterial? = nil,
                        applyMaterials: Bool = true,
                        baseColorTextureType: TextureType = .None,
                        normalMapTextureType: TextureType = .None,
                        specularTextureType: TextureType = .None,
                        submeshesToDisplay: [String: Bool]? = nil) {
        if let _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                if let submeshesToDisplay {
                    for submesh in _submeshes {
                        if submeshesToDisplay[submesh.name] ?? false {
                            if applyMaterials {
                                submesh.material?.applyTextures(with: renderCommandEncoder,
                                                                baseColorTextureType: baseColorTextureType,
                                                                normalMapTextureType: normalMapTextureType,
                                                                specularTextureType: specularTextureType)
                                submesh.applyMaterial(with: renderCommandEncoder, customMaterial: material)
                            }

                            drawIndexedPrimitives(renderCommandEncoder, submesh: submesh, instanceCount: _instanceCount)
                        }
                    }
                } else {
                    for submesh in _submeshes {
                        if applyMaterials {
                            submesh.material?.applyTextures(with: renderCommandEncoder,
                                                            baseColorTextureType: baseColorTextureType,
                                                            normalMapTextureType: normalMapTextureType,
                                                            specularTextureType: specularTextureType)
                            submesh.applyMaterial(with: renderCommandEncoder, customMaterial: material)
                        }
                        
                        drawIndexedPrimitives(renderCommandEncoder, submesh: submesh, instanceCount: _instanceCount)
                    }
                }
            } else {
                if applyMaterials, let material {
                    applyMaterial(with: renderCommandEncoder, material: material)
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
                                 specularTextureType: specularTextureType,
                                 submeshesToDisplay: submeshesToDisplay)
        }
    }
    
    func drawShadowPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder, submeshesToDisplay: [String: Bool]? = nil) {
        if let _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            if _submeshes.count > 0 {
                if let submeshesToDisplay {
                    for submesh in _submeshes {
                        if submeshesToDisplay[submesh.name] ?? false {
                            drawIndexedPrimitives(renderCommandEncoder, submesh: submesh, instanceCount: _instanceCount)
                        }
                    }
                } else {
                    for submesh in _submeshes {
                        drawIndexedPrimitives(renderCommandEncoder, submesh: submesh, instanceCount: _instanceCount)
                    }
                }
            } else {
                renderCommandEncoder.drawPrimitives(type: .triangle,
                                                    vertexStart: 0,
                                                    vertexCount: _vertices.count,
                                                    instanceCount: _instanceCount)
            }
        }
        
        for child in _childMeshes {
            child.drawShadowPrimitives(renderCommandEncoder, submeshesToDisplay: submeshesToDisplay)
        }
    }
}
