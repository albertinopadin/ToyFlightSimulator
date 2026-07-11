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
        // SetupAnimation relies on this for consecutive skinned meshes:
        // an already-animated Current short-circuits the swap.
        #expect(RenderPipelineStateType.TiledMSAAGBufferAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.TiledDeferredGBufferAnimated.animatedVariant == nil)
        #expect(RenderPipelineStateType.TiledMSAAShadowAnimated.animatedVariant == nil)
    }

    @Test("Families without animated pipelines map to nil, not a cross-family PSO")
    func familiesWithoutAnimatedPipelinesMapToNil() {
        #expect(RenderPipelineStateType.OpaqueMaterial.animatedVariant == nil)
        #expect(RenderPipelineStateType.OrderIndependentTransparent.animatedVariant == nil)
        #expect(RenderPipelineStateType.SinglePassDeferredGBufferMaterial.animatedVariant == nil)
        #expect(RenderPipelineStateType.SinglePassDeferredTransparency.animatedVariant == nil)
        #expect(RenderPipelineStateType.Composite.animatedVariant == nil)
        #expect(RenderPipelineStateType.TiledMSAAAverageResolve.animatedVariant == nil)
    }

    @Test("isAnimatedVariant is true for exactly the three animated PSOs")
    func isAnimatedVariantMembership() {
        #expect(RenderPipelineStateType.TiledMSAAGBufferAnimated.isAnimatedVariant)
        #expect(RenderPipelineStateType.TiledDeferredGBufferAnimated.isAnimatedVariant)
        #expect(RenderPipelineStateType.TiledMSAAShadowAnimated.isAnimatedVariant)
        #expect(!RenderPipelineStateType.TiledMSAAGBuffer.isAnimatedVariant)
        #expect(!RenderPipelineStateType.TiledMSAAShadow.isAnimatedVariant)
        #expect(!RenderPipelineStateType.Final.isAnimatedVariant)
    }
}
