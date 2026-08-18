//
//  RenderPassEncoding.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/11/25.
//

import MetalKit

protocol RenderPassEncoding {}

extension RenderPassEncoding {
    /// Convenience for binding a library pipeline by type. Pure sugar — the
    /// skinned-mesh PSO swap gets its pass PSO explicitly via the DrawManager
    /// entry points' psoType parameter, so there is no global pipeline
    /// tracking and no "wrong" way to bind a pipeline.
    func setRenderPipelineState(_ renderEncoder: MTLRenderCommandEncoder, state: RenderPipelineStateType) {
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[state])
    }
    
    func encodeRenderPass(into commandBuffer: MTLCommandBuffer,
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
    
    func encodeRenderStage(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    /// The one full-screen draw (E6): a single bufferless triangle whose
    /// positions come from the bound vertex function (full_screen_vertex or a
    /// FullScreenTriangleVertex-based specialization — vertex_id only). The
    /// PSO must NOT set a vertexDescriptor: the debug layer validates draws
    /// against the descriptor's layouts and would demand a vertex buffer at
    /// index 0 even though nothing reads one.
    @inline(__always)
    func drawFullScreenTriangle(with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
