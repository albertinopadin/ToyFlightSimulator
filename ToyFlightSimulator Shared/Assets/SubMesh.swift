//
//  SubMesh.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2/6/23.
//

import MetalKit

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
    private var _specularTexture: MTLTexture!
    
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
        
        print("Creating textures and material for \(mtkSubmesh.name)")
        createTextures(mdlSubmesh.material!)
        createMaterial(mdlSubmesh.material!)
    }
    
    private func texture(for semantic: MDLMaterialSemantic,
                         in material: MDLMaterial?,
                         textureOrigin: MTKTextureLoader.Origin) -> MTLTexture? {
        guard let material = material else { return nil }
        
        let textureLoader = MTKTextureLoader(device: Engine.Device)
        
        var newTexture: MTLTexture!
        
        for property in material.properties(with: semantic) {
            let options: [MTKTextureLoader.Option: Any] = [
                .origin: textureOrigin as Any,
                .generateMipmaps: true,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ]
            
//            print("Property type: \(property.type)")
            
            switch property.type {
            case .string:
//                print("Material property is string!")
                if let stringValue = property.stringValue {
                    newTexture = try? textureLoader.newTexture(name: stringValue,
                                                                scaleFactor: 1.0,
                                                                bundle: nil,
                                                                options: options)
                }
            case .URL:
//                print("Material property is url!")
                if let textureURL = property.urlValue {
                    newTexture = try? textureLoader.newTexture(URL: textureURL, options: options)
                }
            case .texture:
//                print("Material property is texture!")
                let sourceTexture = property.textureSamplerValue!.texture!
//                print("sourceTexture: \(sourceTexture.debugDescription)")
                newTexture = try? textureLoader.newTexture(texture: sourceTexture, options: options)
            case .color:
//                print("Material property is color!")
                let color = float4(Float(property.color!.components![0]),
                                   Float(property.color!.components![1]),
                                   Float(property.color!.components![2]),
                                   Float(property.color!.components![3]))
                
                newTexture = makeSolid2DTexture(device: Engine.Device,
                                                color: color)
            case .buffer:
                print("Material property is a buffer!")
            case .matrix44:
                print("Material property is 4x4 matrix!")
            case .float, .float2, .float3, .float4:
                print("Material property is float!")
            case .none:
                print("Material property is none!")
            default:
//                fatalError("Texture data for material property not found - name: \(material.name), class name: \(material.className), debug desc: \(material.debugDescription)")
                print("In default block")
            }
        }
        
        return newTexture
    }
    
    private func makeSolid2DTexture(device: MTLDevice,
                                    color: simd_float4,
                                    pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        print("[makeSolid2DTexture] Color: \(color)")
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 8
        descriptor.height = 8
        descriptor.mipmapLevelCount = 1
        descriptor.storageMode = .managed
        descriptor.arrayLength = 1
        descriptor.sampleCount = 1
        descriptor.cpuCacheMode = .writeCombined
        descriptor.allowGPUOptimizedContents = false
        descriptor.pixelFormat = pixelFormat
        descriptor.textureType = .type2D
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("[makeSolid2DTexture] Could not create texture!")
            return nil
        }
        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        let size = MTLSize(width: texture.width, height: texture.height, depth: texture.depth)
        let region = MTLRegion(origin: origin, size: size)
        let mappedColor = simd_uchar4(color * 255)
        Array<simd_uchar4>(repeating: mappedColor, count: 64).withUnsafeBytes { ptr in
            texture.replace(region: region, mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: 32)
        }
        return texture
    }
    
    private func createTextures(_ mdlMaterial: MDLMaterial) {
        _baseColorTexture = texture(for: .baseColor, in: mdlMaterial, textureOrigin: .bottomLeft)
        _normalMapTexture = texture(for: .tangentSpaceNormal, in: mdlMaterial, textureOrigin: .bottomLeft)
        _specularTexture = texture(for: .specular, in: mdlMaterial, textureOrigin: .bottomLeft)
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
                       customNormalMapTextureType: TextureType,
                       customSpecularTextureType: TextureType) {
        _material.useBaseTexture = customBaseColorTextureType != .None || _baseColorTexture != nil
        _material.useNormalMapTexture = customNormalMapTextureType != .None || _normalMapTexture != nil
        _material.useSpecularTexture = customSpecularTextureType != .None || _normalMapTexture != nil
        
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        let baseColorTex = customBaseColorTextureType == .None ?
                            _baseColorTexture : Assets.Textures[customBaseColorTextureType]
        if baseColorTex != nil {
            renderCommandEncoder.setFragmentTexture(baseColorTex, index: Int(TFSTextureIndexBaseColor.rawValue))
        }
        
        let normalMapTex = customNormalMapTextureType == .None ?
                            _normalMapTexture : Assets.Textures[customNormalMapTextureType]
        if normalMapTex != nil {
            renderCommandEncoder.setFragmentTexture(normalMapTex, index: Int(TFSTextureIndexNormal.rawValue))
        }
        
        let specularTex = customSpecularTextureType == .None ? _specularTexture : Assets.Textures[customSpecularTextureType]
        if specularTex != nil {
            renderCommandEncoder.setFragmentTexture(specularTex, index: Int(TFSTextureIndexSpecular.rawValue))
        }
    }
    
    func applyMaterials(renderCommandEncoder: MTLRenderCommandEncoder, customMaterial: Material?) {
        var mat = customMaterial == nil ? _material : customMaterial
        renderCommandEncoder.setFragmentBytes(&mat, length: Material.stride, index: Int(TFSBufferIndexMaterial.rawValue))
    }
}
