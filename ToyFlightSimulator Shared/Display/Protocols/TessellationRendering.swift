//
//  TessellationRendering.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 5/13/25.
//

import MetalKit

protocol TessellationRendering: ComputePassEncoding, RenderPassEncoding {}

extension TessellationRendering {
    var edgeFactors: [Float] { [4] }
    var insideFactors: [Float] { [4] }
    
    func encodeTessellationComputePass(into commandBuffer: MTLCommandBuffer) {
        encodeComputePass(into: commandBuffer, label: "Tessellation Compute Pass") { computeEncoder in
            let tessellationComputePipelineState = Graphics.ComputePipelineStates[.Tessellation]
            computeEncoder.setComputePipelineState(tessellationComputePipelineState)
            
            computeEncoder.setBytes(self.edgeFactors, length: Float.size * self.edgeFactors.count, index: 0)
            computeEncoder.setBytes(self.insideFactors, length: Float.size * self.insideFactors.count, index: 1)
            
            // The camera position the draw uses, paired with the terrain matrix that
            // TerrainObject.computeUpdate binds (also cached by update()). On a floating-origin
            // shift tick the live pair would move the already-shifted terrain at least 1 km
            // away from the not-yet-shifted camera, so the patch under the camera would get the
            // minimum factor (4) for that frame instead of its real one (6.4 with the camera
            // 10 m above it).
            var cameraPosition = float4(SceneManager.CurrentScene?.cameraPositionOfLastUpdate ?? .zero, 0)
            computeEncoder.setBytes(&cameraPosition, length: float4.stride, index: 3)
            
            ComputeManager.ComputeTerrainTessellation(with: computeEncoder)
        }
    }
    
    func encodeTessellationRenderPass(with renderEncoder: MTLRenderCommandEncoder) {
        encodeRenderStage(using: renderEncoder, label: "Tessellation") {
//            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[.TessellationGBuffer])
            setRenderPipelineState(renderEncoder, state: .TessellationGBuffer)
            renderEncoder.setDepthStencilState(Graphics.DepthStencilStates[.TiledDeferredGBuffer])
            DrawManager.DrawTessellatables(with: renderEncoder)
        }
    }
}

final class TessellatedRendering: TessellationRendering {
    public static let maxTessellation: Int = Engine.Device.supportsFamily(.apple5) ? 64 : 16
}
