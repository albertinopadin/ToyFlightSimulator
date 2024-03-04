//
//  SinglePassDeferredRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/28/23.
//

import MetalKit

class SinglePassDeferredLightingRenderer: Renderer {
    // Create quad for fullscreen composition drawing
    private let _quadVertices: [TFSSimpleVertex] = [
        .init(position: .init(x: -1, y: -1)),
        .init(position: .init(x: -1, y:  1)),
        .init(position: .init(x:  1, y: -1)),
        
        .init(position: .init(x:  1, y: -1)),
        .init(position: .init(x: -1, y:  1)),
        .init(position: .init(x:  1, y:  1))
    ]
    
    private let _quadVertexBuffer: MTLBuffer!
    
    private static var ShadowMapSize: Int = 8_192
    var shadowMap: MTLTexture?
    var shadowRenderPassDescriptor: MTLRenderPassDescriptor!
    
    private let _gBufferAndLightingRenderPassDescriptor: MTLRenderPassDescriptor = {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[TFSRenderTargetAlbedo.index].storeAction = .dontCare
        descriptor.colorAttachments[TFSRenderTargetNormal.index].storeAction = .dontCare
        descriptor.colorAttachments[TFSRenderTargetDepth.index].storeAction = .dontCare
        
        // To make empty space (no nodes/skybox) look black instead of Snow...
        descriptor.colorAttachments[TFSRenderTargetLighting.index].loadAction = .clear
        descriptor.colorAttachments[TFSRenderTargetLighting.index].clearColor = Preferences.ClearColor
        return descriptor
    }()
    
    private var gBufferTextures = SinglePassDeferredGBufferTextures()
    
    override var metalView: MTKView {
        didSet {
            metalView.depthStencilPixelFormat = .depth32Float_stencil8
            let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
            updateDrawableSize(size: drawableSize)
        }
    }
    
    public static func makeShadowMap(label: String) -> MTLTexture! {
        let shadowTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                               width: Self.ShadowMapSize,
                                                                               height: Self.ShadowMapSize,
                                                                               mipmapped: false)
        shadowTextureDescriptor.resourceOptions = .storageModePrivate
        shadowTextureDescriptor.usage = [.renderTarget, .shaderRead]
        let sm = Engine.Device.makeTexture(descriptor: shadowTextureDescriptor)!
        sm.label = label
        
        return sm
    }
    
    public static func createShadowRenderPassDescriptor(shadowMapTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let mShadowRenderPassDescriptor = MTLRenderPassDescriptor()
        mShadowRenderPassDescriptor.depthAttachment.texture = shadowMapTexture
        mShadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        mShadowRenderPassDescriptor.depthAttachment.storeAction = .store
        return mShadowRenderPassDescriptor
    }
    
    init() {
        _quadVertexBuffer = Engine.Device.makeBuffer(bytes: _quadVertices,
                                                     length: MemoryLayout<TFSSimpleVertex>.stride * _quadVertices.count)
        super.init(type: .SinglePassDeferredLighting)
        createShadowMap()
    }
    
    init(_ mtkView: MTKView) {
        _quadVertexBuffer = Engine.Device.makeBuffer(bytes: _quadVertices,
                                                     length: MemoryLayout<TFSSimpleVertex>.stride * _quadVertices.count)
        super.init(mtkView, type: .SinglePassDeferredLighting)
        createShadowMap()
        let drawableSize = CGSize(width: Double(Renderer.ScreenSize.x), height: Double(Renderer.ScreenSize.y))
        print("[SPDL Renderer init] drawable size: \(drawableSize)")
        updateDrawableSize(size: drawableSize)
    }
    
    func createShadowMap() {
        shadowMap = Self.makeShadowMap(label: "Shadow Map")
        shadowRenderPassDescriptor = Self.createShadowRenderPassDescriptor(shadowMapTexture: shadowMap!)
    }
    
    func setGBufferTextures(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentTexture(gBufferTextures.albedoSpecular, index: TFSRenderTargetAlbedo.index)
        renderEncoder.setFragmentTexture(gBufferTextures.normalShadow, index: TFSRenderTargetNormal.index)
        renderEncoder.setFragmentTexture(gBufferTextures.depth, index: TFSRenderTargetDepth.index)
    }
    
    func setGBufferTextures(_ renderPassDescriptor: MTLRenderPassDescriptor) {
        renderPassDescriptor.colorAttachments[TFSRenderTargetAlbedo.index].texture = gBufferTextures.albedoSpecular
        renderPassDescriptor.colorAttachments[TFSRenderTargetNormal.index].texture = gBufferTextures.normalShadow
        renderPassDescriptor.colorAttachments[TFSRenderTargetDepth.index].texture = gBufferTextures.depth
    }
    
    func encodeGBufferStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "GBuffer Generation Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredGBufferMaterial])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.GBufferGeneration])
            // NOTE: For some reason, setting cull mode to back makes meshes appear 'extruded' or turned inside out.
            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setFragmentTexture(shadowMap, index: TFSTextureIndexShadow.index)
            SceneManager.SetDirectionalLightConstants(with: renderEncoder)
            SceneManager.RenderGBuffer(with: renderEncoder)
        }
    }
    
    func encodeDirectionalLightingStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Directional Lighting Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredDirectionalLighting])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.DirectionalLighting])
            renderEncoder.setCullMode(.back)
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setVertexBuffer(_quadVertexBuffer,
                                          offset: 0,
                                          index: TFSBufferIndexMeshPositions.index)
            SceneManager.SetSceneConstants(with: renderEncoder)
            SceneManager.SetDirectionalLightConstants(with: renderEncoder)
            
            // Draw full screen quad
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
    
    func encodeLightMaskStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Point Light Mask Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.LightMask])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LightMask])
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setCullMode(.front)
            SceneManager.SetPointLightConstants(with: renderEncoder)
            SceneManager.RenderPointLightMeshes(with: renderEncoder)
        }
    }
    
    func encodePointLightStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Point Light Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.SinglePassDeferredPointLight])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.PointLight])  // <--- This is causing issues
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
            renderEncoder.setStencilReferenceValue(128)
            renderEncoder.setCullMode(.back)
//            SceneManager.SetPointLightConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetPointLightData(with: renderEncoder)
            SceneManager.RenderPointLights(with: renderEncoder)
        }
    }
    
    func encodeSkyboxStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Skybox Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Skybox])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Skybox])
//            renderEncoder.setCullMode(.front)
            renderEncoder.setCullMode(.back)  //<-- This or not setting the cull mode works. WTF?
            SceneManager.Render(with: renderEncoder, renderPipelineStateType: .Skybox, applyMaterials: false)
        }
    }
    
    // TODO: Must be doing something wrong because there are strange artifacts, like:
    //       - Seeing shadow of bombs and landing gear through aircraft
    //       - Shadows on 'back side' of jet look odd
    //       - If I pitch or roll jet, shadows look very different on adjacent panels in mesh.
    // ADDENDUM: Might fix issues if I implement soft shadows...
    func encodeShadowMapPass(into commandBuffer: MTLCommandBuffer) {
        encodePass(into: commandBuffer, using: shadowRenderPassDescriptor, label: "Shadow Map Pass") { renderEncoder in
            encodeStage(using: renderEncoder, label: "Shadow Generation Stage") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.ShadowGeneration])
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.ShadowGeneration])
//                renderEncoder.setCullMode(.back)
//                renderEncoder.setCullMode(.front)
//                renderEncoder.setDepthBias(0.015, slopeScale: 7, clamp: 0.02)
                renderEncoder.setDepthBias(0.1, slopeScale: 1, clamp: 0.0)
                SceneManager.SetDirectionalLightConstants(with: renderEncoder)
                SceneManager.RenderShadows(with: renderEncoder)
            }
        }
    }
    
    // For testing:
    func encodeIcosahedronStage(using renderEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderEncoder, label: "Icosahedron Stage") {
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Icosahedron])
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.Less])
//            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.DepthWriteDisabled])
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.PointLight])
            renderEncoder.setStencilReferenceValue(128)
            SceneManager.Render(with: renderEncoder, renderPipelineStateType: .Icosahedron)
        }
    }
    
    override func draw(in view: MTKView) {
        // FIXME - this should be set independent of the frame rate:
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        var commandBuffer = beginFrame()
        commandBuffer.label = "Shadow Commands"
        
        encodeShadowMapPass(into: commandBuffer)
        commandBuffer.commit()
        
        commandBuffer = beginDrawableCommands()
        commandBuffer.label = "GBuffer & Lighting Commands"
        
        if let drawableTexture = view.currentDrawable?.texture {
            _gBufferAndLightingRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].texture = drawableTexture
            _gBufferAndLightingRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
            _gBufferAndLightingRenderPassDescriptor.stencilAttachment.texture = view.depthStencilTexture
            
            encodePass(into: commandBuffer, using: _gBufferAndLightingRenderPassDescriptor, label: "GBuffer & Lighting Pass") {
                renderEncoder in
                SceneManager.SetSceneConstants(with: renderEncoder)
                
                encodeGBufferStage(using: renderEncoder)
                encodeDirectionalLightingStage(using: renderEncoder)
                encodeLightMaskStage(using: renderEncoder)
                encodePointLightStage(using: renderEncoder)
                encodeIcosahedronStage(using: renderEncoder)
                encodeSkyboxStage(using: renderEncoder)
            }
        }
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
    
    override func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("[SinglePass drawableSizeWillChange] new size: \(size)")
        if !size.width.isNaN && !size.height.isNaN && !size.width.isInfinite && !size.height.isInfinite {
            updateDrawableSize(size: size)
        }
    }
    
    func updateDrawableSize(size: CGSize) {
        gBufferTextures.makeTextures(device: Engine.Device, size: size, storageMode: .memoryless)
        
        // Re-set GBuffer textures in the view render pass descriptor after they have been reallocated by a resize
        setGBufferTextures(_gBufferAndLightingRenderPassDescriptor)
        updateScreenSize(size: size)
    }
}
