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
    
    public static func Texture(name: String, textureOrigin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {
        if let cachedTexture = Self.StringToTextureCache[name] {
            return cachedTexture
        } else {
            let options = Self.MakeTextureLoaderOptions(textureOrigin: textureOrigin,
                                                        generateMipmaps: true)
            if let newTexture = try? Self.textureLoader.newTexture(name: name,
                                                                   scaleFactor: 1.0,
                                                                   bundle: nil,
                                                                   options: options) {
                Self.StringToTextureCache[name] = newTexture
                return newTexture
            }
        }
        
        return nil
    }
    
    public static func Texture(url: URL, textureOrigin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {
        if let cachedTexture = Self.UrlToTextureCache[url] {
            return cachedTexture
        } else {
            let options = Self.MakeTextureLoaderOptions(textureOrigin: textureOrigin,
                                                        generateMipmaps: true)
            if let newTexture = try? Self.textureLoader.newTexture(URL: url, options: options) {
                Self.UrlToTextureCache[url] = newTexture
                return newTexture
            }
        }
        
        return nil
    }
    
    public static func Texture(mdlTexture: MDLTexture, textureOrigin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {
        if let cachedTexture = Self.MdlToTextureCache[mdlTexture] {
            return cachedTexture
        } else {
            let options = Self.MakeTextureLoaderOptions(textureOrigin: textureOrigin,
                                                        generateMipmaps: mdlTexture.mipLevelCount > 1)
            if let newTexture = try? Self.textureLoader.newTexture(texture: mdlTexture, options: options) {
                Self.MdlToTextureCache[mdlTexture] = newTexture
                return newTexture
            }
        }
        
        return nil
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
    }
}
