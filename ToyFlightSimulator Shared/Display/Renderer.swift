//
//  Renderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

import Metal
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    public static var ScreenSize = float2(100, 100)
    public static var AspectRatio: Float { return ScreenSize.x / ScreenSize.y }
    public static let ShadowMapSize: Int = 16_384
    
    // The max number of command buffers in flight
    let maxFramesInFlight = 3
    // The semaphore used to control GPU-CPU synchronization of frames.
    private let inFlightSemaphore: DispatchSemaphore
    
    var baseRenderPassDescriptor: MTLRenderPassDescriptor!
    
    let shadowMap: MTLTexture!
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor!
    
    public let rendererType: RendererType
    
    private var _metalView: MTKView!
    public var metalView: MTKView {
        get {
            return _metalView
        }
        
        set {
            _metalView = newValue
            updateScreenSize(size: _metalView.drawableSize)
            createBaseRenderPassDescriptor(screenWidth: Int(Renderer.ScreenSize.x),
                                           screenHeight: Int(Renderer.ScreenSize.y))
            _metalView.delegate = self
        }
    }
    
    init(type: RendererType) {
        self.rendererType = type
        
        inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        
        shadowMap = Renderer.makeShadowMap(label: "Shadow Map")
        
        super.init()
        createShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
    }
    
    init(_ mtkView: MTKView, type: RendererType) {
        self.rendererType = type
        
        inFlightSemaphore = DispatchSemaphore(value: maxFramesInFlight)
        
        shadowMap = Renderer.makeShadowMap(label: "Shadow Map")
        
        super.init()
        
        metalView = mtkView
        createShadowRenderPassDescriptor(shadowMapTexture: shadowMap)
    }
    
    static func makeShadowMap(label: String) -> MTLTexture! {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                               width: Renderer.ShadowMapSize,
                                                                               height: Renderer.ShadowMapSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.resourceOptions = .storageModePrivate
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        let sm = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor)!
        sm.label = label
        
        return sm
    }
    
    // Heavily inspired by:
    // https://developer.apple.com/documentation/metal/metal_sample_code_library/rendering_a_scene_with_deferred_lighting_in_swift
    
    /// Perform operations necessary at the beginning of the frame.  Wait on the in flight semaphore,
    /// and get a command buffer to encode intial commands for this frame.
    func beginFrame() -> MTLCommandBuffer {
        // Wait to ensure only maxFramesInFlight are getting processed by any stage in the Metal
        //   pipeline (App, Metal, Drivers, GPU, etc)
        inFlightSemaphore.wait()
        
        // Create a new command buffer for each render pass to the current drawable
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else {
            fatalError("Failed to create a command new command buffer.")
        }
        
//        didBeginFrame()
        
        return commandBuffer
    }
    
    /// Perform operations necessary to obtain a command buffer for rendering to the drawable.  By
    /// endoding commands that are not dependant on the drawable in a separate command buffer, Metal
    /// can begin executing encoded commands for the frame (commands from the previous command buffer)
    /// before a drawable for this frame becomes avaliable.
    func beginDrawableCommands() -> MTLCommandBuffer {
        guard let commandBuffer = Engine.CommandQueue.makeCommandBuffer() else {
            fatalError("Failed to make command buffer from command queue")
        }
        
        // Add completion hander which signals inFlightSemaphore
        // when Metal and the GPU has fully finished processing the commands encoded for this frame.
        // This indicates when the dynamic buffers, written this frame, will no longer be needed by Metal and the GPU.
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        return commandBuffer
    }
    
    /// Perform cleanup operations including presenting the drawable and committing the command buffer
    /// for the current frame.  Also, when enabled, draw buffer examination elements before all this.
//    func endFrame(_ commandBuffer: MTLCommandBuffer) {
//        // Schedule a present once the framebuffer is complete using the current drawable
//        
//        if let drawable = getCurrentDrawable?() {
//            commandBuffer.present(drawable)
//        }
//        
//        // Finalize rendering here & push the command buffer to the GPU
//        commandBuffer.commit()
//    }
    
    func encodePass(into commandBuffer: MTLCommandBuffer,
                    using descriptor: MTLRenderPassDescriptor,
                    label: String,
                    _ encodingBlock: (MTLRenderCommandEncoder) -> Void) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to make render command encoder with: \(descriptor.description)")
        }
        
        renderEncoder.label = label
        encodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }
    
    func encodeStage(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    private func createBaseRenderPassDescriptor(screenWidth: Int, screenHeight: Int) {
        // --- BASE COLOR 0 TEXTURE ---
        let base0TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: screenWidth,
                                                                              height: screenHeight,
                                                                              mipmapped: false)
        // Defining render target
        base0TextureDescriptor.usage = [.renderTarget, .shaderRead]
        let tex = Engine.Device.makeTexture(descriptor: base0TextureDescriptor)
        Assets.Textures.setTexture(textureType: .BaseColorRender_0,
                                   texture: tex!)
        
        // --- BASE COLOR 1 TEXTURE ---
        let base1TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: screenWidth,
                                                                              height: screenHeight,
                                                                              mipmapped: false)
        // Defining render target
        base1TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_1,
                                   texture: Engine.Device.makeTexture(descriptor: base1TextureDescriptor)!)
        
        // --- BASE DEPTH TEXTURE ---
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: screenWidth,
                                                                              height: screenHeight,
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
        
        baseRenderPassDescriptor = MTLRenderPassDescriptor()
        baseRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        baseRenderPassDescriptor.colorAttachments[0].storeAction = .store
        baseRenderPassDescriptor.colorAttachments[0].loadAction = .clear
    
        baseRenderPassDescriptor.colorAttachments[1].texture = Assets.Textures[.BaseColorRender_1]
        baseRenderPassDescriptor.colorAttachments[1].storeAction = .store
        baseRenderPassDescriptor.colorAttachments[1].loadAction = .clear
    
        baseRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        baseRenderPassDescriptor.depthAttachment.storeAction = .store
        baseRenderPassDescriptor.depthAttachment.loadAction = .clear
    }
    
    private func createShadowRenderPassDescriptor(shadowMapTexture: MTLTexture) {
        shadowRenderPassDescriptor = MTLRenderPassDescriptor()
        shadowRenderPassDescriptor.depthAttachment.texture = shadowMapTexture
        shadowRenderPassDescriptor.depthAttachment.storeAction = .store
    }
    
    
    // --- MTKViewDelegate methods ---
    public func updateScreenSize(size: CGSize) {
        print("[Renderer updateScreenSize] new size: \(size)")
        if size.width > 0 && size.width.isFinite && size.height > 0 && size.height.isFinite {
            Renderer.ScreenSize = float2(Float(size.width), Float(size.height))
            print("[Renderer updateScreenSize] aspect ratio: \(Renderer.AspectRatio)")
            SceneManager.SetAspectRatio(Renderer.AspectRatio)
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[Renderer drawableSizeWillChange]")
        // When window is resized
        if size.width.isNaN && !size.height.isNaN {
            updateScreenSize(size: size)
        }
    }
    
    func draw(in view: MTKView) {
        
    }
}
