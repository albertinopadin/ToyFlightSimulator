# Metal Drawable Acquisition and Presentation: Best Practices Research

**Date:** 2026-04-19
**Subject:** [TiledMultisampleRenderer.swift:172](ToyFlightSimulator%20Shared/Display/TiledMultisampleRenderer.swift#L172) — current drawable acquired before ~1–8 ms of compute/render encoding work.
**Question:** Is it OK to gate render commands on `view.currentDrawable != nil`, or is it better to encode work first and acquire the drawable only just before `present`?

---

## TL;DR

1. **Apple's own guidance is unambiguous**: acquire the drawable as late as possible, release it as soon as possible. The current code acquires it earlier than Apple recommends.
2. **Both your patterns ("gate on availability" and "encode first, present last") are conceptually valid**, but the literal pseudocode you proposed has a subtle defect for *this* renderer: it would still touch view‑owned resources during encoding.
3. **In `TiledMultisampleRenderer.draw(in:)`, line 175** reads `view.currentRenderPassDescriptor` to copy the lighting color attachment into `tiledDeferredRenderPassDescriptor`. **Reading `currentRenderPassDescriptor` implicitly acquires the drawable**, so the early `view.currentDrawable` on line 172 is not the only thing tying the frame to a view‑managed drawable.
4. **You can safely keep the current implementation if you are not seeing stutter, present-delay spikes, or `nextDrawable` blocking** in Instruments / Metal Performance HUD. Apple's WWDC 2019 Session 606 explicitly frames the "acquire late" rule as a *latency and pacing* optimization, not a correctness requirement.
5. **If you want to follow the canonical pattern**, you must stop using the view's drawable‑backed render pass for the GBuffer/lighting/MSAA‑resolve pass and instead resolve into an app‑owned texture, then composite that texture into the drawable in a final, short pass. Only then does delaying the `currentDrawable` fetch actually buy you anything.

---

## What the Code Currently Does

In [TiledMultisampleRenderer.swift:155-208](ToyFlightSimulator%20Shared/Display/TiledMultisampleRenderer.swift#L155):

```swift
override func draw(in view: MTKView) {
    ...
    render {
        runDrawableCommands { commandBuffer in           // CB #1: shadow
            commandBuffer.label = "Shadow Commands"
            encodeMSAAShadowPass(into: commandBuffer)
        }

        if let drawable = view.currentDrawable {         // ← line 172: drawable acquired
            runDrawableCommands { commandBuffer in       // CB #2: GBuffer + composite
                ...
                let viewColorAttachment = view.currentRenderPassDescriptor!  // ← line 175
                    .colorAttachments[TFSRenderTargetLighting.index]
                tiledDeferredRenderPassDescriptor
                    .colorAttachments[TFSRenderTargetLighting.index] = viewColorAttachment

                encodeParticleComputePass(into: commandBuffer)               // GPU: compute
                encodeRenderPass(... GBuffer & Lighting Pass ...) { ... }    // GPU: G-buffer
                encodeRenderPass(... Composite Pass ...) { ... }             // GPU: composite

                commandBuffer.present(drawable)                              // ← line 204
            }
        }
    }
}
```

`runDrawableCommands` (in [Renderer.swift:71-95](ToyFlightSimulator%20Shared/Display/Renderer.swift#L71)) commits the command buffer immediately after the closure returns. So the lifetime of the drawable in CB #2 is roughly:

1. `view.currentDrawable` returned (line 172).
2. `view.currentRenderPassDescriptor` read (line 175) — already implicitly acquired by step 1, but worth noting it would acquire it on its own.
3. CPU‑side encoding of the particle compute pass.
4. CPU‑side encoding of the GBuffer + lighting + transparency + particle render + MSAA‑resolve pass.
5. CPU‑side encoding of the composite pass into `drawable.texture`.
6. `commandBuffer.present(drawable)` (line 204).
7. `commandBuffer.commit()` inside `runDrawableCommands`.

The 1–8 ms you measured is the wall‑clock distance between (1) and (7), and that is exactly the window Apple keeps telling people to minimize.

The shadow command buffer (CB #1) is already committed before the drawable is acquired, which is good and matches Apple's "early GPU submission" recommendation from WWDC 2019. So the renderer is partially aligned with best practices already.

---

## What Apple Explicitly Recommends

### "Hold a drawable as briefly as possible"

The archived **Metal Best Practices Guide — Drawables** is the most quotable source. The key paragraphs:

> "Drawables are expensive system resources created and maintained by the Core Animation framework. They exist within a limited and reusable resource pool and may or may not be available when requested by your app. **If there is no drawable available at the time of your request, the calling thread is blocked until a new drawable becomes available** (which is usually at the next display refresh interval)."

> "Always **acquire a drawable as late as possible**; preferably, immediately before encoding an on‑screen render pass. A frame's CPU work may include dynamic data updates and off‑screen render passes that you can perform before acquiring a drawable."

> "Always **release a drawable as soon as possible**; preferably, immediately after finalizing a frame's CPU work. It is highly advisable to contain your rendering loop within an autorelease pool block to avoid possible deadlock situations with multiple drawables."

> "A drawable's presentation is registered by calling a command buffer's `presentDrawable:` method before calling its `commit` method. **Do not wait for the command buffer to complete its GPU work before registering a drawable presentation; this will cause a considerable CPU stall.**"

The same guide gives a model frame structure (Listing 6‑1):

1. Update dynamic data.
2. Encode off‑screen render passes.
3. Acquire `currentRenderPassDescriptor` / drawable.
4. Encode on‑screen render pass.
5. `presentDrawable:`.
6. `commit`.

### `MTKView.currentRenderPassDescriptor` implicitly acquires the drawable

This is the part most easily missed. Apple's `MTKView` documentation states that `currentRenderPassDescriptor` is constructed from the drawable's texture and **reading it triggers acquisition of `currentDrawable`**. From a behavioral standpoint:

- `view.currentDrawable` and `view.currentRenderPassDescriptor` are *both* drawable‑acquisition points.
- For a frame, only the first read pays the cost; later reads return cached state.
- For your renderer, even if you removed line 172, line 175 would still acquire the drawable.

That makes the literal pseudocode you proposed:

```swift
runDrawableCommands {
    encodeRenderPass { ... }
}
guard let drawable = view.currentDrawable else { return }
commandBuffer.present(drawable)
```

…only beneficial if **none of the encoded passes** touch `view.currentDrawable`, `view.currentRenderPassDescriptor`, the view's depth/stencil texture, or any view‑owned resolve attachment. In your renderer today, the GBuffer/lighting pass does touch the view's lighting attachment, so just reordering control flow does not buy you the late‑acquisition benefit.

### Use the command‑buffer presentation path

`commandBuffer.present(drawable)` is the right call for `MTKView`/`CAMetalLayer` in the normal path (the exception is `presentsWithTransaction = true`, which you do not use). Apple repeatedly warns *not* to call `waitUntilCompleted` or `waitUntilScheduled` on the command buffer before registering presentation — that defeats the GPU pipelining the drawable system is built around.

### WWDC 2019 Session 606 ("Delivering Optimized Metal Apps and Games")

This is the most useful single source on *why* the rule exists. The session's recommended pattern is:

> "Scheduling all the off‑screen GPU work early is very important. It will improve the latency and responsiveness of your game and it will also allow the system to adapt to the workload much better. So, it is important that you have multiple GPU submissions in your frame. In particular, you will want **an early GPU submission before waiting for the drawables since that stalls the render thread**. And after you get the drawable which will be **as late as possible in the frame**, you will then have a late GPU submission where you will schedule all the on‑screen work."

> "First create the command buffer to encode all the off‑screen work which will be your early GPU submission. You will commit the command buffer and then wait for the next drawable, which will stall your thread. **After you have the drawable, you will create one final command buffer where you will encode all the on‑screen work and present the drawable.**"

This is exactly the architecture your shadow pass already follows for CB #1, and exactly the architecture your GBuffer/lighting/composite pass does *not* follow for CB #2.

---

## Drawable Pool Mechanics (Why "Late" Matters)

- `CAMetalLayer.maximumDrawableCount` can only be `2` or `3`. Default is `3`.
- `nextDrawable()` blocks the calling thread until a drawable is available. It can wait roughly one second before returning `nil` (controlled by `allowsNextDrawableTimeout`).
- The drawable pool is the *primary* mechanism by which Metal pipelines CPU encoding (frame N), GPU rendering (frame N‑1), and display compositing (frame N‑2). Holding a drawable longer than necessary shrinks the effective queue and forces the next `nextDrawable()` call to wait for the display refresh.
- On a 60 Hz display, frame budget is 16.67 ms. On 120 Hz ProMotion it is 8.33 ms. **A 1–8 ms unnecessary hold is between 6 % and ~96 % of a 120 Hz frame budget.** That is enough to push the system from "headroom available" to "thread blocked at `nextDrawable`" once anything else (GC, compositor, system thermal throttling) consumes time.

The Flutter Impeller team explicitly cited Apple's "as late as possible" rule when deferring drawable acquisition on iOS 120 Hz devices, noting that drawable acquisition stalls were consuming 4 ms+ on ProMotion screens — i.e., Apple's own platform team and major framework consumers treat this as a real performance lever, not a stylistic preference.

---

## Answering the Two Questions Directly

### Q1: "Is it OK to only issue render commands if the drawable is non‑nil?"

**Yes — for the *on‑screen* portion of the frame.** It is correct and idiomatic to gate the on‑screen pass on drawable availability:

```swift
guard let drawable = view.currentDrawable,
      let descriptor = view.currentRenderPassDescriptor else { return }
```

This is what Apple's own Metal Game template does (per Apple Engineer's reply on Apple Developer Forums thread 689320).

But there are two subtleties:

1. **Don't gate work that doesn't need the drawable on drawable availability.** Simulation, culling, shadow maps, off‑screen GBuffers, particle compute updates, post‑processing into app‑owned textures — all of that can run without a drawable. In your renderer the shadow pass already follows this rule; the deferred GBuffer/lighting pass does not (because it writes into the view's lighting attachment).
2. **`nil` from `view.currentDrawable` is rare in healthy code paths but not impossible.** Backgrounding, layer disconnection, drawable timeouts after ~1 s, and certain compositor states can produce `nil`. Skipping the on‑screen pass in that case is the right behavior; *don't* spin or retry, just drop the frame.

### Q2: "Is it better to eagerly issue render commands and only obtain/present the drawable AFTER all render commands have been issued?"

**Conceptually yes**, and that is exactly the WWDC 2019 prescription. **In practice, for this renderer, your literal pseudocode would not work** because:

- The GBuffer/lighting pass writes into `view.currentRenderPassDescriptor.colorAttachments[Lighting]` (line 175). The first time you read `currentRenderPassDescriptor`, the drawable is acquired.
- The composite pass at line 196 binds `drawable.texture` directly as the color attachment.

So if you literally wrote:

```swift
runDrawableCommands { commandBuffer in
    encodeMSAAShadowPass(into: commandBuffer)
    encodeParticleComputePass(into: commandBuffer)
    encodeRenderPass(into: commandBuffer, using: tiledDeferredRenderPassDescriptor) { ... }
    encodeRenderPass(into: commandBuffer, using: compositeRenderPassDescriptor) { ... }
}
guard let drawable = view.currentDrawable else { return }
commandBuffer.present(drawable)
```

…you would still trigger drawable acquisition the moment you touched `view.currentRenderPassDescriptor`, *and* you would not have a valid attachment for the composite pass before the drawable existed. The reordering is cosmetic without a deeper change.

The **deeper change** is: stop using view‑owned resources for any pass except the final composite. Specifically:

1. Allocate an app‑owned `MTLTexture` (call it `lightingResolveTexture`) sized to the drawable, with `pixelFormat` matching the view's color pixel format and `usage` including `.renderTarget` and `.shaderRead`.
2. In `tiledDeferredRenderPassDescriptor`, point the lighting attachment's `resolveTexture` (or `texture` if no MSAA) at `lightingResolveTexture` instead of copying it from `view.currentRenderPassDescriptor`.
3. Encode shadow + particle compute + GBuffer/lighting/MSAA‑resolve into the early command buffer using only app‑owned textures. Commit it.
4. **Now** acquire `view.currentDrawable` (or `view.currentRenderPassDescriptor` — they are equivalent in cost).
5. Open a new, very short command buffer, encode a single full‑screen composite that samples `lightingResolveTexture` and writes to `drawable.texture`, call `commandBuffer.present(drawable)`, commit.

That structure mirrors WWDC 2019 Session 606's two‑command‑buffer pattern *and* is consistent with what Apple's own deferred‑lighting sample (the one your `Renderer.runDrawableCommands` comment links to) does in spirit.

A sketched control flow:

```swift
override func draw(in view: MTKView) {
    if firstRun { ... }

    render {
        // Early CB: nothing here touches the drawable.
        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Shadow + GBuffer + Lighting (offscreen)"
            encodeMSAAShadowPass(into: commandBuffer)
            encodeParticleComputePass(into: commandBuffer)
            encodeRenderPass(into: commandBuffer,
                             using: tiledDeferredRenderPassDescriptor,   // resolves into appOwnedLightingTexture
                             label: "GBuffer & Lighting Pass") { encoder in
                ...
                encodeMSAAResolveStage(using: encoder)
            }
        }

        // Late CB: acquire drawable here, do the absolute minimum on it.
        guard let drawable = view.currentDrawable,
              let viewDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        runDrawableCommands { commandBuffer in
            commandBuffer.label = "Composite + Present"
            // Either compositeRenderPassDescriptor pointed at drawable.texture,
            // or use viewDescriptor directly and bind the resolved lighting
            // texture as a fragment input.
            encodeRenderPass(into: commandBuffer,
                             using: compositeDescriptorTargetingDrawable,
                             label: "Composite Pass") { encoder in
                encodeCompositeStage(using: encoder)
            }
            commandBuffer.present(drawable)
        }
    }
}
```

The composite pass is intentionally trivial (one full‑screen quad sampling one texture). Encoding it should take well under 100 µs, so the drawable lifetime drops from ~1–8 ms to microseconds.

---

## Symptoms If This Becomes a Problem

You said you currently see no ill effects. That is plausible — the renderer is healthy at 60 Hz with the work it does today, and the drawable pool is forgiving in steady state. The symptoms to watch for, in approximate order of how early they show up:

1. **`Thread blocked waiting for next drawable`** notes in Instruments → Metal System Trace. This is the first concrete indicator that `nextDrawable()` is stalling. Apple Forums thread 722434 walks through how to read this.
2. **Spikes in Frame Interval / Pretime** on the Metal Performance HUD. If average frame interval is ~16.7 ms but the HUD shows red maximums of 33+ ms, the render thread is occasionally stalling — drawable acquisition is one of the common causes.
3. **"On‑glass present lateness"** in the App Store CAMetalLayer Performance analytics report. This is a direct measurement of frames whose presentation slipped past their intended display interval.
4. **ProMotion downclocking misbehavior**. Like Zed observed, irregular drawable presentation can cause the display to fail to stay at 120 Hz; you get "120 Hz, but choppy" instead of the smooth low‑latency mode.
5. **Cascading frame delays under transient CPU load**. The Apple Forums thread 107302 documented this as a "command buffer traffic jam": a single late frame cascades into many late frames because the drawable pool stays starved. This is more pronounced with `presentsWithTransaction`, but the underlying mechanism (holding a drawable across CPU work) is the same.
6. **Higher input‑to‑photon latency**. Even when frame rate looks fine, total latency rises because each frame's drawable is acquired earlier in the frame's wall‑clock timeline, pushing the GPU's *actual* work later in that timeline.
7. **More frequent `nil` from `view.currentDrawable`** in pathological cases — drawable timeouts, layer reconfiguration, etc. With the current code this manifests as a dropped frame and is recoverable.
8. **Hard hangs on background/foreground transitions** if `allowsNextDrawableTimeout = false` was ever set. This is a known macOS pitfall (Zed issue #53390 and gfx‑rs #2460 both bit it).

The pattern across all of these is the same: holding a drawable for milliseconds when you only need it for microseconds steals from the scheduling slack the system uses to absorb jitter.

---

## How to Measure Whether It Is Hurting You

You can answer "is this actually a problem yet?" without changing any code, using these tools:

1. **Metal Performance HUD** (set `MTL_HUD_ENABLED=1` in the scheme, or call `view.layer.setValue(true, forKey: "MTLHUDEnabled")` for the layer). Watch the frame‑interval and GPU‑time graphs. Red maxima on frame interval indicate stalls; if the GPU graph stays flat while frame interval spikes, the stall is on the CPU side, and `nextDrawable` is a likely suspect.
2. **Instruments → Metal System Trace** (or Game Performance template). This will *explicitly* call out drawable waits, plus tie command‑buffer scheduling, GPU execution, and surface presentation timestamps to one timeline. This is the definitive way to see whether the drawable is being held longer than it should be.
3. **`MTLDrawable.addPresentedHandler(_:)` + `drawable.presentedTime`**. Lets you log actual on‑glass time vs. expected, which is the cleanest in‑app way to measure present‑lateness.
4. **App Store CAMetalLayer Performance report** (post‑release). Surfaces aggregate `Skipped Frame Count`, `On Glass Present Lateness Count`, and `Presented GPU Done‑To‑Completed Total` across real users.

If you do this and *don't* see any drawable waits or present lateness, the current code is empirically fine. The architectural advice in this document is then a hedge against future scope (more passes, ProMotion targets, more aggressive workloads).

---

## Recommendation for `TiledMultisampleRenderer`

**If you do nothing**: the current code is likely fine at 60 Hz and probably fine at 120 Hz today, given that you are not seeing stutter. The shadow pass already follows the early‑submit pattern. The risk is purely about the future: as the GBuffer/lighting/composite work grows, the drawable‑held window grows with it, and at some point you will start seeing the symptoms above.

**If you want to fix it properly**: the change is not "move the `guard` lower"; it is "decouple the GBuffer/lighting pipeline from view‑owned resources." Concretely:

1. Add an app‑owned `lightingResolveTexture` (sized from `mtkView(_:drawableSizeWillChange:)` and `updateDrawableSize(size:)`).
2. Make `tiledDeferredRenderPassDescriptor.colorAttachments[TFSRenderTargetLighting.index].resolveTexture` point at it permanently.
3. Remove the line that copies `view.currentRenderPassDescriptor.colorAttachments[Lighting]` into the descriptor.
4. Submit the early CB (shadow + particle compute + GBuffer/lighting/resolve) without ever touching the view.
5. Acquire the drawable, open the late CB, run the composite into `drawable.texture`, present, commit.

That refactor would also make the renderer's resource lifetimes more explicit and less coupled to `MTKView` internals, which is generally a maintenance win.

**If you want a pragmatic middle ground**: at minimum, move `view.currentDrawable` and the `view.currentRenderPassDescriptor` read so they happen *immediately before* the composite pass rather than *immediately before* the GBuffer pass. You will still pay the early‑acquisition cost from the view's perspective if the GBuffer pass uses any view‑owned attachment, but if the composite is the only thing that needs the drawable, doing the GBuffer/lighting work into a copy of the descriptor (without referencing the view) and then composing late is a smaller change that captures most of the benefit.

---

## Edge Cases and Caveats

- **`presentsWithTransaction = true`**: changes the rules. You must not use `MTLCommandBuffer.present(_:)` and must instead drive presentation through a Core Animation transaction. You are not in this case (`MTKView` defaults to `false`), so this is a footnote.
- **`displaySyncEnabled = false`** (macOS): reduces latency by skipping vsync but introduces tearing. Doesn't change drawable lifetime advice.
- **Variable refresh rate / ProMotion**: aggravates the cost of holding the drawable, because the system uses the timing of consecutive presentations to decide what refresh rate to drive the panel at. Inconsistent presentation timing can cause the panel to drop from 120 Hz to 60 Hz, which is more visually disruptive than just running at 60 Hz steadily.
- **`maximumDrawableCount = 2`**: halves your scheduling slack. If you ever set this for memory reasons, the late‑acquire pattern becomes much more important.
- **Paused MTKView**: not your case (you use the delegate path), but if you ever switch to manual driving with `isPaused = true`, you must call `nextDrawable()` directly on the layer rather than reading `view.currentDrawable`, per the Apple‑engineer canonical reply on Forums thread 689320.

---

## URLs Visited

- https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html
- https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html
- https://developer.apple.com/documentation/metalkit/mtkview/currentdrawable
- https://developer.apple.com/documentation/metalkit/mtkview/currentrenderpassdescriptor
- https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()
- https://developer.apple.com/documentation/quartzcore/cametallayer/maximumdrawablecount
- https://developer.apple.com/documentation/metal/mtlcommandbuffer/1443029-presentdrawable
- https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work
- https://developer.apple.com/documentation/metal/customizing-render-pass-setup
- https://developer.apple.com/documentation/metal/using-metal-to-draw-a-views-contents
- https://developer.apple.com/documentation/Metal/rendering-a-scene-with-deferred-lighting-in-swift
- https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics
- https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance
- https://developer.apple.com/forums/thread/689320
- https://developer.apple.com/forums/thread/722434
- https://developer.apple.com/forums/thread/107302
- https://developer.apple.com/videos/play/wwdc2019/606/
- https://developer.apple.com/videos/play/tech-talks/110339/
- https://asciiwwdc.com/2019/sessions/606
- https://metalbyexample.com/modern-metal-1/
- https://github.com/flutter/flutter/issues/138490
- https://github.com/floooh/sokol/issues/504
- https://zed.dev/blog/120fps
- https://www.macgaming.com/article/unlocking-the-mac-performance-overlay-a-deep-dive-into-mtl-hud-enabled
