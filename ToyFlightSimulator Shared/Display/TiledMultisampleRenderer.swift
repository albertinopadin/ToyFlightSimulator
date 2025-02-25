//
//  TiledMultisampleRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/28/24.
//

import MetalKit

class TiledMultisampleRenderer: Renderer {
    private static let sampleCount: Int = 4
    
    private static let tileWidth = 16
    private static let tileHeight = 16
    private static let imageBlockSampleLength = 32
    
    private static var ShadowTextureSize: Int = 8_192
    
    private var gBufferTextures = TiledDeferredGBufferTextures()
    
    private var shadowMultisampleTexture: MTLTexture
    private var shadowResolveTexture: MTLTexture
    private var shadowRenderPassDescriptor: MTLRenderPassDescriptor
    
    private var particleComputePipelineState: MTLComputePipelineState
    
    private let tiledDeferredRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        
        descriptor.tileWidth = TiledMultisampleRenderer.tileWidth
        descriptor.tileHeight = TiledMultisampleRenderer.tileHeight
        descriptor.imageblockSampleLength = TiledMultisampleRenderer.imageBlockSampleLength
        
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
    
    static func makeShadowTexture(label: String, sampleCount: Int) -> MTLTexture {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                               width: Self.ShadowTextureSize,
                                                                               height: Self.ShadowTextureSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.resourceOptions = .storageModePrivate
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        
        if sampleCount > 1 {
            shadowTextureDescriptor.textureType = .type2DMultisample
            shadowTextureDescriptor.sampleCount = sampleCount
        }
        
        guard let shadowTex = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor) else {
            fatalError("Failed to create shadow texture")
        }
        shadowTex.label = label
        return shadowTex
    }
    
    static func makeShadowRenderPassDescriptor(shadowTexture: MTLTexture,
                                               resolveTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowTexture
        mShadowRenderPassDescriptor.depthAttachment.resolveTexture = resolveTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .multisampleResolve
        return mShadowRenderPassDescriptor
    }
    
    init() {
        shadowMultisampleTexture = Self.makeShadowTexture(label: "Shadow Multisample Texture",
                                                          sampleCount: Self.sampleCount)
        shadowResolveTexture = Self.makeShadowTexture(label: "Shadow Resolve Texture",
                                                      sampleCount: 1)
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowTexture: shadowMultisampleTexture,
                                                                         resolveTexture: shadowResolveTexture)
        particleComputePipelineState = Graphics.ComputePipelineStates[.Particle]
        super.init(type: .TiledDeferredMSAA)
    }
    
    init(_ mtkView: MTKView) {
        shadowMultisampleTexture = Self.makeShadowTexture(label: "Shadow Multisample Texture",
                                                          sampleCount: Self.sampleCount)
        shadowResolveTexture = Self.makeShadowTexture(label: "Shadow Resolve Texture",
                                                      sampleCount: 1)
        shadowRenderPassDescriptor = Self.makeShadowRenderPassDescriptor(shadowTexture: shadowMultisampleTexture,
                                                                         resolveTexture: shadowResolveTexture)
        particleComputePipelineState = Graphics.ComputePipelineStates[.Particle]
        super.init(mtkView, type: .TiledDeferredMSAA)
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
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAShadow])
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredShadow])
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                DrawManager.Draw(with: renderEncoder)
            }
        }
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Tiled GBuffer Stage") { [weak self] in
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAGBuffer])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            renderEncoder.setFragmentTexture(self?.shadowResolveTexture, index: TFSTextureIndexShadow.index)
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
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAADirectionalLight])
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        DrawManager.DrawPointLights(with: renderEncoder)
    }
    
    func encodeTransparencyStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Transparent Object Rendering") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAATransparency])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.Draw(with: renderEncoder, withTransparency: true)
        }
    }
    
    func encodeParticleComputePass(into commandBuffer: MTLCommandBuffer) {
        encodeComputePass(into: commandBuffer, label: "Particle Compute Pass") { [weak self] computeEncoder in
            computeEncoder.setComputePipelineState(self!.particleComputePipelineState)
            let threadsPerGroup = MTLSize(width: self!.particleComputePipelineState.threadExecutionWidth,
                                          height: 1,
                                          depth: 1)
            SceneManager.Compute(with: computeEncoder, threadsPerGroup: threadsPerGroup)
        }
    }
    
    func encodeParticleRenderStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Particle Render Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ParticleMSAA])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawParticles(with: renderEncoder)
        }
    }
    
    func encodeMSAAResolveStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "MSAA Resolve Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TiledMSAAAverageResolve])
            renderEncoder.dispatchThreadsPerTile(MTLSize(width: 16, height: 16, depth: 1))
        }
    }
    
    func encodeCompositeStage(using renderEncoder: MTLRenderCommandEncoder) {
        let resolveTexture = tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].resolveTexture
        encodeRenderStage(using: renderEncoder, label: "Composite Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Composite])
            renderEncoder.setFragmentTexture(resolveTexture, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    var firstRun: Bool = true
    
    override func draw(in view: MTKView) {
        view.sampleCount = Self.sampleCount
        
        if firstRun {
            let screenSize = CGSize(width: CGFloat(Renderer.ScreenSize.x),
                                    height: CGFloat(Renderer.ScreenSize.y))
            updateDrawableSize(size: screenSize)
            firstRun.toggle()
        }
        
        // Updates scene:
        super.draw(in: view)
        
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow Commands"
            encodeShadowPass(into: commandBuffer)
        }
        
        if let drawable = view.currentDrawable {
            runDrawableCommands { [weak self] commandBuffer in
                commandBuffer.label = "GBuffer & Lighting Commands"
                let viewColorAttachment = view.currentRenderPassDescriptor!.colorAttachments[TFSRenderTargetLighting.index]
                self?.tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index] = viewColorAttachment
                
                self?.encodeParticleComputePass(into: commandBuffer)
                
                self?.encodeRenderPass(into: commandBuffer,
                                       using: self!.tiledDeferredRenderPassDescriptor,
                                 label: "GBuffer & Lighting Pass") { renderEncoder in
                    SceneManager.SetSceneConstants(with: renderEncoder)
                    SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                    SceneManager.SetPointLightData(with: renderEncoder)
                    
                    self?.encodeGBufferStage(using: renderEncoder)
                    self?.encodeLightingStage(using: renderEncoder)
                    self?.encodeTransparencyStage(using: renderEncoder)
                    self?.encodeParticleRenderStage(using: renderEncoder)
                    
                    self?.encodeMSAAResolveStage(using: renderEncoder)
                }
                
                self?.compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].storeAction = .store
                self?.compositeRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawable.texture
                
                self?.encodeRenderPass(into: commandBuffer,
                                       using: self!.compositeRenderPassDescriptor,
                                       label: "Composite Pass") { renderEncoder in
                    self?.encodeCompositeStage(using: renderEncoder)
                }
            
                commandBuffer.present(drawable)
            }
        }
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if !size.width.isNaN && !size.height.isNaN && !size.width.isInfinite && !size.height.isInfinite {
            updateDrawableSize(size: size)
        }
    }
    
    func updateDrawableSize(size: CGSize) {
        gBufferTextures.makeTextures(device: Engine.Device,
                                     size: size,
                                     storageMode: .memoryless,
                                     sampleCount: Self.sampleCount)
        // Re-set GBuffer textures in the view render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(tiledDeferredRenderPassDescriptor)
        updateScreenSize(size: size)
    }
}
