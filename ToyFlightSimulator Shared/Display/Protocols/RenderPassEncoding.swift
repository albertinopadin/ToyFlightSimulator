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
}
