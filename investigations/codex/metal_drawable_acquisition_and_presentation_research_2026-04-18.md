# Metal Drawable Acquisition and Presentation Research

**Date:** 2026-04-18  
**Scope:** Best practices for obtaining and presenting drawables in Metal apps, with a specific review of `ToyFlightSimulator Shared/Display/TiledMultisampleRenderer.swift:172`.

## Executive Answer

Apple's guidance is consistent on the main point:

- Acquire a drawable as late as possible.
- Release it as soon as possible.
- Prefer `MTLCommandBuffer.present(_:)` over calling `drawable.present()` directly in the normal `MTKView` / `CAMetalLayer` path.

For this renderer, the important nuance is:

- Your proposed "encode everything first, fetch the drawable at the end, then present" structure is the **right direction only if the earlier passes are truly offscreen**.
- In the current code, they are **not fully offscreen**, because `view.currentRenderPassDescriptor` is read at `TiledMultisampleRenderer.swift:175`, and Apple documents that reading `currentRenderPassDescriptor` implicitly acquires the current drawable.
- That means simply moving `guard let drawable = view.currentDrawable` later is **not enough** if you still use `view.currentRenderPassDescriptor` during the deferred lighting pass.

So the practical answer is:

1. It is fine to skip the onscreen pass when the drawable is unavailable.
2. It is better practice to do CPU work and GPU passes that do not require the drawable first.
3. In this renderer, if you want to follow Apple's preferred pattern more strictly, you need to stop using the `MTKView`'s drawable-backed attachment during the GBuffer/lighting pass and instead resolve into an app-owned intermediate texture, then composite that texture into the drawable at the very end.

## What Apple Recommends

I prioritized Apple documentation and samples. Some modern Apple doc pages are JavaScript-rendered in the browser tool, so where the full page was not directly readable, I relied on the indexed snippets plus Apple's archive documentation, which is readable in full.

### 1) Hold drawables briefly

Apple's archived Metal Best Practices Guide says:

- Drawables are "expensive system resources."
- They come from a limited pool.
- If no drawable is available when requested, the calling thread can block until one becomes available.
- You should "always acquire a drawable as late as possible; preferably, immediately before encoding an on-screen render pass."
- You should "always release a drawable as soon as possible."

Apple's `CAMetalLayer` docs say the same thing in a more concrete way:

- If a drawable is unavailable when `nextDrawable()` is called, the system waits for one.
- Before retrieving a new drawable, you should perform CPU work or submit GPU work that does not require it.
- After committing the command buffer that uses the drawable, release strong references to it promptly.
- If you do not release drawables correctly, the layer can run out of drawables, and future `nextDrawable()` calls can return `nil`.

### 2) `MTKView.currentRenderPassDescriptor` also counts as acquiring the drawable

Apple's `MTKView` docs explicitly say:

- `currentRenderPassDescriptor` is generated from the drawable's texture.
- Reading `currentRenderPassDescriptor` implicitly obtains the current drawable and stores it in `currentDrawable`.
- You should obtain drawables "as late as possible; preferably, immediately before encoding your onscreen render pass."

This matters a lot for your renderer, because the current code acquires:

- `view.currentDrawable` at line 172, and
- `view.currentRenderPassDescriptor` at line 175.

Either one is enough to tie the frame to a view-owned drawable early.

### 3) Present through the command buffer in the normal path

Apple recommends registering presentation on the command buffer:

- `commandBuffer.present(drawable)` schedules presentation after the command buffer is scheduled.
- The drawable does not actually present until the GPU work that renders or writes to it has completed.
- Apple explicitly warns not to wait for the GPU to complete before registering presentation, because that causes CPU stalls.

This matches your current use of `commandBuffer.present(drawable)` at line 204 and is the correct default approach for an `MTKView` renderer.

### 4) There is a limited drawable pool

Apple documents:

- `CAMetalLayer.maximumDrawableCount` can only be `2` or `3`.
- The default is `3`.
- `nextDrawable()` waits until a drawable is available, then returns it.
- If all drawables are in use, it can wait up to one second and then return `nil`, depending on `allowsNextDrawableTimeout`.

That is the underlying reason Apple cares about early acquisition: holding one drawable unnecessarily reduces the size of the available pool for the rest of the pipeline.

### 5) Apple's sample structure favors offscreen work first, onscreen work last

The archived Best Practices Guide shows the preferred sequence:

1. Update dynamic data.
2. Create a command buffer.
3. Encode offscreen passes.
4. Acquire `currentRenderPassDescriptor`.
5. Encode the onscreen pass.
6. Present the drawable.
7. Commit.

Apple's "Customizing render pass setup" sample also reinforces the same architectural split:

- perform the offscreen pass first,
- then perform the pass that draws to the `MTKView`.

## What the Current Renderer Does

Relevant code paths:

- `TiledMultisampleRenderer.draw(in:)` acquires `view.currentDrawable` at line 172.
- It then enters `runDrawableCommands` and encodes particle compute, GBuffer, lighting, transparency, particle rendering, MSAA resolve, composite, and `present`.
- At line 175 it also reads `view.currentRenderPassDescriptor`, which implicitly acquires the drawable if it has not already been acquired.
- `Renderer.runDrawableCommands(_:)` commits the command buffer immediately after the closure returns at `Renderer.swift:94`.

So the current lifetime of the drawable in the second command buffer is approximately:

1. `view.currentDrawable` at line 172.
2. `view.currentRenderPassDescriptor` at line 175.
3. CPU-side encoding of compute + render passes.
4. `commandBuffer.present(drawable)` at line 204.
5. `commandBuffer.commit()` in `Renderer.runDrawableCommands(_:)`.

The good news is:

- the shadow pass is already separate and committed before the drawable is acquired.

The less good news is:

- the drawable is still held across the entire CPU encoding window for the second command buffer.

If that encoding window is currently around 1-8 ms, that is not automatically a bug, but it is exactly the window Apple is telling you to minimize.

## Is It OK to Only Render If the Drawable Is Non-`nil`?

Yes, with an important distinction.

### Safe answer

It is normal and correct to guard the onscreen pass with something like:

```swift
guard let descriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable else {
    return
}
```

Apple's own examples effectively do this.

### But not all work needs to be gated by drawable availability

It is **not** ideal to use drawable availability as the gate for work that does not depend on the drawable.

If a frame includes:

- simulation updates,
- culling,
- shadow map rendering,
- offscreen GBuffer work,
- compute passes,
- post-processing into app-owned textures,

then those steps can be done before asking for the drawable, assuming their outputs are still useful for the frame.

So the better principle is:

- **gate only the onscreen phase on drawable availability**, not the entire frame, unless the entire frame is disposable when presentation is impossible.

## Is It Better to Fetch the Drawable Only After Earlier Rendering Commands?

### General answer

Yes, if the earlier commands do not need the drawable.

Your proposed shape, interpreted as pseudocode:

```swift
runDrawableCommands {
  encodeRenderPass {
    ...
  }
}
guard let drawable = view.currentDrawable else {
  return
}
commandBuffer.present(drawable)
```

is directionally correct only if:

- none of the earlier passes target the drawable,
- none of the earlier passes use `view.currentRenderPassDescriptor`,
- none of the earlier passes need a view-managed resolve texture or view-managed multisample attachment.

### Renderer-specific answer

For `TiledMultisampleRenderer`, the answer is: **not as written**.

Why:

- At line 175, `view.currentRenderPassDescriptor!.colorAttachments[...]` is copied into `tiledDeferredRenderPassDescriptor`.
- Apple documents that `currentRenderPassDescriptor` implicitly acquires the drawable.
- In practice, for an `MTKView` with multisampling, the view manages the color attachment arrangement needed for drawing to the screen, which can include a multisample color texture and the final drawable resolve target.

That means the current deferred lighting pass is already coupled to view-owned onscreen resources.

So if you want the "late drawable fetch" structure, you need a slightly different renderer design:

1. Use app-owned intermediate textures for the GBuffer and lighting/resolve output.
2. Perform particle compute, GBuffer, lighting, transparency, and MSAA resolve into those intermediate textures without touching `MTKView.currentDrawable` or `MTKView.currentRenderPassDescriptor`.
3. Only after all of that, acquire `view.currentRenderPassDescriptor` or `view.currentDrawable`.
4. Encode the final full-screen composite/blit into the drawable.
5. Call `commandBuffer.present(drawable)`.

That is the cleanest way to align your renderer with Apple's preferred drawable lifetime.

## Recommendation for This Codebase

### Short version

- Current code is probably acceptable while frame times are healthy and you are not seeing stalls.
- Apple's best practice still favors moving drawable acquisition later.
- In this specific renderer, moving it later requires an intermediate lighting/resolve texture, not just a small control-flow edit.

### Concrete recommendation

### Best-practice version

Refactor toward this frame structure:

1. Shadow pass in command buffer A.
2. Particle compute + deferred GBuffer/lighting/transparency/MSAA resolve into app-owned textures in command buffer B.
3. Acquire `view.currentRenderPassDescriptor` or `view.currentDrawable` immediately before the final composite pass.
4. Composite into the drawable.
5. `commandBuffer.present(drawable)`.

### Pragmatic version

If you do not want the extra intermediate texture yet:

- keeping the current structure is not obviously wrong,
- especially if you see no stalls,
- but it is less robust as CPU encoding time, GPU time, display refresh rate, or drawable pressure increase.

In other words: the current implementation is tolerable, but the alternative architecture is more scalable.

## What Problems You Might See If This Becomes an Issue

If drawable acquisition is happening too early, or if drawables are retained too long, likely symptoms are:

- `currentDrawable` / `nextDrawable()` blocking the CPU more often.
- More frame pacing jitter.
- Stutter under transient spikes even when average frame time looks acceptable.
- Increased "present delay" or "on-glass lateness."
- More skipped frames when the system cannot get a drawable in time.
- Extra latency between CPU frame generation and the frame actually appearing onscreen.
- Problems showing up sooner on 120 Hz displays than 60 Hz displays.
- Problems showing up sooner if `maximumDrawableCount` is `2` instead of `3`.
- Rare nil drawables when the layer is misconfigured or timed out.
- In the worst drawable-lifetime mistakes, deadlock-like behavior around drawable reuse.

Why 1-8 ms can matter:

- At 60 Hz, a frame budget is about 16.67 ms.
- At 120 Hz, a frame budget is about 8.33 ms.

So an unnecessary 8 ms drawable hold is:

- roughly half a 60 Hz frame budget,
- almost a whole 120 Hz frame budget.

That does not mean it always causes a problem. It means it consumes a large fraction of the scheduling slack that the drawable pool is supposed to give you.

## How I Would Measure It

Apple exposes several useful diagnostics.

### Metal Performance HUD

Watch:

- `Present Delay`
- `Frame Interval`
- `GPU Time`
- `Command Buffer and Encoder Count`

If the drawable is being acquired too early, `Present Delay` and frame pacing metrics are the most relevant first indicators.

### Drawable presentation timestamps

Use `MTLDrawable.addPresentedHandler(_:)` and `drawable.presentedTime` to measure actual on-glass intervals and latency trends.

### App Store / analytics report

Apple's `CAMetalLayer Performance` report includes fields such as:

- `Skipped Frame Count`
- `On Glass Present Lateness Count`
- `Presented GPU Done-To-Completed Total`

Those are exactly the kinds of metrics that would expose a drawable-lifetime problem at scale.

## Edge Cases and Exceptions

There is one notable exception to the normal `commandBuffer.present(drawable)` rule:

- If `CAMetalLayer.presentsWithTransaction` is `true`, Apple says not to use `MTLCommandBuffer.present(_:)`.
- In that case you need a Core Animation transaction-aware presentation flow.

That does **not** appear to be your situation here, but it is the documented exception.

Another related setting is `displaySyncEnabled`:

- `true` is the default and synchronizes presentation to the display refresh.
- `false` can reduce latency but may introduce tearing.

That setting changes presentation behavior, but it does not change the core best practice to acquire drawables late.

## Bottom-Line Conclusion

For `TiledMultisampleRenderer.swift:172`, the best answer is:

- It is not ideal to acquire `view.currentDrawable` before several milliseconds of compute and render encoding.
- Apple would prefer you to do as much offscreen work as possible first, then acquire the drawable immediately before the final onscreen pass.
- However, in your current renderer, the GBuffer/lighting pass is already coupled to the view's drawable-backed render-pass descriptor, so a proper fix requires an intermediate app-owned lighting/resolve texture.
- If the drawable is unavailable, it is fine to skip the onscreen pass for that frame.
- If the only purpose of the offscreen work is to feed the skipped present, skipping the whole present path is reasonable.

So the most accurate recommendation is:

- **Do not merely move the `guard let drawable = view.currentDrawable` lower.**
- **Decouple the deferred pipeline from `MTKView` resources first, then fetch the drawable late.**

## URLs Visited

- https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html
- https://developer.apple.com/documentation/metalkit/mtkview
- https://developer.apple.com/documentation/metal/using-metal-to-draw-a-view%27s-contents
- https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable%28%29
- https://developer.apple.com/documentation/quartzcore/cametallayer?language=objc
- https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount
- https://developer.apple.com/documentation/metal/mtlcommandbuffer/present%28_%3A%29
- https://developer.apple.com/documentation/metal/mtldrawable
- https://developer.apple.com/documentation/metal/mtldrawable/addpresentedhandler%28_%3A%29
- https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics
- https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work
- https://developer.apple.com/documentation/metal/customizing-render-pass-setup
- https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- https://developer.apple.com/documentation/quartzcore/cametallayer/presentswithtransaction
- https://developer.apple.com/documentation/quartzcore/cametallayer/displaysyncenabled
- https://developer.apple.com/documentation/analytics-reports/cametallayer-performance
- https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Cmd-Submiss/Cmd-Submiss.html
- https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Render-Ctx/Render-Ctx.html
- https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos
- https://developer.apple.com/documentation/quartzcore/cametaldisplaylink
