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
        print("[OIT Renderer init]")
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
        encodeStage(using: renderCommandEncoder, label: "Opaque Object Rendering") {
            renderCommandEncoder.setCullMode(.none)
            renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualWrite])
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Base)
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Material)
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Instanced)
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .Opaque)
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .OpaqueMaterial)
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder, renderPipelineStateType: .SkySphere)
        }
    }
    
    func drawTransparentObjects(renderCommandEncoder: MTLRenderCommandEncoder) {
        encodeStage(using: renderCommandEncoder, label: "Transparent Object Rendering") {
            renderCommandEncoder.setCullMode(.none)
            renderCommandEncoder.setDepthStencilState(Graphics.DepthStencilStates[.LessEqualNoWrite])
            SceneManager.Render(renderCommandEncoder: renderCommandEncoder,
                                renderPipelineStateType: .OrderIndependentTransparent)
        }
    }
    
    func orderIndependentTransparencyRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        encodePass(into: commandBuffer,
                   using: _forwardRenderPassDescriptor,
                   label: "Order Independent Transparency Render Pass") { renderEncoder in
            encodeStage(using: renderEncoder, label: "[Tile Render] Init Image Block") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TileRender])
                renderEncoder.dispatchThreadsPerTile(_optimalTileSize)
            }
            
            SceneManager.SetSceneConstants(renderCommandEncoder: renderEncoder)
            SceneManager.SetLightData(renderCommandEncoder: renderEncoder)
            drawOpaqueObjects(renderCommandEncoder: renderEncoder)
            drawTransparentObjects(renderCommandEncoder: renderEncoder)
            
            encodeStage(using: renderEncoder, label: "Blend Fragments") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Blend])
                renderEncoder.setCullMode(.none)
                renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.AlwaysNoWrite])
                // Draw full screen quad:
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
    }
    
    func finalRenderPass(view: MTKView, commandBuffer: MTLCommandBuffer) {
        encodePass(into: commandBuffer, using: view.currentRenderPassDescriptor!, label: "Final Render Pass") { renderEncoder in
            encodeStage(using: renderEncoder, label: "Final Render") {
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.Final])
                renderEncoder.setFragmentTexture(Assets.Textures[.BaseColorRender_0], index: 0)
                Assets.Meshes[.Quad].drawPrimitives(renderEncoder)
            }
        }
    }
    
    override func draw(in view: MTKView) {
        SceneManager.Update(deltaTime: 1.0 / Float(view.preferredFramesPerSecond))
        
        let commandBuffer = Engine.CommandQueue.makeCommandBuffer()
        commandBuffer?.label = "Order Independent Transparency Render Command Buffer"
        
        orderIndependentTransparencyRenderPass(view: view, commandBuffer: commandBuffer!)
        // Intermediate renders go here
        finalRenderPass(view: view, commandBuffer: commandBuffer!)
        
        commandBuffer?.present(view.currentDrawable!)
        commandBuffer?.commit()
    }
}
