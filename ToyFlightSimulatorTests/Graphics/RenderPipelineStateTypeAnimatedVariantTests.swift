//
//  RenderPipelineStateTypeAnimatedVariantTests.swift
//  ToyFlightSimulatorTests
//
//  Created by Albertino Padin on 7/11/26.
//

import Testing
@testable import ToyFlightSimulator

/// Pins the pass-PSO → animated-PSO mapping that DrawManager.SetupAnimation
/// derives skinned-mesh pipeline switching from. Pure enum logic — no Metal.
/// A renderer family without an animated variant must map to nil (skinned
/// meshes draw in bind pose with the pass PSO) rather than inheriting an
/// MSAA-family default, which is what bound 4x/shadow PSOs into mismatched
/// passes (the renderer-switch validation assert).
@Suite("RenderPipelineStateType animated variants", .tags(.graphics))
struct RenderPipelineStateTypeAnimatedVariantTests {

    @Test("GBuffer and transparency passes map to their family's animated GBuffer PSO")
    func gBufferAndTransparencyMapping() {
        #expect(RenderPipelineStateType.TiledMSAAGBuffer.animatedVariant == .TiledMSAAGBufferAnimated)
        #expect(RenderPipelineStateType.TiledMSAATransparency.animatedVariant == .TiledMSAAGBufferAnimated)
        #expect(RenderPipelineStateType.TiledDeferredGBuffer.animatedVariant == .TiledDeferredGBufferAnimated)
        #expect(RenderPipelineStateType.TiledDeferredTransparency.animatedVariant == .TiledDeferredGBufferAnimated)
    }

    @Test("OIT and SinglePassDeferred mesh passes map to their own animated PSOs")
    func oitAndSinglePassMapping() {
        // Both OIT mesh passes swap base_vertex for base_animated_vertex but
        // keep distinct fragment/blend state, so each has its own variant.
        #expect(RenderPipelineStateType.OpaqueMaterial.animatedVariant == .OpaqueMaterialAnimated)
        #expect(RenderPipelineStateType.OrderIndependentTransparent.animatedVariant
                == .OrderIndependentTransparentAnimated)
        #expect(RenderPipelineStateType.SinglePassDeferredGBufferMaterial.animatedVariant
                == .SinglePassDeferredGBufferMaterialAnimated)
        #expect(RenderPipelineStateType.SinglePassDeferredTransparency.animatedVariant
                == .SinglePassDeferredTransparencyAnimated)
    }

    @Test("All shadow passes share the single animated shadow PSO")
    func shadowMapping() {
        // Every cascade pass has the same attachment layout (no color,
        // depth32Float, sample count 1), so one animated PSO serves all three.
        #expect(RenderPipelineStateType.TiledMSAAShadow.animatedVariant == .TiledMSAAShadowAnimated)
        #expect(RenderPipelineStateType.TiledDeferredShadow.animatedVariant == .TiledMSAAShadowAnimated)
        #expect(RenderPipelineStateType.ShadowGeneration.animatedVariant == .TiledMSAAShadowAnimated)
    }

    @Test("Animated variants themselves have no further variant")
    func animatedVariantsAreTerminal() {
        // No draw loop ever passes an animated PSO as its pass psoType;
        // pinning nil keeps the mapping one-way (a swap can't chain into
        // a second swap).
        #expect(RenderPipelineStateType.TiledMSAAGBufferAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.TiledDeferredGBufferAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.TiledMSAAShadowAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.OpaqueMaterialAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.OrderIndependentTransparentAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.SinglePassDeferredGBufferMaterialAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.SinglePassDeferredTransparencyAnimated.animatedVariant == nil)
    }

    @Test("Non-mesh passes map to nil, not a cross-family PSO")
    func passesWithoutAnimatedPipelinesMapToNil() {
        #expect(RenderPipelineStateType.Composite.animatedVariant == nil)
        #expect(RenderPipelineStateType.TiledMSAAAverageResolve.animatedVariant == nil)
        #expect(RenderPipelineStateType.Final.animatedVariant == nil)
        #expect(RenderPipelineStateType.Blend.animatedVariant == nil)
        #expect(RenderPipelineStateType.TileRender.animatedVariant == nil)
    }
}
