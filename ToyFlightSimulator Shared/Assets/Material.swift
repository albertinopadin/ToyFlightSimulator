//
//  Material.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/7/24.
//

import MetalKit

struct Material {
    public static let TextureCache = TFSCache<MDLTexture, MTLTexture>()
    
    public var name: String
    public var shaderMaterial = ShaderMaterial()
    public var baseColorTexture: MTLTexture?
    public var normalMapTexture: MTLTexture?
    public var specularTexture: MTLTexture?
    
    init(_ mdlMaterial: MDLMaterial, textureLoader: MTKTextureLoader) {
        name = mdlMaterial.name
        if let ambient = mdlMaterial.property(with: .emission)?.float3Value { shaderMaterial.ambient = ambient }
        if let diffuse = mdlMaterial.property(with: .baseColor)?.float3Value { shaderMaterial.diffuse = diffuse }
        if let specular = mdlMaterial.property(with: .specular)?.float3Value { shaderMaterial.specular = specular }
        if let shininess = mdlMaterial.property(with: .specularExponent)?.floatValue { shaderMaterial.shininess = shininess }
        
        baseColorTexture = Material.Texture(for: .baseColor, in: mdlMaterial, textureLoader: textureLoader)
        normalMapTexture = Material.Texture(for: .tangentSpaceNormal, in: mdlMaterial, textureLoader: textureLoader)
        specularTexture = Material.Texture(for: .specular, in: mdlMaterial, textureLoader: textureLoader)
    }
    
    public mutating func applyTextures(with renderCommandEncoder: MTLRenderCommandEncoder,
                                       baseColorTextureType: TextureType,
                                       normalMapTextureType: TextureType,
                                       specularTextureType: TextureType) {
        shaderMaterial.useBaseTexture = baseColorTextureType != .None || baseColorTexture != nil
        shaderMaterial.useNormalMapTexture = normalMapTextureType != .None || normalMapTexture != nil
        shaderMaterial.useSpecularTexture = specularTextureType != .None || specularTexture != nil
        
        renderCommandEncoder.setFragmentSamplerState(Graphics.SamplerStates[.Linear], index: 0)
        
        if let baseColorTex = baseColorTextureType == .None ? baseColorTexture : Assets.Textures[baseColorTextureType] {
            renderCommandEncoder.setFragmentTexture(baseColorTex, index: Int(TFSTextureIndexBaseColor.rawValue))
        }
        
        if let normalMapTex = normalMapTextureType == .None ? normalMapTexture : Assets.Textures[normalMapTextureType] {
            renderCommandEncoder.setFragmentTexture(normalMapTex, index: Int(TFSTextureIndexNormal.rawValue))
        }
        
        if let specularTex = specularTextureType == .None ? specularTexture : Assets.Textures[specularTextureType] {
            renderCommandEncoder.setFragmentTexture(specularTex, index: Int(TFSTextureIndexSpecular.rawValue))
        }
    }
    
    public static func Texture(for semantic: MDLMaterialSemantic,
                               in material: MDLMaterial?,
                               textureLoader: MTKTextureLoader,
                               textureOrigin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {
        guard let material else { return nil }
        
        var newTexture: MTLTexture!
        
        if semantic == .baseColor {
            print("\(material.name) num of properties with semantic baseColor: \(material.properties(with: semantic).count)")
        }
        
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
                    // TODO: cache texture here
                    print("Material property is string!")
                    if let stringValue = property.stringValue {
                        newTexture = try? textureLoader.newTexture(name: stringValue,
                                                                   scaleFactor: 1.0,
                                                                   bundle: nil,
                                                                   options: options)
                    }
                case .URL:
                    // TODO: cache texture here
                    print("Material property is url!")
                    if let newTexture {
                        print("[Material texture] Material prop is URL; newTexture has already been set: \(newTexture)")
                    }
                    
                    if let textureURL = property.urlValue {
                        newTexture = try? textureLoader.newTexture(URL: textureURL, options: options)
                    }
                case .texture:
                    print("Material property is texture!")
                    if let newTexture {
                        print("[Material texture] Material prop is texture; newTexture has already been set: \(newTexture)")
                    }
                    
                    let sourceTexture = property.textureSamplerValue!.texture!
    //                print("sourceTexture: \(sourceTexture.debugDescription)")
                
                    if let cachedTexture = Material.TextureCache[sourceTexture] {
                        newTexture = cachedTexture
                    } else {
                        newTexture = try? textureLoader.newTexture(texture: sourceTexture, options: options)
                        Material.TextureCache[sourceTexture] = newTexture
                    }
                
                case .color:
                    // TODO: cache texture here
                    print("Material property is color!")
                    if let newTexture {
                        print("[Material texture] Material prop is color; newTexture has already been set: \(newTexture)")
                        break
                    }
                    
                    let color = float4(Float(property.color!.components![0]),
                                       Float(property.color!.components![1]),
                                       Float(property.color!.components![2]),
                                       Float(property.color!.components![3]))
                    
                    newTexture = Material.MakeSolid2DTexture(device: Engine.Device, color: color)
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
    
    public static func MakeSolid2DTexture(device: MTLDevice,
                                          color: simd_float4,
                                          pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        print("[makeSolid2DTexture] Color: \(color)")
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 8
        descriptor.height = 8
        descriptor.mipmapLevelCount = 1
        #if os(macOS)
        descriptor.storageMode = .managed
        #endif
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
}
