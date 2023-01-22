//
//  OITRenderer.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 1/21/23.
//

import MetalKit

class OITRenderer: Renderer {
    private var _forwardRenderPassDescriptor: MTLRenderPassDescriptor!
    private let _optimalTileSize: MTLSize = MTLSize(width: 32, height: 16, depth: 1)
    
    override init(_ mtkView: MTKView) {
        super.init(mtkView)
        createForwardRenderPassDescriptor()
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
//        guard let drawableTexture = view.currentDrawable?.texture else { return }
        
//        _forwardRenderPassDescriptor.colorAttachments[0].texture = drawableTexture
//        _forwardRenderPassDescriptor.depthAttachment.texture = view.depthStencilTexture
        
        let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: _forwardRenderPassDescriptor)
        renderCommandEncoder?.label = "Order Independent Transparency Render Command Encoder"
        
        renderCommandEncoder?.pushDebugGroup("[Tile Render] Init Image Block")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.TileRender])
        renderCommandEncoder?.dispatchThreadsPerTile(_optimalTileSize)
        renderCommandEncoder?.popDebugGroup()
        
        SceneManager.SetSceneConstants(renderCommandEncoder: renderCommandEncoder!)
        drawOpaqueObjects(renderCommandEncoder: renderCommandEncoder!)
        drawTransparentObjects(renderCommandEncoder: renderCommandEncoder!)
        
        renderCommandEncoder?.pushDebugGroup("Blend Fragments")
        renderCommandEncoder?.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
        renderCommandEncoder?.setCullMode(.none)
        renderCommandEncoder?.setDepthStencilState(Graphics.DepthStencilStates[.AlwaysNoWrite])
        // Draw full screen quad:
        renderCommandEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
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
    
    override func draw(in view: MTKView) {
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        let commandBuffer = Engine.CommandQueue.makeCommandBuffer()
        commandBuffer?.label = "Base Command Buffer"
        
        orderIndependentTransparencyRenderPass(view: view, commandBuffer: commandBuffer!)
        // Intermediate renders go here
        finalRenderPass(view: view, commandBuffer: commandBuffer!)
        
        commandBuffer?.present(view.currentDrawable!)
        commandBuffer?.commit()
    }
}
