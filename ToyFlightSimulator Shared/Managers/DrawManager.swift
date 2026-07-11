//
//  DrawManager.swift
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 9/14/24.
//

import MetalKit

final class DrawManager {
    // ===================== Uniforms/ModelConstants Ring Buffer ===================== //
    nonisolated(unsafe) private static var uniformsRingBuffers: [MTLBuffer] = []
    nonisolated(unsafe) private static var currentFrameIndex: Int = 0
    public static var currentRenderFrameIndex: Int { currentFrameIndex }
    nonisolated(unsafe) private static var currentBufferOffset: Int = 0
    /// Absolute (non-wrapped) frame number, set in BeginFrame. Used by the
    /// animated-uniforms cache: ring SLOT indices recycle every 3 frames, so a
    /// slot index alone can't tell "this frame" from "3 frames ago".
    nonisolated(unsafe) private static var currentAbsoluteFrame: Int = -1
    private static let initialBufferSize = 32 * 1024 * 1024  // 32 MB initial capacity

    /// Per-frame cache of mesh-local-transform-multiplied ModelConstants.
    /// A mesh with a non-identity animation transform is drawn by up to 6
    /// passes per frame (4 shadow cascades + GBuffer + transparency); the
    /// transform multiply is identical in each, so compute once on the first
    /// pass and re-bind the same ring-buffer region in the rest.
    /// `srcOffset` guards against a Mesh instance ever being shared across
    /// models (different source regions → distinct cache entries lose).
    /// Render-thread only.
    private struct AnimatedUniformsEntry {
        let frame: Int
        let srcOffset: Int
        let dstOffset: Int
    }
    nonisolated(unsafe) private static var _animatedUniformsCache: [ObjectIdentifier: AnimatedUniformsEntry] = [:]

    /// Called from SceneManager.TeardownScene so cache entries keyed by Mesh
    /// identity don't linger across scene loads.
    public static func ClearFrameCaches() {
        _animatedUniformsCache.removeAll()
    }

    // Per-frame end offset after update thread writes, so render thread continues from there:
    nonisolated(unsafe) private static var updateEndOffsets: [Int] = [0, 0, 0]

    public static func InitializeRingBuffers() {
        for i in 0..<Renderer.maxFramesInFlight {
            guard let buf = Engine.Device.makeBuffer(length: initialBufferSize, options: .storageModeShared) else {
                fatalError("Failed to create uniforms ring buffer")
            }

            buf.label = "Uniforms Ring Buffer \(i)"
            uniformsRingBuffers.append(buf)
        }
    }

    // Called by the UPDATE thread before writing ModelConstants for a frame:
    static func BeginFrameForUpdate(frameIndex: Int) {
        // Reset write offset for this frame's buffer slot.
        // Safe: only the update thread calls this, and the inFlightSemaphore
        // ensures the GPU is done with this slot before we reuse it.
        currentBufferOffset = 0
    }

    // Called by the UPDATE thread after finishing all ModelConstants writes:
    static func finishUpdateWrites(frameIndex: Int) {
        updateEndOffsets[frameIndex] = currentBufferOffset
    }

    // Called by the RENDER thread at the start of each frame.
    // Continues from where the update thread stopped writing.
    static func BeginFrame(frameIndex: Int) {
        currentAbsoluteFrame = frameIndex
        currentFrameIndex = frameIndex % Renderer.maxFramesInFlight
        currentBufferOffset = updateEndOffsets[currentFrameIndex]
    }

    /// Write ModelConstants from a ContiguousArray of GameObjects into the ring buffer.
    /// Returns the byte offset where the data was written, or nil on failure.
    /// Called by the update thread during SceneManager.writeFrameSnapshot().
    static func writeModelConstants(gameObjects: ContiguousArray<GameObject>, frameIndex: Int) -> Int? {
        guard !gameObjects.isEmpty else { return nil }

        let count = gameObjects.count
        let size = ModelConstants.stride(count)
        let alignment = 256
        let alignedOffset = (currentBufferOffset + alignment - 1) & ~(alignment - 1)

        var ringBuffer = uniformsRingBuffers[frameIndex]

        // Grow buffer if needed:
        if alignedOffset + size > ringBuffer.length {
            let newSize = max(ringBuffer.length * 2, alignedOffset + size)
            guard let grown = Engine.Device.makeBuffer(length: newSize, options: .storageModeShared) else {
                return nil
            }
            grown.label = "Uniforms Ring Buffer \(frameIndex)"
            memcpy(grown.contents(), ringBuffer.contents(), alignedOffset)
            uniformsRingBuffers[frameIndex] = grown
            ringBuffer = grown
        }

        // Write each GameObject's modelConstants directly into the ring buffer:
        let dst = ringBuffer.contents().advanced(by: alignedOffset)
            .assumingMemoryBound(to: ModelConstants.self)
        for i in 0..<count {
            dst[i] = gameObjects[i].modelConstants
        }

        currentBufferOffset = alignedOffset + size
        return alignedOffset
    }

    // Write uniforms into the ring buffer (used for animation fallback and ad-hoc draws).
    // Returns (buffer, offset):
    private static func writeUniformsToRingBuffer(_ uniforms: inout [ModelConstants]) -> (buffer: MTLBuffer, offset: Int)? {
        guard !uniforms.isEmpty else { return nil }

        let size = ModelConstants.stride(uniforms.count)
        let alignment = 256
        let alignedOffset = (currentBufferOffset + alignment - 1) & ~(alignment - 1)

        var ringBuffer = uniformsRingBuffers[currentFrameIndex]

        // Grow buffer if needed:
        if alignedOffset + size > ringBuffer.length {
            let newSize = max(ringBuffer.length * 2, alignedOffset + size)
            guard let grown = Engine.Device.makeBuffer(length: newSize, options: .storageModeShared) else {
                return nil
            }
            grown.label = "Uniforms Ring Buffer \(currentFrameIndex)"
            memcpy(grown.contents(), ringBuffer.contents(), alignedOffset)
            uniformsRingBuffers[currentFrameIndex] = grown
            ringBuffer = grown
        }

        memcpy(ringBuffer.contents().advanced(by: alignedOffset), &uniforms, size)
        currentBufferOffset = alignedOffset + size

        return (ringBuffer, alignedOffset)
    }
    
    // TODO: Consider removing this as it's the same code as in RenderPassEncoding protocol extension:
    static func EncodeRender(using renderEncoder: MTLRenderCommandEncoder, label: String, _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    // Draw opaque objects from pre-written ring buffer snapshots (no allocation, no lock):
    static func DrawOpaque(with renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
        renderEncoder.setFrontFacing(.clockwise)
        renderEncoder.setCullMode(.back)

        if applyMaterials {
            bindLinearSampler(renderEncoder)
        }

        let snapshot = SceneManager.getOpaqueSnapshot(frameIndex: currentFrameIndex)
        for (model, region) in snapshot {
            for meshData in region.meshDatas {
                if !meshData.opaqueSubmeshes.isEmpty {
                    SetupAnimation(renderEncoder, mesh: meshData.mesh)
                    DrawFromRingBuffer(renderEncoder,
                                       model: model,
                                       region: region,
                                       mesh: meshData.mesh,
                                       submeshes: meshData.opaqueSubmeshes,
                                       applyMaterials: applyMaterials)
                }
            }
        }

        DrawLines(with: renderEncoder)
    }

    static func DrawTransparent(with renderEncoder: MTLRenderCommandEncoder, applyMaterials: Bool = true) {
        renderEncoder.setFrontFacing(.clockwise)
        renderEncoder.setCullMode(.back)

        if applyMaterials {
            bindLinearSampler(renderEncoder)
        }

        // Opaque models with transparent submeshes:
        let opaqueSnapshot = SceneManager.getOpaqueSnapshot(frameIndex: currentFrameIndex)
        for (model, region) in opaqueSnapshot {
            for meshData in region.meshDatas {
                if !meshData.transparentSubmeshes.isEmpty {
                    SetupAnimation(renderEncoder, mesh: meshData.mesh)
                    DrawFromRingBuffer(renderEncoder,
                                       model: model,
                                       region: region,
                                       mesh: meshData.mesh,
                                       submeshes: meshData.transparentSubmeshes,
                                       applyMaterials: applyMaterials)
                }
            }
        }

        // Fully transparent objects:
        let transparentSnapshot = SceneManager.getTransparentSnapshot(frameIndex: currentFrameIndex)
        for (model, region) in transparentSnapshot {
            for meshData in region.meshDatas {
                DrawFromRingBuffer(renderEncoder,
                                   model: model,
                                   region: region,
                                   mesh: meshData.mesh,
                                   submeshes: meshData.transparentSubmeshes,
                                   applyMaterials: applyMaterials)
            }
        }
    }
    
    static func SetupAnimation(_ renderEncoder: MTLRenderCommandEncoder, mesh: Mesh) {
        if let paletteBuffer = mesh.skin?.jointMatrixPaletteBuffer {
            renderEncoder.setVertexBuffer(paletteBuffer,
                                          offset: 0,
                                          index: TFSBufferIndexJointBuffer.index)

            // Hack for now to set the proper PSO: derive the animated variant
            // from the pass PSO the renderer bound via the tracked
            // setRenderPipelineState(_:state:) helper. nil variant means the
            // pass PSO is already an animated one (keep it) or the renderer
            // family has no animated pipelines (OIT, SinglePassDeferred) —
            // then the mesh draws in bind pose with the pass PSO.
            guard let animated = RenderState.CurrentPipelineStateType.animatedVariant else { return }
            RenderState.PreviousPipelineStateType = RenderState.CurrentPipelineStateType
            RenderState.CurrentPipelineStateType = animated
            renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[animated])
        } else {
            if RenderState.CurrentPipelineStateType.isAnimatedVariant {
                renderEncoder.setVertexBuffer(nil,
                                              offset: 0,
                                              index: TFSBufferIndexJointBuffer.index)
                renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[RenderState.PreviousPipelineStateType])
                RenderState.CurrentPipelineStateType = RenderState.PreviousPipelineStateType
            }
        }
    }
    
    static func DrawShadows(with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFrontFacing(.clockwise)
        renderEncoder.setCullMode(.back)
        
        let snapshot = SceneManager.getOpaqueSnapshot(frameIndex: currentFrameIndex)
        for (model, region) in snapshot {
            for meshData in region.meshDatas {
                SetupAnimation(renderEncoder, mesh: meshData.mesh)
                DrawFromRingBuffer(renderEncoder,
                                   model: model,
                                   region: region,
                                   mesh: meshData.mesh,
                                   submeshes: meshData.opaqueSubmeshes,
                                   applyMaterials: false)
            }
        }
    }
    
    // TODO: Maybe it would be a good idea to refactor this class;
    //       Have the Renderer provide a dict of [RenderPipelineStateType : GameObject Type]
    //       Then parametrize Draw command on the pso to draw the appropriate objects
//    static func Draw(with renderEncoder: MTLRenderCommandEncoder,
//                     psoType: RenderPipelineStateType,
//                     withTransparency: Bool = false,
//                     applyMaterials: Bool = true) {
//        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[psoType])
//        
//
//    }
    
    // Resolved draw-time asset references. The model library subscript takes a
    // lock (and builds the model on first access), so resolve once and reuse
    // instead of subscripting every frame. Models stay cached in the library for
    // the process lifetime, so these references never go stale. Render-thread only.
    nonisolated(unsafe) private static var _fullScreenQuadMeshes: [Mesh]?
    nonisolated(unsafe) private static var _icosahedronDrawData: (model: Model, mesh: Mesh, submeshes: [Submesh])?

    /// Icosahedron model/mesh/submeshes shared by DrawPointLights and DrawIcosahedrons.
    private static func getIcosahedronDrawData() -> (model: Model, mesh: Mesh, submeshes: [Submesh])? {
        if let cached = _icosahedronDrawData { return cached }
        let model = Assets.Models[.Icosahedron]
        guard let mesh = model.meshes.first else { return nil }
        let data = (model: model, mesh: mesh, submeshes: model.meshes.flatMap { $0.submeshes })
        _icosahedronDrawData = data
        return data
    }

    static func DrawFullScreenQuad(with renderEncoder: MTLRenderCommandEncoder) {
        if _fullScreenQuadMeshes == nil {
            _fullScreenQuadMeshes = Assets.Models[.Quad].meshes
        }
        guard let meshes = _fullScreenQuadMeshes else { return }

        for mesh in meshes {
            if let vertexBuffer = mesh.vertexBuffer {
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                
                for submesh in mesh.submeshes {
                    renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                        indexCount: submesh.indexCount,
                                                        indexType: submesh.indexType,
                                                        indexBuffer: submesh.indexBuffer,
                                                        indexBufferOffset: submesh.indexBufferOffset,
                                                        instanceCount: mesh.instanceCount)
                }
            }
        }
    }
    
    // Scratch buffers for ad-hoc draws — uniforms are refilled in place each frame.
    nonisolated(unsafe) private static var _pointLightUniformsScratch: [ModelConstants] = []
    nonisolated(unsafe) private static var _icosahedronUniformsScratch: [ModelConstants] = []

    static func DrawPointLights(with renderEncoder: MTLRenderCommandEncoder) {
        let pointLights = LightManager.GetLightObjects(lightType: Point)
        guard !pointLights.isEmpty else { return }
        guard let (model, mesh, submeshes) = getIcosahedronDrawData() else { return }

        _pointLightUniformsScratch.removeAll(keepingCapacity: true)
        for light in pointLights {
            _pointLightUniformsScratch.append(light.modelConstants)
        }

        bindLinearSampler(renderEncoder)
        Draw(renderEncoder,
             model: model,
             uniforms: _pointLightUniformsScratch,
             mesh: mesh,
             submeshes: submeshes,
             applyMaterials: true)
    }

    static func DrawIcosahedrons(with renderEncoder: MTLRenderCommandEncoder) {
        guard !SceneManager.icosahedrons.isEmpty else { return }
        guard let (model, mesh, submeshes) = getIcosahedronDrawData() else { return }

        _icosahedronUniformsScratch.removeAll(keepingCapacity: true)
        for ico in SceneManager.icosahedrons {
            _icosahedronUniformsScratch.append(ico.modelConstants)
        }

        bindLinearSampler(renderEncoder)
        Draw(renderEncoder,
             model: model,
             uniforms: _icosahedronUniformsScratch,
             mesh: mesh,
             submeshes: submeshes,
             applyMaterials: true)
    }
    
    static func DrawSky(with renderEncoder: MTLRenderCommandEncoder) {
        guard let skyObj = SceneManager.skyData.gameObjects.first as? SkyEntity,
              let mesh = skyObj.model.meshes.first,
              let skyMeshData = SceneManager.skyData.meshDatas.first,
              let skyRegion = SceneManager.getSkySnapshot(frameIndex: currentFrameIndex)
        else { return }

        let pso: RenderPipelineStateType = ((skyObj as? SkyBox) != nil) ? .Skybox : .SkySphere
        renderEncoder.setRenderPipelineState(Graphics.RenderPipelineStates[pso])
        // skyObj.texture was resolved off the render thread at construction — no
        // per-frame trip through the texture library's locked subscript.
        renderEncoder.setFragmentTexture(skyObj.texture, index: TFSTextureIndexSkyBox.index)

        DrawFromRingBuffer(renderEncoder,
                           model: skyObj.model,
                           region: skyRegion,
                           mesh: mesh,
                           submeshes: skyMeshData.opaqueSubmeshes,
                           applyMaterials: false)
    }
    
    static func DrawParticles(with renderEncoder: MTLRenderCommandEncoder) {
        for particleObject in SceneManager.particleObjects {
            if particleObject.shouldEmit && particleObject.emitter.currentParticles > 0 {
                EncodeRender(using: renderEncoder, label: "Rendering \(particleObject.getName())") {
                    renderEncoder.setVertexBuffer(particleObject.emitter.particleBuffer, offset: 0, index: 0)
                    renderEncoder.setVertexBytes(&particleObject.emitter.position, length: float3.stride, index: 2)
                    
                    renderEncoder.setVertexBytes(&particleObject.modelConstants,
                                                 length: ModelConstants.stride,
                                                 index: TFSBufferModelConstants.index)
                    
                    if let emitterTexture = particleObject.emitter.particleTexture {
                        renderEncoder.setFragmentTexture(emitterTexture, index: TFSTextureIndexParticle.index)
                    }
                    
                    renderEncoder.drawPrimitives(type: .point,
                                                 vertexStart: 0,
                                                 vertexCount: 1,
                                                 instanceCount: particleObject.emitter.currentParticles)
                }
            }
        }
    }
    
    static func DrawTessellatables(with renderEncoder: MTLRenderCommandEncoder) {
        for tessellatable in SceneManager.tessellatables {
            EncodeRender(using: renderEncoder, label: "Rendering \(tessellatable.getName())") {
                renderEncoder.setVertexBytes(&tessellatable.modelConstants,
                                             length: ModelConstants.stride,
                                             index: TFSBufferModelConstants.index)
                
                tessellatable.setRenderState(renderEncoder)
                
                renderEncoder.drawPatches(numberOfPatchControlPoints: 4,
                                          patchStart: 0,
                                          patchCount: tessellatable.patchCount,
                                          patchIndexBuffer: nil,
                                          patchIndexBufferOffset: 0,
                                          instanceCount: 1,
                                          baseInstance: 0)
            }
        }
    }
    
    static func DrawLines(with renderEncoder: MTLRenderCommandEncoder) {
        if !SceneManager.lines.isEmpty {
            EncodeRender(using: renderEncoder, label: "Rendering Lines") {
                bindLinearSampler(renderEncoder)

                for line in SceneManager.lines {
                    renderEncoder.setVertexBytes(&line.modelConstants,  // !!!!!!!
                                                 length: ModelConstants.stride,
                                                 index: TFSBufferModelConstants.index)
                    renderEncoder.setVertexBuffer(line.vertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: line.vertices.count)
                }
            }
        }
    }
    
    /// Draw objects whose ModelConstants are already in the ring buffer (written by update thread).
    /// Applies mesh animation transform if needed, writing a modified copy to the ring buffer.
    static private func DrawFromRingBuffer(_ renderEncoder: MTLRenderCommandEncoder,
                                           model: Model,
                                           region: RingBufferRegion,
                                           mesh: Mesh,
                                           submeshes: [Submesh],
                                           applyMaterials: Bool) {
        EncodeRender(using: renderEncoder, label: "Rendering \(model.name)") {
            guard region.count > 0 else { return }

            let ringBuffer = uniformsRingBuffers[currentFrameIndex]
            let localTransform = mesh.transform?.currentTransform ?? .identity

            if localTransform != .identity {
                // Mesh has an animation transform. Compute the transformed
                // constants ONCE per frame (first pass that draws this mesh),
                // then re-bind the same region from subsequent passes.
                let key = ObjectIdentifier(mesh)
                if let hit = _animatedUniformsCache[key],
                   hit.frame == currentAbsoluteFrame,
                   hit.srcOffset == region.offset {
                    renderEncoder.setVertexBuffer(uniformsRingBuffers[currentFrameIndex],
                                                  offset: hit.dstOffset,
                                                  index: TFSBufferModelConstants.index)
                } else {
                    guard let dstOffset = writeTransformedUniforms(region: region,
                                                                   localTransform: localTransform) else { return }
                    _animatedUniformsCache[key] = AnimatedUniformsEntry(frame: currentAbsoluteFrame,
                                                                        srcOffset: region.offset,
                                                                        dstOffset: dstOffset)
                    // Re-fetch the buffer: writeTransformedUniforms may have grown it.
                    renderEncoder.setVertexBuffer(uniformsRingBuffers[currentFrameIndex],
                                                  offset: dstOffset,
                                                  index: TFSBufferModelConstants.index)
                }
            } else {
                // No animation — bind ring buffer region directly (ZERO COPY):
                renderEncoder.setVertexBuffer(ringBuffer, offset: region.offset, index: TFSBufferModelConstants.index)
            }

            drawSubmeshes(renderEncoder,
                          mesh: mesh,
                          submeshes: submeshes,
                          instanceCount: mesh.instanceCount * region.count,
                          applyMaterials: applyMaterials)
        }
    }

    /// Reserve a new ring-buffer region and fill it with the source region's
    /// ModelConstants, each modelMatrix post-multiplied by `localTransform` —
    /// a single ring-to-ring pass with no intermediate Swift array.
    /// Returns the destination byte offset, or nil if the buffer can't grow.
    /// Source and destination never overlap: dst starts at/after the current
    /// end-of-writes offset, which is past every update-thread region.
    private static func writeTransformedUniforms(region: RingBufferRegion,
                                                 localTransform: float4x4) -> Int? {
        let count = region.count
        guard count > 0 else { return nil }

        let size = ModelConstants.stride(count)
        let alignment = 256
        let alignedOffset = (currentBufferOffset + alignment - 1) & ~(alignment - 1)

        var ringBuffer = uniformsRingBuffers[currentFrameIndex]

        // Grow buffer if needed (grow-then-read: the memcpy preserves every
        // byte below alignedOffset, which includes the source region):
        if alignedOffset + size > ringBuffer.length {
            let newSize = max(ringBuffer.length * 2, alignedOffset + size)
            guard let grown = Engine.Device.makeBuffer(length: newSize, options: .storageModeShared) else {
                return nil
            }
            grown.label = "Uniforms Ring Buffer \(currentFrameIndex)"
            memcpy(grown.contents(), ringBuffer.contents(), alignedOffset)
            uniformsRingBuffers[currentFrameIndex] = grown
            ringBuffer = grown
        }

        let base = ringBuffer.contents()
        let src = base.advanced(by: region.offset).assumingMemoryBound(to: ModelConstants.self)
        let dst = base.advanced(by: alignedOffset).assumingMemoryBound(to: ModelConstants.self)
        for i in 0..<count {
            var constants = src[i]
            constants.modelMatrix *= localTransform
            dst[i] = constants
        }

        currentBufferOffset = alignedOffset + size
        return alignedOffset
    }

    /// Legacy Draw for ad-hoc objects not in the ring buffer (point lights, icosahedrons, etc.)
    static private func Draw(_ renderEncoder: MTLRenderCommandEncoder,
                             model: Model,
                             uniforms: [ModelConstants],
                             mesh: Mesh,
                             submeshes: [Submesh],
                             applyMaterials: Bool) {
        EncodeRender(using: renderEncoder, label: "Rendering \(model.name)") {
            guard !uniforms.isEmpty else { return }
            var uniforms = uniforms

            let localTransform = mesh.transform?.currentTransform ?? .identity
            if localTransform != .identity {
                for idx in 0..<uniforms.count {
                    uniforms[idx].modelMatrix *= localTransform
                }
            }

            guard let (ringBuffer, offset) = writeUniformsToRingBuffer(&uniforms) else { return }
            renderEncoder.setVertexBuffer(ringBuffer, offset: offset, index: TFSBufferModelConstants.index)

            drawSubmeshes(renderEncoder,
                          mesh: mesh,
                          submeshes: submeshes,
                          instanceCount: mesh.instanceCount * uniforms.count,
                          applyMaterials: applyMaterials)
        }
    }

    /// Inner loop shared by `Draw` and `DrawFromRingBuffer`. Assumes the ModelConstants
    /// buffer at `TFSBufferModelConstants.index` has already been bound by the caller.
    private static func drawSubmeshes(_ renderEncoder: MTLRenderCommandEncoder,
                                      mesh: Mesh,
                                      submeshes: [Submesh],
                                      instanceCount: Int,
                                      applyMaterials: Bool) {
        for submesh in submeshes {
            guard let parentMesh = submesh.parentMesh,
                  let vertexBuffer = parentMesh.vertexBuffer else { continue }
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            if applyMaterials, let material = submesh.material {
                applyMaterialTextures(material, with: renderEncoder)
                var materialProps = material.properties
                renderEncoder.setFragmentBytes(&materialProps,
                                               length: MaterialProperties.stride,
                                               index: TFSBufferIndexMaterial.index)
            }

            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer,
                                                indexBufferOffset: submesh.indexBufferOffset,
                                                instanceCount: instanceCount)
        }
    }

    /// Bind the active linear sampler at fragment index 0. The sampler is identical for
    /// every submesh in a pass and reading `currentLinearSamplerState` takes a lock, so
    /// the Draw* entry points bind it once per pass instead of per submesh.
    private static func bindLinearSampler(_ renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentSamplerState(Graphics.SamplerStates.currentLinearSamplerState, index: 0)
    }

    /// Per-submesh material state. The linear sampler is NOT bound here — it's pass-wide
    /// state, bound once per pass via `bindLinearSampler` in the Draw* entry points.
    private static func applyMaterialTextures(_ material: Material, with renderEncoder: MTLRenderCommandEncoder) {
        // setFragmentTexture accepts nil — no need for separate else branches.
        renderEncoder.setFragmentTexture(material.baseColorTexture, index: TFSTextureIndexBaseColor.index)
        renderEncoder.setFragmentTexture(material.normalMapTexture, index: TFSTextureIndexNormal.index)
        renderEncoder.setFragmentTexture(material.specularTexture,  index: TFSTextureIndexSpecular.index)

        var textureTransforms = material.textureTransforms
        renderEncoder.setFragmentBytes(&textureTransforms,
                                       length: MaterialTextureTransforms.stride,
                                       index: TFSBufferIndexMaterialTextureTransforms.index)
    }
}
