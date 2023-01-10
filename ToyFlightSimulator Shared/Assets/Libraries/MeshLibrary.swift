//
//  MeshLibrary.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/26/22.
//

import MetalKit

enum MeshType {
    case None
    case Triangle_Custom
    case Quad_Custom
    case Cube_Custom
    case Sphere_Custom
    
    case Sphere
    case Quad
    
    case SkySphere
    
    case F16
}

class MeshLibrary: Library<MeshType, Mesh> {
    private var _library: [MeshType: Mesh] = [:]
    
    override func makeLibrary() {
        _library.updateValue(NoMesh(), forKey: .None)
        _library.updateValue(TriangleMesh(), forKey: .Triangle_Custom)
        _library.updateValue(QuadMesh(), forKey: .Quad_Custom)
        _library.updateValue(CubeMesh(), forKey: .Cube_Custom)
        _library.updateValue(SphereMesh(), forKey: .Sphere_Custom)
        
        
        _library.updateValue(Mesh(modelName: "sphere"), forKey: .Sphere)
        _library.updateValue(Mesh(modelName: "quad"), forKey: .Quad)
        _library.updateValue(Mesh(modelName: "skysphere"), forKey: .SkySphere)
        _library.updateValue(Mesh(modelName: "f16"), forKey: .F16)
    }
    
    override subscript(type: MeshType) -> Mesh {
        return _library[type]!
    }
}

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
        (descriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (descriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeColor
        (descriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (descriptor.attributes[3] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (descriptor.attributes[4] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        (descriptor.attributes[5] as! MDLVertexAttribute).name = MDLVertexAttributeBitangent
        
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
        let asset: MDLAsset = MDLAsset(url: assetURL,
                                       vertexDescriptor: descriptor,
                                       bufferAllocator: bufferAllocator,
                                       preserveTopology: true,
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
        renderCommandEncoder.setFragmentBytes(&mat, length: Material.stride, index: 1)
    }
    
    func drawPrimitives(_ renderCommandEncoder: MTLRenderCommandEncoder,
                        material: Material? = nil,
                        baseColorTextureType: TextureType = .None,
                        normalMapTextureType: TextureType = .None) {
        if let _vertexBuffer = _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                for submesh in _submeshes {
                    submesh.applyTextures(renderCommandEncoder: renderCommandEncoder,
                                          customBaseColorTextureType: baseColorTextureType,
                                          customNormalMapTextureType: normalMapTextureType)
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
}

// Index Information
class Submesh {
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
    
    private var _material = Material()
    private var _baseColorTexture: MTLTexture!
    private var _normalMapTexture: MTLTexture!
    
    init(indices: [UInt32]) {
        self._indices = indices
        self._indexCount = indices.count
        createIndexBuffer()
    }
    
    init(mtkSubmesh: MTKSubmesh, mdlSubmesh: MDLSubmesh) {
        _indexBuffer = mtkSubmesh.indexBuffer.buffer
        _indexBufferOffset = mtkSubmesh.indexBuffer.offset
        _indexCount = mtkSubmesh.indexCount
        _indexType = mtkSubmesh.indexType
        _primitiveType = mtkSubmesh.primitiveType
        
        createTexture(mdlSubmesh.material!)
        createMaterial(mdlSubmesh.material!)
    }
    
    private func texture(for semantic: MDLMaterialSemantic,
                         in material: MDLMaterial?,
                         textureOrigin: MTKTextureLoader.Origin) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: Engine.Device)
        guard let materialProperty = material?.property(with: semantic) else { return nil }
        guard let sourceTexture = materialProperty.textureSamplerValue?.texture else { return nil }
        let options: [MTKTextureLoader.Option: Any] = [
            .origin: textureOrigin as Any,
            .generateMipmaps: true
        ]
        let tex = try? textureLoader.newTexture(texture: sourceTexture, options: options)
        return tex
    }
    
    private func createTexture(_ mdlMaterial: MDLMaterial) {
        _baseColorTexture = texture(for: .baseColor, in: mdlMaterial, textureOrigin: .bottomLeft)
        _normalMapTexture = texture(for: .tangentSpaceNormal, in: mdlMaterial, textureOrigin: .bottomLeft)
    }
    
    private func createMaterial(_ mdlMaterial: MDLMaterial) {
        if let ambient = mdlMaterial.property(with: .emission)?.float3Value { _material.ambient = ambient }
        if let diffuse = mdlMaterial.property(with: .baseColor)?.float3Value { _material.diffuse = diffuse }
        if let specular = mdlMaterial.property(with: .specular)?.float3Value { _material.specular = specular }
        if let shininess = mdlMaterial.property(with: .specularExponent)?.floatValue { _material.shininess = shininess }
    }
    
    private func createIndexBuffer() {
        if _indices.count > 0 {
            _indexBuffer = Engine.Device.makeBuffer(bytes: _indices,
                                                    length: UInt32.stride(_indices.count),
                                                    options: [])
        }
    }
    
    func applyTextures(renderCommandEncoder: MTLRenderCommandEncoder,
                       customBaseColorTextureType: TextureType,
                       customNormalMapTextureType: TextureType) {
        _material.useBaseTexture = customBaseColorTextureType != .None || _baseColorTexture != nil
        _material.useNormalMapTexture = customNormalMapTextureType != .None || _normalMapTexture != nil
        
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        let baseColorTex = customBaseColorTextureType == .None ?
                            _baseColorTexture : Assets.Textures[customBaseColorTextureType]
        if baseColorTex != nil {
            renderCommandEncoder.setFragmentTexture(baseColorTex, index: 0)
        }
        
        let normalMapTex = customNormalMapTextureType == .None ?
                            _normalMapTexture : Assets.Textures[customNormalMapTextureType]
        if normalMapTex != nil {
            renderCommandEncoder.setFragmentTexture(normalMapTex, index: 1)
        }
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder, customMaterial: Material?) {
        var mat = customMaterial == nil ? _material : customMaterial
        renderCommandEncoder.setFragmentBytes(&mat, length: Material.stride, index: 1)
    }
}

class NoMesh: Mesh { }

class TriangleMesh: Mesh {
    override func createMesh() {
        addVertex(position: float3( 0, 1,0), color: float4(1,0,0,1), textureCoordinate: float2(0.5,0.0), normal: float3(0,0,1))
        addVertex(position: float3(-1,-1,0), color: float4(0,1,0,1), textureCoordinate: float2(0.0,1.0), normal: float3(0,0,1))
        addVertex(position: float3( 1,-1,0), color: float4(0,0,1,1), textureCoordinate: float2(1.0,1.0), normal: float3(0,0,1))
    }
}

class QuadMesh: Mesh {
    override func createMesh() {
        addVertex(position: float3( 1, 1,0),
                  color: float4(1,0,0,1),
                  textureCoordinate: float2(1,0),
                  normal: float3(0,0,1)) //Top Right
        addVertex(position: float3(-1, 1,0),
                  color: float4(0,1,0,1),
                  textureCoordinate: float2(0,0),
                  normal: float3(0,0,1)) //Top Left
        addVertex(position: float3(-1,-1,0),
                  color: float4(0,0,1,1),
                  textureCoordinate: float2(0,1),
                  normal: float3(0,0,1)) //Bottom Left
        addVertex(position: float3( 1,-1,0),
                  color: float4(1,0,1,1),
                  textureCoordinate: float2(1,1),
                  normal: float3(0,0,1)) //Bottom Right
        
        addSubmesh(Submesh(indices: [
            0,1,2,
            0,2,3
        ]))
    }
}

class CubeMesh: Mesh {
    override func createMesh() {
        //Left
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(-1, 0, 0))
        
        //RIGHT
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 0.5, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(0.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 1, 0, 0))
        
        //TOP
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.5, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 1, 0))
        
//        addSubmesh(Submesh(indices: [
//            0,1,2,
//            0,2,3
//        ]))
        
        //BOTTOM
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(0.5, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0, 0.5, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0,-1, 0))
        
        //BACK
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(0.5, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0, 1.0,-1.0),
                  color: float4(0.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3( 1.0, 1.0,-1.0),
                  color: float4(1.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3( 1.0,-1.0,-1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0,-1))
        addVertex(position: float3(-1.0,-1.0,-1.0),
                  color: float4(1.0,0.5,1.0,1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3(0,0,-1))
        
        //FRONT
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(1.0, 0.5, 0.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3(-1.0,-1.0, 1.0),
                  color: float4(0.0, 1.0, 0.0, 1.0),
                  textureCoordinate: float2(0,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(0.5, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(0,1),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0, 1.0, 1.0),
                  color: float4(1.0, 1.0, 0.5, 1.0),
                  textureCoordinate: float2(1,1),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3(-1.0, 1.0, 1.0),
                  color: float4(0.0, 1.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
        addVertex(position: float3( 1.0,-1.0, 1.0),
                  color: float4(1.0, 0.0, 1.0, 1.0),
                  textureCoordinate: float2(1,0),
                  normal: float3( 0, 0, 1))
    }
}

class SphereMesh: Mesh {
    private var color: float4
    
    init(radius: Float = 1.0, color: float4 = BLUE_COLOR) {
        let diameter = radius * 2
        self.color = color
        
        let allocator = MTKMeshBufferAllocator(device: Engine.Device)
        let mdlSphere = MDLMesh(sphereWithExtent: float3(diameter, diameter, diameter),
                                segments: SIMD2<UInt32>(100, 100),
                                inwardNormals: false,
                                geometryType: .triangles,
                                allocator: allocator)
        
        mdlSphere.vertexDescriptor = Graphics.MDLVertexDescriptors[.Base]
        let mtkMesh = try! MTKMesh(mesh: mdlSphere, device: Engine.Device)
        
        let vertexLayoutStride = (mtkMesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout).stride
        for meshBuffer in mtkMesh.vertexBuffers {
            for i in 0..<mtkMesh.vertexCount {
                let colorPosition = (i * vertexLayoutStride) + float4.stride
                meshBuffer.buffer.contents().advanced(by: colorPosition).copyMemory(from: &self.color, byteCount: float4.stride)
            }
        }
        
        super.init(mtkMesh: mtkMesh, mdlMesh: mdlSphere)
    }
}
