//
//  TiledGBufferRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 2026-05-07.
//

import MetalKit

/// Wires a renderer's tiled GBuffer textures into a render pass descriptor.
/// Conforming renderers expose the GBuffer texture set; the protocol provides
/// default attachment-binding logic shared across all tiled deferred variants.
protocol TiledGBufferRendering {
    var gBufferTextures: TiledDeferredGBufferTextures { get }
}

extension TiledGBufferRendering {
    /// Bind albedo / normal / position color attachments + depth & stencil.
    func setGBufferTextures(_ rpd: MTLRenderPassDescriptor) {
        rpd.colorAttachments[TFSRenderTargetAlbedo.index].texture   = gBufferTextures.albedoTexture
        rpd.colorAttachments[TFSRenderTargetNormal.index].texture   = gBufferTextures.normalTexture
        rpd.colorAttachments[TFSRenderTargetPosition.index].texture = gBufferTextures.positionTexture
        setDepthAndStencilTextures(rpd)
    }

    func setDepthAndStencilTextures(_ rpd: MTLRenderPassDescriptor) {
        rpd.depthAttachment.texture       = gBufferTextures.depthTexture
        rpd.depthAttachment.storeAction   = .dontCare
        rpd.stencilAttachment.texture     = gBufferTextures.depthTexture
        rpd.stencilAttachment.storeAction = .dontCare
    }
}
