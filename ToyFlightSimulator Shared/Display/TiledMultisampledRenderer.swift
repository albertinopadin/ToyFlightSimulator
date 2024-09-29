//
//  TiledMultisampledRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/24/24.
//

import MetalKit

class TiledMultisampledRenderer: Renderer {
    private static let tileWidth = 16
    private static let tileHeight = 16
    private static let imageBlockSampleLength = 32
    
    private static var ShadowTextureSize: Int = 8_192
    private var gBufferTextures = TiledDeferredGBufferTextures()
    
    private static var defaultSampleCount: Int = 4
    
    private var shadowTexture: MTLTexture
    private var shadowRenderPassDescriptor: MTLRenderPassDescriptor
    
    private var particleComputePipelineState: MTLComputePipelineState
    
    private let tiledDeferredRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        
//        descriptor.tileWidth = TiledMultisampledRenderer.tileWidth
//        descriptor.tileHeight = TiledMultisampledRenderer.tileHeight
//        descriptor.imageblockSampleLength = TiledMultisampledRenderer.imageBlockSampleLength
        
        let renderTargets: [TFSRenderTargetIndices] = [
            TFSRenderTargetAlbedo,
            TFSRenderTargetNormal,
            TFSRenderTargetPosition
        ]
        
        for renderTarget in renderTargets {
            descriptor.colorAttachments[renderTarget.index].loadAction = .clear
            descriptor.colorAttachments[renderTarget.index].storeAction = .dontCare
        }
        
        // To make empty space (no nodes/skybox) look black instead of Snow...
        descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
        descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
//        descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .multisampleResolve
        return descriptor
    }()
    
    private let msaaRenderPassDescriptor: MTLRenderPassDescriptor = {
       let descriptor = MTLRenderPassDescriptor()
        
        descriptor.tileWidth = TiledMultisampledRenderer.tileWidth
        descriptor.tileHeight = TiledMultisampledRenderer.tileHeight
        descriptor.imageblockSampleLength = TiledMultisampledRenderer.imageBlockSampleLength
        
        descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
        descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
        descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .multisampleResolve
        return descriptor
    }()
    
    private let compositeRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
        descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
        descriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
        return descriptor
    }()
    
    override var metalView: MTKView {
        didSet {
            metalView.depthStencilPixelFormat = .depth32Float
            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize)
        }
    }
    
    override var sampleCount: Int {
        didSet {
            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize, sampleCount: sampleCount)
        }
    }
    
    static func makeMultisampleTexture(label: String, size: CGSize, sampleCount: Int) -> MTLTexture {
        let multisampleTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                                    width: Int(size.width),
                                                                                    height: Int(size.height),
                                                                                    mipmapped: false)
        multisampleTextureDescriptor.textureType = .type2DMultisample
        multisampleTextureDescriptor.sampleCount = sampleCount
        multisampleTextureDescriptor.usage = .renderTarget
//        multisampleTextureDescriptor.storageMode = .memoryless
        multisampleTextureDescriptor.storageMode = .private
        
        guard let multisampleTexture = Engine.Device.makeTexture(descriptor: multisampleTextureDescriptor) else {
            fatalError("Failed to create multisample texture")
        }
        multisampleTexture.label = label
        return multisampleTexture
    }
    
    static func makeMultisampleResolveTexture(label: String, size: CGSize) -> MTLTexture {
        let resolveTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                                width: Int(size.width),
                                                                                height: Int(size.height),
                                                                                mipmapped: false)
        resolveTextureDescriptor.textureType = .type2D
        resolveTextureDescriptor.storageMode = .private
        resolveTextureDescriptor.usage = [.shaderRead, .renderTarget]
        
        guard let resolveTexture = Engine.Device.makeTexture(descriptor: resolveTextureDescriptor) else {
            fatalError("Failed to create multisample resolve texture")
        }
        resolveTexture.label = label
        return resolveTexture
    }
    
    static func makeShadowTexture(label: String, sampleCount: Int) -> MTLTexture {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                               width: Self.ShadowTextureSize,
                                                                               height: Self.ShadowTextureSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.resourceOptions = .storageModePrivate
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        
        if (sampleCount > 1) {
            shadowTextureDescriptor.textureType = .type2DMultisample
            shadowTextureDescriptor.sampleCount = sampleCount
        }
        
        guard let shadowTex = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor) else {
            fatalError("Failed to create shadow texture")
        }
        shadowTex.label = label
        return shadowTex
    }
    
    static func makeShadowRenderPassDescriptor(shadowTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .store
        return mShadowRenderPassDescriptor
    }
    
    init() {
//        shadowTexture = Self.makeShadowTexture(label: "Shadow Texture", sampleCount: Self.defaultSampleCount)
        shadowTexture = Self.makeShadowTexture(label: "Shadow Texture", sampleCount: 1)
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowTexture: shadowTexture)
        particleComputePipelineState = Graphics.ComputePipelineStates[.Particle]
        super.init(type: .TiledDeferredMSAA)
        self.sampleCount = Self.defaultSampleCount
    }
    
    init(_ mtkView: MTKView) {
        shadowTexture = Self.makeShadowTexture(label: "Shadow Texture", sampleCount: 1)
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowTexture: shadowTexture)
        particleComputePipelineState = Graphics.ComputePipelineStates[.Particle]
        super.init(mtkView, type: .TiledDeferredMSAA)
        self.sampleCount = Self.defaultSampleCount
    }
    
    func setMSAATextures(_ renderPassDescriptor: MTLRenderPassDescriptor, size: CGSize) {
        let msaaTexture = Self.makeMultisampleTexture(label: "Multisample Texture", size: size, sampleCount: self.sampleCount)
        renderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = msaaTexture
        
        let resolveTexture = Self.makeMultisampleResolveTexture(label: "Multisample Resolve Texture", size: size)
        renderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].resolveTexture = resolveTexture
    }
    
    func setGBufferTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.colorAttachments[TFSRenderTargetAlbedo.index].texture = gBufferTextures.albedoTexture
        renderPassDescriptor.colorAttachments[TFSRenderTargetNormal.index].texture = gBufferTextures.normalTexture
        renderPassDescriptor.colorAttachments[TFSRenderTargetPosition.index].texture = gBufferTextures.positionTexture
        setDepthAndStencilTextures(renderPassDescriptor)
    }
    
    func setDepthAndStencilTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.depthAttachment.texture = gBufferTextures.depthTexture
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.stencilAttachment.texture = gBufferTextures.depthTexture
        renderPassDescriptor.stencilAttachment.storeAction = .dontCare
    }
    
    func encodeShadowPass(into commandBuffer: MTLCommandBuffer) {
        encodeRenderPass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Pass") { renderEncoder in
            encodeRenderStage(using: renderEncoder, label: "Shadow Texture Stage") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredShadow])
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                DrawManager.Draw(with: renderEncoder)
            }
        }
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Tiled GBuffer Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredGBuffer])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            renderEncoder.setFragmentTexture(shadowTexture, index: TFSTextureIndexShadow.index)
            DrawManager.Draw(with: renderEncoder)
        }
    }
    
    func encodeLightingStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Lighting Stage") {
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredLight])
            encodeDirectionalLightStage(using: renderEncoder)
            encodePointLightStage(using: renderEncoder)
        }
    }
    
    func encodeDirectionalLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Directional Light Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredDirectionalLight])
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Point Light Stage") {
            DrawManager.DrawPointLights(with: renderEncoder)
        }
    }
    
    func encodeTransparencyStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredTransparency])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.Draw(with: renderEncoder, withTransparency: true)
        }
    }
    
    func encodeParticleComputePass(into commandBuffer: MTLCommandBuffer) {
        encodeComputePass(into: commandBuffer, label: "Particle Compute Pass") { computeEncoder in
            computeEncoder.setComputePipelineState(particleComputePipelineState)
            let threadsPerGroup = MTLSize(width: particleComputePipelineState.threadExecutionWidth,
                                          height: 1,
                                          depth: 1)
            SceneManager.Compute(with: computeEncoder, threadsPerGroup: threadsPerGroup)
        }
    }
    
    func encodeParticleRenderStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Particle Render Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Particle])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawParticles(with: renderEncoder)
        }
    }
    
    func encodeCopyToMultisampleTextureStage(using renderEncoder: MTLRenderCommandEncoder, viewTexture: MTLTexture) {
        encodeRenderStage(using: renderEncoder, label: "Copy to Multisample Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredComposite])
            renderEncoder.setFragmentTexture(viewTexture, index: TFSRenderTargetLighting.index)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodeMSAAStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "MSAA Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredMSAA])
            renderEncoder.dispatchThreadsPerTile(MTLSize(width: 16, height: 16, depth: 1))
        }
    }
    
    override func draw(in view: MTKView) {
//        view.sampleCount = self.sampleCount  // Probably need this as the resolve texture
        
        // Updates scene:
        super.draw(in: view)
        
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeShadowPass(into: commandBuffer)
        }
        
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "GBuffer & Lighting Commands"
            
            tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = view.currentRenderPassDescriptor?.colorAttachments[TFSRenderTargetLighting.index].texture
            
//            setMSAATextures(tiledDeferredRenderPassDescriptor, size: CGSize(width: Int(Renderer.ScreenSize.x),
//                                                                            height: Int(Renderer.ScreenSize.y)))
            
            encodeParticleComputePass(into: commandBuffer)
            
            encodeRenderPass(into: commandBuffer,
                             using: tiledDeferredRenderPassDescriptor,
                             label: "GBuffer & Lighting Pass") { renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                SceneManager.SetPointLightData(with: renderEncoder)
                
                encodeGBufferStage(using: renderEncoder)
                encodeLightingStage(using: renderEncoder)
                encodeTransparencyStage(using: renderEncoder)
                encodeParticleRenderStage(using: renderEncoder)
            }
            
            var viewTexture = view.currentDrawable!.texture
//            compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = viewTexture
//            encodeRenderPass(into: commandBuffer, using: compositeRenderPassDescriptor, label: "Copy to Multisample Pass") {
//                renderEncoder in
//                encodeCopyToMultisampleTextureStage(using: renderEncoder, viewTexture: viewTexture)
//            }
            
            if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                blitEncoder.copy(from: viewTexture,
                                 to: msaaRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index]!.texture!)
            }
            
            encodeRenderPass(into: commandBuffer, using: msaaRenderPassDescriptor, label: "MSAA Pass") { renderEncoder in
                encodeMSAAStage(using: renderEncoder)
            }
            
            let resolveTexture = msaaRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].resolveTexture
            compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = resolveTexture
            
            encodeRenderPass(into: commandBuffer, using: compositeRenderPassDescriptor, label: "CompositePass") {
                renderEncoder in
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledDeferredComposite])
                renderEncoder.setFragmentTexture(resolveTexture, index: TFSRenderTargetLighting.index)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            
            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
        }
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if !size.width.isNaN && !size.height.isNaN && !size.width.isInfinite && !size.height.isInfinite {
            updateDrawableSize(size: size, sampleCount: self.sampleCount)
        }
    }
    
    func updateDrawableSize(size: CGSize, sampleCount: Int = 1) {
//        gBufferTextures.makeTextures(device: Engine.Device,
//                                     size: size,
//                                     storageMode: .memoryless,
//                                     sampleCount: sampleCount)
        gBufferTextures.makeTextures(device: Engine.Device,
                                     size: size,
                                     storageMode: .memoryless,
                                     sampleCount: 1)
        // Re-set GBuffer textures in the view render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(tiledDeferredRenderPassDescriptor)
//        setMSAATextures(tiledDeferredRenderPassDescriptor, size: size)  // TODO - maybe need a diff render pass desc here
        setMSAATextures(msaaRenderPassDescriptor, size: size)
        updateScreenSize(size: size)
    }
}
