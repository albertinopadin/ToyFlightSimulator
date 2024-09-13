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
    // Trying out only declaring this once...
    public static let mtkMeshBufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
    
    private static let loadingQueue = DispatchQueue(label: "mesh-model-loading-queue")
    
    public var name: String = "Mesh"
    internal var _vertices: [Vertex] = []
    internal var _vertexCount: Int = 0
    internal var _vertexBuffer: MTLBuffer! = nil
    internal var _instanceCount: Int = 1
    internal var _submeshes: [Submesh] = []
    internal var _childMeshes: [Mesh] = []
    internal var _metalKitMesh: MTKMesh? = nil
    
    init() {
        createMesh()
        createBuffer()
    }
    
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
            _metalKitMesh = try MTKMesh(mesh: mdlMesh, device: Engine.Device)
            print("[Mesh init] MTKMesh: \(String(describing: _metalKitMesh))")
            if _metalKitMesh!.vertexBuffers.count > 1 {
                print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
            }
            self._vertexBuffer = _metalKitMesh!.vertexBuffers[0].buffer
            self._vertexCount = _metalKitMesh!.vertexCount
            for i in 0..<_metalKitMesh!.submeshes.count {
                let mtkSubmesh = _metalKitMesh!.submeshes[i]
                let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
                let submesh = Submesh(mtkSubmesh: mtkSubmesh, 
                                      mdlSubmesh: mdlSubmesh)
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
        
        self._metalKitMesh = mtkMesh
        if _metalKitMesh!.vertexBuffers.count > 1 {
            // TODO: Figure out how to handle multiple vertex layouts with potentially multiple buffers
            print("[Mesh init] WARNING! Metal Kit Mesh has more than one vertex buffer.")
        }
        self._vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        self._vertexCount = mtkMesh.vertexCount
        for i in 0..<mtkMesh.submeshes.count {
            let mtkSubmesh = mtkMesh.submeshes[i]
            let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
            let submesh = Submesh(mtkSubmesh: mtkSubmesh, 
                                  mdlSubmesh: mdlSubmesh)
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
    
    func applyMaterial(with renderEncoder: MTLRenderCommandEncoder, material: MaterialProperties?) {
        var mat = material
        renderEncoder.setFragmentBytes(&mat, length: MaterialProperties.stride, index: Int(TFSBufferIndexMaterial.rawValue))
    }
    
    func drawIndexedPrimitives(_ renderEncoder: MTLRenderCommandEncoder, submesh: Submesh, instanceCount: Int) {
        renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                            indexCount: submesh.indexCount,
                                            indexType: submesh.indexType,
                                            indexBuffer: submesh.indexBuffer,
                                            indexBufferOffset: submesh.indexBufferOffset,
                                            instanceCount: instanceCount)
    }
    
    func drawPrimitives(_ renderEncoder: MTLRenderCommandEncoder,
                        objectName: String,
                        material: MaterialProperties? = nil,
                        applyMaterials: Bool = true,
                        withTransparency: Bool = false,
                        baseColorTextureType: TextureType = .None,
                        normalMapTextureType: TextureType = .None,
                        specularTextureType: TextureType = .None,
                        submeshesToDisplay: [String: Bool]? = nil) {
        if let _vertexBuffer {
            renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                if let submeshesToDisplay {
                    for submesh in _submeshes {
                        if submeshesToDisplay[submesh.name] ?? false {
                            drawSubmesh(renderEncoder,
                                        submesh: submesh,
                                        objectName: objectName,
                                        material: material,
                                        applyMaterials: applyMaterials,
                                        withTransparency: withTransparency,
                                        baseColorTextureType: baseColorTextureType,
                                        normalMapTextureType: normalMapTextureType,
                                        specularTextureType: specularTextureType)
                        }
                    }
                } else {
                    for submesh in _submeshes {
                        drawSubmesh(renderEncoder,
                                    submesh: submesh,
                                    objectName: objectName,
                                    material: material,
                                    applyMaterials: applyMaterials,
                                    withTransparency: withTransparency,
                                    baseColorTextureType: baseColorTextureType,
                                    normalMapTextureType: normalMapTextureType,
                                    specularTextureType: specularTextureType)
                    }
                }
            } else {
                if applyMaterials, let material {
                    applyMaterial(with: renderEncoder, material: material)
                }
                
                renderEncoder.drawPrimitives(type: .triangle,
                                                    vertexStart: 0,
                                                    vertexCount: _vertices.count,
                                                    instanceCount: _instanceCount)
            }
        }
        
        for child in _childMeshes {
            child.drawPrimitives(renderEncoder,
                                 objectName: objectName,
                                 material: material,
                                 applyMaterials: applyMaterials,
                                 withTransparency: withTransparency,
                                 baseColorTextureType: baseColorTextureType,
                                 normalMapTextureType: normalMapTextureType,
                                 specularTextureType: specularTextureType,
                                 submeshesToDisplay: submeshesToDisplay)
        }
    }
    
    func drawSubmesh(_ renderEncoder: MTLRenderCommandEncoder,
                     submesh: Submesh,
                     objectName: String,
                     material: MaterialProperties? = nil,
                     applyMaterials: Bool = true,
                     withTransparency: Bool = false,
                     baseColorTextureType: TextureType = .None,
                     normalMapTextureType: TextureType = .None,
                     specularTextureType: TextureType = .None) {
        if withTransparency == submesh.material!.isTransparent {
            if applyMaterials {
                submesh.material?.applyTextures(with: renderEncoder,
                                                baseColorTextureType: baseColorTextureType,
                                                normalMapTextureType: normalMapTextureType,
                                                specularTextureType: specularTextureType)
                submesh.applyMaterial(with: renderEncoder, customMaterial: material)
            }
            
            drawIndexedPrimitives(renderEncoder, submesh: submesh, instanceCount: _instanceCount)
        }
    }
    
    func drawShadowPrimitives(_ renderEncoder: MTLRenderCommandEncoder, submeshesToDisplay: [String: Bool]? = nil) {
        if let _vertexBuffer {
            renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            if _submeshes.count > 0 {
                if let submeshesToDisplay {
                    for submesh in _submeshes {
                        if submeshesToDisplay[submesh.name] ?? false {
                            drawIndexedPrimitives(renderEncoder, submesh: submesh, instanceCount: _instanceCount)
                        }
                    }
                } else {
                    for submesh in _submeshes {
                        drawIndexedPrimitives(renderEncoder, submesh: submesh, instanceCount: _instanceCount)
                    }
                }
            } else {
                renderEncoder.drawPrimitives(type: .triangle,
                                                    vertexStart: 0,
                                                    vertexCount: _vertices.count,
                                                    instanceCount: _instanceCount)
            }
        }
        
        for child in _childMeshes {
            child.drawShadowPrimitives(renderEncoder, submeshesToDisplay: submeshesToDisplay)
        }
    }
}
