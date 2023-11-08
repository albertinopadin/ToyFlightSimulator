//
//  Mesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit
import GLTFKit2

enum MeshExtension: String {
    case OBJ = "obj"
    case GLTF = "gltf"
    case GLB = "glb"
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
    
    init(modelName: String, ext: MeshExtension = .OBJ) {
        name = modelName
        createMeshFromModel(modelName, ext: ext)
    }
    
    init(mdlMesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor, addTangentBases: Bool = true) {
        print("[Mesh init] mdlMesh name: \(mdlMesh.name)")
        name = mdlMesh.name
        
//        mdlMesh.vertexDescriptor = vertexDescriptor
        
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
            for i in 0..<metalKitMesh!.submeshes.count {
                let mtkSubmesh = metalKitMesh!.submeshes[i]
                let mdlSubmesh = mdlMesh.submeshes![i] as! MDLSubmesh
                let submesh: Submesh
                if mdlSubmesh.name == "submesh" {
                    submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh, name: mdlMesh.name)
                } else {
                    submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
                }
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
            let submesh: Submesh
            if mdlSubmesh.name == "submesh" {
                submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh, name: mdlMesh.name)
            } else {
                submesh = Submesh(mtkSubmesh: mtkSubmesh, mdlSubmesh: mdlSubmesh)
            }
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
    
    private static func makeMeshes(object: MDLObject,
                                   vertexDescriptor: MDLVertexDescriptor,
                                   fileExtension: MeshExtension = .OBJ) -> [Mesh] {
        var meshes = [Mesh]()
        
        print("[makeMeshes] object named \(object.name): \(object)")
        
        switch fileExtension {
            case .OBJ:
                if let mesh = object as? MDLMesh {
                    print("[makeMeshes] object named \(object.name) is MDLMesh")
                    let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
                    meshes.append(newMesh)
                }
                
                if object.conforms(to: MDLObjectContainerComponent.self) {
                    print("[makeMeshes] object named \(object.name) conforms to MDLObjectContainerComponent and has \(object.children.objects.count) children")
                    for child in object.children.objects {
                        let childMeshes = makeMeshes(object: child, vertexDescriptor: vertexDescriptor, fileExtension: fileExtension)
                        meshes.append(contentsOf: childMeshes)
                    }
                } else {
                    print("[makeMeshes] object \(object.name) does not conform to MDLObjectContainerComponent")
                }
            case .USDC, .USDZ:
                if let mesh = object as? MDLMesh {
                    print("[makeMeshes] object named \(object.name) is MDLMesh")
                    let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
                    meshes.append(newMesh)
                }
                
                for child in object.children.objects {
                    let childMeshes = makeMeshes(object: child, vertexDescriptor: vertexDescriptor, fileExtension: fileExtension)
                    meshes.append(contentsOf: childMeshes)
                }
            case .GLB, .GLTF:
                if let mesh = object as? MDLMesh {
                    print("[makeMeshes] object named \(object.name) is MDLMesh")
                    
                    // Perhaps we can move around the data in the vertex buffers to correspond to
                    // the BASE vertex format the engine was built around...
//                    mesh.submeshes
//                    mesh.vertexDescriptor
//                    mesh.vertexBuffers
//                    mesh.vertexAttributeData(forAttributeNamed: <#T##String#>)
//                    mesh.addAttribute(withName: <#T##String#>, format: <#T##MDLVertexFormat#>)
//                    mesh.addAttribute(withName: <#T##String#>, format: <#T##MDLVertexFormat#>, type: <#T##String#>, data: <#T##Data#>, stride: <#T##Int#>)
//                    mesh.addNormals(withAttributeNamed: <#T##String?#>, creaseThreshold: <#T##Float#>)
                    
//                    let positionVertexAttrData: MDLVertexAttributeData =
//                        mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition)!
//                    let texcoordVertexAttrData = 
//                        mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate)!
//                    let normalVertexAttrData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal)!
                    
//                    let normalVertexBuffer: MDLMeshBuffer = mesh.vertexBuffers[0]
//                    let texcoordVertexBuffer: MDLMeshBuffer = mesh.vertexBuffers[1]
//                    let positionVertexBuffer: MDLMeshBuffer = mesh.vertexBuffers[2]
                    
                    let positionVertexBuffer: MDLMeshBuffer = mesh.vertexBuffers[0]
                    let normalVertexBuffer: MDLMeshBuffer = mesh.vertexBuffers[1]
                    let texcoordVertexBuffer: MDLMeshBuffer = mesh.vertexBuffers[2]
                    
//                    let colorVertexBuffer = MDLMeshBufferData(type: .vertex, length: positionVertexBuffer.length)
//                    let tangentVertexBuffer = MDLMeshBufferData(type: .vertex, length: positionVertexBuffer.length)
//                    let bitangentVertexBuffer = MDLMeshBufferData(type: .vertex, length: positionVertexBuffer.length)
                    
//                    let colorVertexBuffer = mesh.allocator.newBuffer(positionVertexBuffer.length, type: .vertex)
                    
                    let colorVertexBuffer = mesh.allocator.newBuffer(16, type: .vertex)
                    let tangentVertexBuffer = mesh.allocator.newBuffer(positionVertexBuffer.length, type: .vertex)
                    let bitangentVertexBuffer = mesh.allocator.newBuffer(positionVertexBuffer.length, type: .vertex)
                    
//                    print("[makeMeshes] removing attribute named: \(MDLVertexAttributeTextureCoordinate)")
//                    mesh.removeAttributeNamed(MDLVertexAttributeTextureCoordinate)
//                    
//                    print("[makeMeshes] removing attribute named: \(MDLVertexAttributeNormal)")
//                    mesh.removeAttributeNamed(MDLVertexAttributeNormal)
//                    
//                    print("[makeMeshes] removing attribute named: \(MDLVertexAttributePosition)")
//                    mesh.removeAttributeNamed(MDLVertexAttributePosition)
                    
                    // Which to use? The buffer, or the Attribute Data?
                    
                    let reorderedVertexBuffers = [
                        positionVertexBuffer,
                        colorVertexBuffer,
                        texcoordVertexBuffer,
                        normalVertexBuffer,
                        tangentVertexBuffer,
                        bitangentVertexBuffer
                    ]
//
                    print("[makeMeshes] vertex descriptor: \(vertexDescriptor)")
                    print("[makeMeshes] mesh vertexCount: \(mesh.vertexCount)")
                    print("[makeMeshes] position vertex buffer length (in bytes): \(positionVertexBuffer.length)")
                    print("[makeMeshes] color vertex buffer length (in bytes): \(colorVertexBuffer.length)")
                    print("[makeMeshes] texture coordinate vertex buffer length (in bytes): \(texcoordVertexBuffer.length)")
                    print("[makeMeshes] normal vertex buffer length (in bytes): \(normalVertexBuffer.length)")
                    print("[makeMeshes] tangent vertex buffer length (in bytes): \(tangentVertexBuffer.length)")
                    print("[makeMeshes] bitangent vertex buffer length (in bytes): \(bitangentVertexBuffer.length)")
                    
                    let reorderedMesh = MDLMesh(vertexBuffers: reorderedVertexBuffers,
                                                vertexCount: mesh.vertexCount,
                                                descriptor: vertexDescriptor,
                                                submeshes: mesh.submeshes as! [MDLSubmesh])
                    
                    // Position
//                    mesh.addAttribute(withName: MDLVertexAttributePosition,
//                                      format: .float3,
//                                      type: MDLVertexAttributePosition,
//                                      data: Data(bytes: positionVertexBuffer.map().bytes, count: positionVertexBuffer.length),
//                                      stride: float3.stride)
                    
//                    mesh.addAttribute(withName: MDLVertexAttributePosition,
//                                      format: .float3,
//                                      type: MDLVertexAttributePosition,
//                                      data: Data(bytes: positionVertexAttrData.dataStart,
//                                                 count: positionVertexAttrData.bufferSize),
//                                      stride: float3.stride)
                    
                    // Texture Coordinate
//                    mesh.addAttribute(withName: MDLVertexAttributeTextureCoordinate,
//                                      format: .float3,
//                                      type: MDLVertexAttributeTextureCoordinate,
//                                      data: Data(bytes: texcoordVertexBuffer.map().bytes, count: texcoordVertexBuffer.length),
//                                      stride: float3.stride)
                    
//                    mesh.addAttribute(withName: MDLVertexAttributeTextureCoordinate,
//                                      format: .float3,
//                                      type: MDLVertexAttributeTextureCoordinate,
//                                      data: Data(bytes: texcoordVertexAttrData.dataStart,
//                                                 count: texcoordVertexAttrData.bufferSize),
//                                      stride: float3.stride)
                    
                    // Normal
//                    mesh.addAttribute(withName: MDLVertexAttributeNormal,
//                                      format: .float3,
//                                      type: MDLVertexAttributeNormal,
//                                      data: Data(bytes: normalVertexBuffer.map().bytes, count: normalVertexBuffer.length),
//                                      stride: float3.stride)
                    
//                    mesh.addAttribute(withName: MDLVertexAttributeNormal,
//                                      format: .float3,
//                                      type: MDLVertexAttributeNormal,
//                                      data: Data(bytes: normalVertexAttrData.dataStart,
//                                                 count: normalVertexAttrData.bufferSize),
//                                      stride: float3.stride)
                    
                    
//                    let newMesh = Mesh(mdlMesh: mesh, vertexDescriptor: vertexDescriptor)
                    let newMesh = Mesh(mdlMesh: reorderedMesh, vertexDescriptor: vertexDescriptor)
                    meshes.append(newMesh)
                }
                
                for child in object.children.objects {
                    let childMeshes = makeMeshes(object: child, vertexDescriptor: vertexDescriptor, fileExtension: fileExtension)
                    meshes.append(contentsOf: childMeshes)
                }
        }
        
        return meshes
    }
    
    private func createMeshFromModel(_ modelName: String, ext: MeshExtension) {
        print("[createMeshFromModel] model name: \(modelName)")
        
        guard let assetURL = Bundle.main.url(forResource: modelName, withExtension: ext.rawValue) else {
            fatalError("Asset \(modelName) does not exist.")
        }
        
        Mesh.loadingQueue.async { [weak self] in
            switch ext {
                case .OBJ:
                    self?.createMeshFromObjModel(modelName, assetUrl: assetURL)
                case .GLB, .GLTF:
                    self?.createMeshFromGlbModel(modelName, assetUrl: assetURL)
                case .USDC, .USDZ:
                    self?.createMeshFromUsdModel(modelName, assetUrl: assetURL)
            }
        }
    }
    
    private func createMdlVertexDescriptor(descriptorType: VertexDescriptorType) -> MDLVertexDescriptor {
        let mtlDescriptor: MTLVertexDescriptor = Graphics.VertexDescriptors[descriptorType]
        let descriptor = MTKModelIOVertexDescriptorFromMetal(mtlDescriptor)
        descriptor.attribute(TFSVertexAttributePosition.rawValue).name      = MDLVertexAttributePosition
        descriptor.attribute(TFSVertexAttributePosition.rawValue).format    = .float3
        descriptor.attribute(TFSVertexAttributeColor.rawValue).name         = MDLVertexAttributeColor
        descriptor.attribute(TFSVertexAttributeColor.rawValue).format       = .float4
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).name      = MDLVertexAttributeTextureCoordinate
        descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).format    = .float2
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).name        = MDLVertexAttributeNormal
        descriptor.attribute(TFSVertexAttributeNormal.rawValue).format      = .float3
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).name       = MDLVertexAttributeTangent
        descriptor.attribute(TFSVertexAttributeTangent.rawValue).format      = .float3
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).name     = MDLVertexAttributeBitangent
        descriptor.attribute(TFSVertexAttributeBitangent.rawValue).format      = .float3
        
        switch descriptorType {
            case .Base:
                (descriptor.layouts[0] as! MDLVertexBufferLayout).stride = Vertex.stride
            case .USD:
                (descriptor.layouts[0] as! MDLVertexBufferLayout).stride = Vertex.stride
            case .GLTF:
                descriptor.attribute(TFSVertexAttributePosition.rawValue).bufferIndex = 0
                descriptor.attribute(TFSVertexAttributeColor.rawValue).bufferIndex = 1
                descriptor.attribute(TFSVertexAttributeTexcoord.rawValue).bufferIndex = 2
                descriptor.attribute(TFSVertexAttributeNormal.rawValue).bufferIndex = 3
            
                (descriptor.layouts[Int(TFSVertexAttributePosition.rawValue)] as! MDLVertexBufferLayout).stride = float3.stride
                (descriptor.layouts[Int(TFSVertexAttributeColor.rawValue)] as! MDLVertexBufferLayout).stride = float4.stride
                (descriptor.layouts[Int(TFSVertexAttributeTexcoord.rawValue)] as! MDLVertexBufferLayout).stride = float2.stride
                (descriptor.layouts[Int(TFSVertexAttributeNormal.rawValue)] as! MDLVertexBufferLayout).stride = float3.stride
            default:
                (descriptor.layouts[0] as! MDLVertexBufferLayout).stride = Vertex.stride
        }
        
        return descriptor
    }
    
    private func createMeshFromObjModel(_ modelName: String, assetUrl: URL) {
        let descriptor = createMdlVertexDescriptor(descriptorType: .Base)
    
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
    
        let asset = MDLAsset(url: assetUrl,
                             vertexDescriptor: descriptor,
                             bufferAllocator: bufferAllocator,
                             preserveTopology: false,
                             error: nil)
        
        print("[createMeshFromObjModel] Created asset: \(asset)")
        asset.loadTextures()
        print("[createMeshFromObjModel] Loaded asset textures")
        
        for child in asset.childObjects(of: MDLObject.self) {
            print("[createMeshFromObjModel] \(modelName) child name: \(child.name)")
            _childMeshes.append(contentsOf: Mesh.makeMeshes(object: child, vertexDescriptor: descriptor, fileExtension: .OBJ))
        }
        
        print("Num child meshes for \(modelName): \(_childMeshes.count)")
        for cm in _childMeshes {
            print("Mesh named \(name); Child mesh name: \(cm.name)")
            for sm in cm._submeshes {
                print("Child mesh \(cm.name); Submesh name: \(sm.name)")
            }
        }
    }
    
    private func createMeshFromUsdModel(_ modelName: String, assetUrl: URL) {
        let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
        
        let descriptor = createMdlVertexDescriptor(descriptorType: .USD)
        let asset = MDLAsset(url: assetUrl, vertexDescriptor: descriptor, bufferAllocator: bufferAllocator)
        
        asset.loadTextures()
        
        let assetChildren = asset.childObjects(of: MDLObject.self)
        print("[createMeshFromUsdModel] \(modelName) child count: \(assetChildren.count)")
        for child in assetChildren {
            print("[createMeshFromUsdModel] \(modelName) child name: \(child.name)")
            _childMeshes.append(contentsOf: Mesh.makeMeshes(object: child, vertexDescriptor: descriptor, fileExtension: .USDC))
        }
        
        print("Num child meshes for \(modelName): \(_childMeshes.count)")
    }
    
    private func createMeshFromGlbModel(_ modelName: String, assetUrl: URL) {
        GLTFAsset.load(with: assetUrl) { (progress, status, maybeAsset, maybeError, _) in
            DispatchQueue.main.async {
                if status == .complete, let maybeAsset {
//                    let bufferAllocator = MTKMeshBufferAllocator(device: Engine.Device)
//                    let asset = MDLAsset(gltfAsset: maybeAsset, bufferAllocator: bufferAllocator)
//                    maybeAsset.
                    let asset = MDLAsset(gltfAsset: maybeAsset)
                    asset.loadTextures()
                    print("[createMeshFromGlbModel] asset: \(asset)")
                    
                    let descriptor = self.createMdlVertexDescriptor(descriptorType: .GLTF)
                    let assetChildren = asset.childObjects(of: MDLObject.self)
                    print("[createMeshFromGlbModel] \(modelName) child count: \(assetChildren.count)")
                    for child in assetChildren {
                        (child as? MDLMesh)?.vertexDescriptor = descriptor
                        print("[createMeshFromGlbModel] \(modelName) child name: \(child.name)")
                        self._childMeshes.append(contentsOf: Mesh.makeMeshes(object: child, 
                                                                             vertexDescriptor: descriptor,
                                                                             fileExtension: .GLB))
                    }
                    
                    print("[createMeshFromGlbModel] Num child meshes for \(modelName): \(self._childMeshes.count)")
                }
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
                        specularTextureType: TextureType = .None,
                        submeshesToDisplay: [String: Bool]? = nil) {
        if let _vertexBuffer {
            renderCommandEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
            
            if _submeshes.count > 0 {
                if let submeshesToDisplay {
                    for submesh in _submeshes {
                        // Hack to work with USDZ file:
                        if submesh.name == "submesh" {
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
                        } else {
                            if submeshesToDisplay[submesh.name] ?? false {
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
                        }
                        
//                        if submeshesToDisplay[submesh.name]! {
//                            if applyMaterials {
//                                submesh.applyTextures(renderCommandEncoder: renderCommandEncoder,
//                                                      customBaseColorTextureType: baseColorTextureType,
//                                                      customNormalMapTextureType: normalMapTextureType,
//                                                      customSpecularTextureType: specularTextureType)
//                                submesh.applyMaterials(renderCommandEncoder: renderCommandEncoder, customMaterial: material)
//                            }
//
//                            renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
//                                                                       indexCount: submesh.indexCount,
//                                                                       indexType: submesh.indexType,
//                                                                       indexBuffer: submesh.indexBuffer,
//                                                                       indexBufferOffset: submesh.indexBufferOffset,
//                                                                       instanceCount: _instanceCount)
//                        }
                    }
                } else {
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
                        // Hack to work with USDZ file:
                        if submesh.name == "submesh" {
                            renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                                       indexCount: submesh.indexCount,
                                                                       indexType: submesh.indexType,
                                                                       indexBuffer: submesh.indexBuffer,
                                                                       indexBufferOffset: submesh.indexBufferOffset,
                                                                       instanceCount: _instanceCount)
                        }
                        else {
                            if submeshesToDisplay[submesh.name] ?? false {
                                renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                                           indexCount: submesh.indexCount,
                                                                           indexType: submesh.indexType,
                                                                           indexBuffer: submesh.indexBuffer,
                                                                           indexBufferOffset: submesh.indexBufferOffset,
                                                                           instanceCount: _instanceCount)
                            }
                        }
                        
//                        if submeshesToDisplay[submesh.name]! {
//                            renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
//                                                                       indexCount: submesh.indexCount,
//                                                                       indexType: submesh.indexType,
//                                                                       indexBuffer: submesh.indexBuffer,
//                                                                       indexBufferOffset: submesh.indexBufferOffset,
//                                                                       instanceCount: _instanceCount)
//                        }
                    }
                } else {
                    for submesh in _submeshes {
                        // TODO: FIX:
                        // Vertex Function(shadow_vertex): argument vertexBuffer.0[0] from buffer(0) with offset(0) and length(64) has space for 64 bytes, but argument has a length(96).
                        renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                                   indexCount: submesh.indexCount,
                                                                   indexType: submesh.indexType,
                                                                   indexBuffer: submesh.indexBuffer,
                                                                   indexBufferOffset: submesh.indexBufferOffset,
                                                                   instanceCount: _instanceCount)
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
