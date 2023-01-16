//
//  Renderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 8/25/22.
//

import Metal
import MetalKit

class Renderer: NSObject, MTKViewDelegate {
    public static var ScreenSize = float2(0, 0)
    public static var AspectRatio: Float { return ScreenSize.x / ScreenSize.y }
    
    private var _baseRenderPassDescriptor: MTLRenderPassDescriptor!
    private var _forwardRenderPassDescriptor: MTLRenderPassDescriptor!
    private var _shadowRenderPassDescriptor: MTLRenderPassDescriptor!
    
    private var _depthPassTexture: MTLTexture!
    private var _depthRenderPassDescriptor: MTLRenderPassDescriptor!
    
    private let _optimalTileSize: MTLSize = MTLSize(width: 32, height: 16, depth: 1)
    
    init(_ mtkView: MTKView) {
        super.init()
        updateScreenSize(view: mtkView)
        createForwardRenderPassDescriptor()
//        createShadowRenderPassDescriptor()
        createDepthRenderPassDescriptor()
        mtkView.delegate = self
    }
    
    private func createBaseRenderPassDescriptor() {
        // --- BASE COLOR 0 TEXTURE ---
        let base0TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        base0TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_0,
                                   texture: Engine.Device.makeTexture(descriptor: base0TextureDescriptor)!)
        
        // --- BASE COLOR 1 TEXTURE ---
        let base1TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        base1TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_1,
                                   texture: Engine.Device.makeTexture(descriptor: base1TextureDescriptor)!)
        
        // --- BASE DEPTH TEXTURE ---
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
        
        _baseRenderPassDescriptor = MTLRenderPassDescriptor()
        _baseRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        _baseRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _baseRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        _baseRenderPassDescriptor.colorAttachments[1].texture = Assets.Textures[.BaseColorRender_1]
        _baseRenderPassDescriptor.colorAttachments[1].storeAction = .store
        _baseRenderPassDescriptor.colorAttachments[1].loadAction = .clear
        
        _baseRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _baseRenderPassDescriptor.depthAttachment.storeAction = .store
        _baseRenderPassDescriptor.depthAttachment.loadAction = .clear
        
        // For Order-Independent Blending:
        _baseRenderPassDescriptor.tileWidth = _optimalTileSize.width
        _baseRenderPassDescriptor.tileHeight = _optimalTileSize.height
        _baseRenderPassDescriptor.imageblockSampleLength = Graphics.RenderPipelineStates[.OrderIndependentTransparent].imageblockSampleLength
    }
    
    private func createForwardRenderPassDescriptor() {
        // --- BASE COLOR 0 TEXTURE ---
        let base0TextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        base0TextureDescriptor.usage = [.renderTarget, .shaderRead]
        Assets.Textures.setTexture(textureType: .BaseColorRender_0,
                                   texture: Engine.Device.makeTexture(descriptor: base0TextureDescriptor)!)
        
        // --- BASE DEPTH TEXTURE ---
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: Int(Renderer.ScreenSize.x),
                                                                              height: Int(Renderer.ScreenSize.y),
                                                                              mipmapped: false)
        // Defining render target
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        Assets.Textures.setTexture(textureType: .BaseDepthRender,
                                   texture: Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!)
        
        _forwardRenderPassDescriptor = MTLRenderPassDescriptor()
        _forwardRenderPassDescriptor.colorAttachments[0].texture = Assets.Textures[.BaseColorRender_0]
        _forwardRenderPassDescriptor.colorAttachments[0].storeAction = .store
        _forwardRenderPassDescriptor.colorAttachments[0].loadAction = .clear
        
        _forwardRenderPassDescriptor.depthAttachment.texture = Assets.Textures[.BaseDepthRender]
        _forwardRenderPassDescriptor.depthAttachment.storeAction = .store
        _forwardRenderPassDescriptor.depthAttachment.loadAction = .clear
        
        // For Order-Independent Blending:
        _forwardRenderPassDescriptor.tileWidth = _optimalTileSize.width
        _forwardRenderPassDescriptor.tileHeight = _optimalTileSize.height
        _forwardRenderPassDescriptor.imageblockSampleLength = Graphics.RenderPipelineStates[.OrderIndependentTransparent].imageblockSampleLength
    }
    
//    func createShadowRenderPassDescriptor() {
//        _shadowRenderPassDescriptor = MTLRenderPassDescriptor()
//        _shadowRenderPassDescriptor.depthAttachment.loadAction = .clear
//        _shadowRenderPassDescriptor.depthAttachment.storeAction = .store
//        _shadowRenderPassDescriptor.depthAttachment.clearDepth = 1.0
//    }
//
    func createDepthRenderPassDescriptor() {
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Preferences.MainDepthPixelFormat,
                                                                              width: 4096 * 2,
                                                                              height: 4096 * 2,
                                                                              mipmapped: false)
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]
        depthTextureDescriptor.storageMode = .private
        _depthPassTexture = Engine.Device.makeTexture(descriptor: depthTextureDescriptor)!

        _depthRenderPassDescriptor = MTLRenderPassDescriptor()
        _depthRenderPassDescriptor.depthAttachment.texture = _depthPassTexture
        _depthRenderPassDescriptor.depthAttachment.storeAction = .store
        _depthRenderPassDescriptor.depthAttachment.loadAction = .clear
        _depthRenderPassDescriptor.depthAttachment.clearDepth = 1.0
    }
    
    
    // --- MTKViewDelegate methods ---
    public func updateScreenSize(view: MTKView) {
        Renderer.ScreenSize = float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // When window is resized
        updateScreenSize(view: view)
    }
    
    func depthRenderPass(commandBuffer: MTLCommandBuffer) {
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _depthRenderPassDescriptor)
        renderCommandEncoder?.label = "Depth Render Command Encoder"
        renderCommandEncoder?.pushDebugGroup("Depth Pass")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Depth])
        renderCommandEncoder?.setDepthClipMode(.clamp)
        renderCommandEncoder?.setDepthStencilState(Graphics.DepthStencilStates[.Less])
        renderCommandEncoder?.setFrontFacing(.counterClockwise)
        renderCommandEncoder?.setCullMode(.front)
        renderCommandEncoder?.setDepthBias(0.001, slopeScale: 2, clamp: 1)

        SceneManager.SetSceneConstants(renderCommandEncoder: renderCommandEncoder!)
        SceneManager.RenderDepth(renderCommandEncoder: renderCommandEncoder!)

        renderCommandEncoder?.popDebugGroup()
        renderCommandEncoder?.endEncoding()
    }

//    func shadowRenderPass(commandBuffer: MTLCommandBuffer) {
//        for light in SceneManager.getLightObjects() {
////            _shadowRenderPassDescriptor.depthAttachment.texture = light.shadowTexture
//            let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _shadowRenderPassDescriptor)
//            renderCommandEncoder?.label = "Shadow Render Command Encoder"
//            renderCommandEncoder?.pushDebugGroup("Rendering Shadow for \(light.getName())")
//            renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Shadow])
//            renderCommandEncoder?.setDepthStencilState(Graphics.DepthStencilStates[.Less])
//            renderCommandEncoder?.setFrontFacing(.counterClockwise)  // ???
//            renderCommandEncoder?.setCullMode(.back)
//
//            SceneManager.SetSceneConstants(renderCommandEncoder: renderCommandEncoder!)
//
//            let shadowViewMatrix = light.modelMatrix.inverse
//            let shadowProjectionMatrix = light.projectionMatrix
//            let shadowViewProjectionMatrix = shadowProjectionMatrix * shadowViewMatrix
//
//            SceneManager.RenderShadows(renderCommandEncoder: renderCommandEncoder!,
//                                       shadowViewProjectionMatrix: shadowViewProjectionMatrix)
//
//            renderCommandEncoder?.popDebugGroup()
//            renderCommandEncoder?.endEncoding()
//        }
//    }
    
    func drawOpaqueObjects(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Opaque Object Rendering")
        renderCommandEncoder.setCullMode(.none)
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualWrite])
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Base)
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Material)
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Instanced)
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Opaque)
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .OpaqueMaterial)
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .SkySphere)
        renderCommandEncoder.popDebugGroup()
    }
    
    func drawTransparentObjects(renderCommandEncoder: MTLRenderCommandEncoder) {
        renderCommandEncoder.pushDebugGroup("Transparent Object Rendering")
        renderCommandEncoder.setCullMode(.none)
        renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
        SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .OrderIndependentTransparent)
        renderCommandEncoder.popDebugGroup()
    }
    
    func orderIndependentTransparencyRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        // TODO: Decide if should have Final Render Pass, or if should render directly to view's
        //       current drawable texture:
//        guard let drawableTexture = view.currentDrawable?.texture else { return }

//        _baseRenderPassDescriptor.colorAttachments[0].texture = drawableTexture
//        _baseRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
        
//        _forwardRenderPassDescriptor.colorAttachments[0].texture = drawableTexture
//        _forwardRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _forwardRenderPassDescriptor)
        renderCommandEncoder?.label = "Order Independent Transparency Render Command Encoder"
        
        renderCommandEncoder?.pushDebugGroup("[Tile Render] Init Image Block")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.TileRender])
        renderCommandEncoder?.dispatchThreadsPerTile(_optimalTileSize)
        renderCommandEncoder?.popDebugGroup()
        
        SceneManager.SetSceneConstants(renderCommandEncoder: renderCommandEncoder!)
//        renderCommandEncoder?.setFragmentTexture(SceneManager.getLightObjects()[0].shadowTexture, index: 2)
        renderCommandEncoder?.setFragmentTexture(_depthPassTexture, index: 2)
        drawOpaqueObjects(renderCommandEncoder: renderCommandEncoder!)
        drawTransparentObjects(renderCommandEncoder: renderCommandEncoder!)
        
        renderCommandEncoder?.pushDebugGroup("Blend Fragments")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
        renderCommandEncoder?.setCullMode(.none)
        renderCommandEncoder?.setDepthStencilState(Graphics.DepthStencilStates[.AlwaysNoWrite])
        renderCommandEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        renderCommandEncoder?.popDebugGroup()
        
        renderCommandEncoder?.endEncoding()
    }
    
    func finalRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!)
        renderCommandEncoder?.label = "Final Render Command Encoder"
        renderCommandEncoder?.pushDebugGroup("Starting Final Render")
        
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Final])
        renderCommandEncoder?.setFragmentTexture(Assets.Textures[.BaseColorRender_0], index: 0)
        Assets.Meshes[.Quad].drawPrimitives(renderCommandEncoder!)
        
        renderCommandEncoder?.popDebugGroup()
        renderCommandEncoder?.endEncoding()
    }
    
    func draw(in view: MTKView) {
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        let commandBuffer = Engine.CommandQueue.makeCommandBuffer()
        commandBuffer?.label = "Draw Command Buffer"
        
        depthRenderPass(commandBuffer: commandBuffer!)
        orderIndependentTransparencyRenderPass(view: view, commandBuffer: commandBuffer!)
        // Intermediate renders go here
        finalRenderPass(view: view, commandBuffer: commandBuffer!)
        
        commandBuffer?.present(view.currentDrawable!)
        commandBuffer?.commit()
    }
}
