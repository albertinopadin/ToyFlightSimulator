//
//  TextureLoader.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 3/1/24.
//

import MetalKit

struct TextureLoader {
    public static let textureLoader = MTKTextureLoader(device: Engine.Device)
    
    private static let StringToTextureCache = TFSCache<String, MTLTexture>()
    private static let UrlToTextureCache = TFSCache<URL, MTLTexture>()
    private static let MdlToTextureCache = TFSCache<MDLTexture, MTLTexture>()
    private static let ColorToTextureCache = TFSCache<float4, MTLTexture>()
    
    private var _textureName: String!
    private var _textureExtension: String!
    private var _origin: MTKTextureLoader.Origin!
    
    init(textureName: String, textureExtension: String = "png", origin: MTKTextureLoader.Origin = .topLeft) {
        self._textureName = textureName
        self._textureExtension = textureExtension
        self._origin = origin
    }
    
    public func loadTextureFromBundle() -> MTLTexture {
        if let cachedTexture = Self.StringToTextureCache[_textureName] {
            return cachedTexture
        } else {
            guard let url = Bundle.main.url(forResource: _textureName, withExtension: _textureExtension) else {
                fatalError("ERROR::CREATING::TEXTURE::__\(_textureName!) does not exist")
            }
            
            let options: [MTKTextureLoader.Option: Any] = [
                .origin: _origin as Any,
                .generateMipmaps: true,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ]
            
            do {
                let texture = try Self.textureLoader.newTexture(URL: url, options: options)
                texture.label = _textureName
                Self.StringToTextureCache[_textureName] = texture
                return texture
            } catch {
                fatalError("ERROR::CREATING::TEXTURE::__\(_textureName!)__::\(error)")
            }
        }
    }
    
    public static func LoadTexture(name: String,
                                   scale: CGFloat = 1.0,
                                   origin: MTKTextureLoader.Origin = .topLeft) -> MTLTexture? {
        if let cachedTexture = Self.StringToTextureCache[name] {
            return cachedTexture
        } else {
            let options: [MTKTextureLoader.Option: Any] = [
                .origin: origin as Any,
                .generateMipmaps: true,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ]
            
            do {
                let texture = try Self.textureLoader.newTexture(name: name,
                                                                scaleFactor: scale,
                                                                bundle: Bundle.main,
                                                                options: options)
                texture.label = name
                Self.StringToTextureCache[name] = texture
                return texture
            } catch {
                fatalError("ERROR::CREATING::TEXTURE::__\(name)__::\(error)")
            }
        }
    }
    
    public static func Texture(for semantic: MDLMaterialSemantic,
                               in material: MDLMaterial?,
                               textureOrigin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {
        guard let material else { return nil }
        
        var newTexture: MTLTexture!
        
        if semantic == .baseColor {
            print("\(material.name) num of properties with semantic baseColor: \(material.properties(with: semantic).count)")
        }
        
        for property in material.properties(with: semantic) {
            switch property.type {
                case .string:
                    print("Material property is string!")
                    if let stringValue = property.stringValue {
                        print("Material property string value: \(stringValue)")
                        if let cachedTexture = Self.StringToTextureCache[stringValue] {
                            newTexture = cachedTexture
                        } else {
                            let options = Self.MakeTextureLoaderOptions(textureOrigin: textureOrigin,
                                                                        generateMipmaps: true)
                            if let tex = try? Self.textureLoader.newTexture(name: stringValue,
                                                                            scaleFactor: 1.0,
                                                                            bundle: nil,
                                                                            options: options) {
                                newTexture = tex
                                Self.StringToTextureCache[stringValue] = newTexture
                            }
                        }
                    }
                case .URL:
                    print("Material property is url!")
                    if let newTexture {
                        print("[Material texture] Material prop is URL; newTexture has already been set: \(newTexture)")
                    }
                
                    if let textureURL = property.urlValue {
                        if let cachedTexture = Self.UrlToTextureCache[textureURL] {
                            newTexture = cachedTexture
                        } else {
                            let options = Self.MakeTextureLoaderOptions(textureOrigin: textureOrigin,
                                                                        generateMipmaps: true)
                            if let tex = try? Self.textureLoader.newTexture(URL: textureURL, options: options) {
                                newTexture = tex
                                Self.UrlToTextureCache[textureURL] = newTexture
                            }
                        }
                    }
                case .texture:
                    print("Material property is texture!")
                    if let newTexture {
                        print("[TextureLoader texture] Material prop is texture; newTexture has already been set: \(newTexture)")
                    }
                    
                    let sourceTexture = property.textureSamplerValue!.texture!
                
                    if let cachedTexture = Self.MdlToTextureCache[sourceTexture] {
                        newTexture = cachedTexture
                    } else {
                        let options = Self.MakeTextureLoaderOptions(textureOrigin: textureOrigin,
                                                                    generateMipmaps: sourceTexture.mipLevelCount > 1)
                        if let tex = try? Self.textureLoader.newTexture(texture: sourceTexture, options: options) {
                            newTexture = tex
                            Self.MdlToTextureCache[sourceTexture] = newTexture
                        }
                    }
                
                case .color:
                    print("Material property is color!")
                    if let newTexture {
                        print("[Material texture] Material prop is color; newTexture has already been set: \(newTexture)")
                        break
                    }
                    
                    let color = float4(Float(property.color!.components![0]),
                                       Float(property.color!.components![1]),
                                       Float(property.color!.components![2]),
                                       Float(property.color!.components![3]))
                    
                    if let cachedTexture = Self.ColorToTextureCache[color] {
                        newTexture = cachedTexture
                    } else {
                        newTexture = Self.MakeSolid2DTexture(device: Engine.Device, color: color)
                        Self.ColorToTextureCache[color] = newTexture
                    }
                    
                case .buffer:
                    print("Material property is a buffer!")
                case .matrix44:
                    print("Material property is 4x4 matrix!")
                case .float, .float2, .float3, .float4:
                    print("Material property is float!")
                case .none:
                    print("Material property is none!")
                default:
                    fatalError("Texture data for material property not found - name: \(material.name), class name: \(material.className), debug desc: \(material.debugDescription)")
//                    print("In default block")
            }
        }
        
        return newTexture
    }
    
    public static func MakeTextureLoaderOptions(textureOrigin: MTKTextureLoader.Origin,
                                                generateMipmaps: Bool) -> [MTKTextureLoader.Option: Any] {
        return [
            .origin: textureOrigin as Any,
            .generateMipmaps: generateMipmaps,
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]
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
    
    public static func PrintCacheInfo() {
        print("[TextureLoader] StringToTextureCache.count: \(StringToTextureCache.count)")
        print("[TextureLoader] UrlToTextureCache.count: \(UrlToTextureCache.count)")
        print("[TextureLoader] MdlToTextureCache.count: \(MdlToTextureCache.count)")
        print("[TextureLoader] ColorToTextureCache.count: \(ColorToTextureCache.count)")
    }
}
