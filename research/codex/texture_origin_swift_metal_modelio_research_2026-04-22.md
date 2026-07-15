# Texture Origin Research for Swift, MetalKit, and Model I/O

**Date:** 2026-04-22  
**Scope:** Whether you can determine the correct texture origin before creating an `MTLTexture`, what the default origin behavior is in MetalKit / Model I/O, and what that means for this repo's `TextureLoader.swift`.

## Executive Answer

Short version:

- There is **no single universal API** that tells you "the correct texture origin" for every texture source before loading.
- In Metal itself, the practical texture-memory convention is **top-left**:
  - Apple's Metal sample says the Metal texture origin is top-left.
  - In that same sample, normalized texture coordinate `(0, 0)` addresses the texel at the first byte of texture data, which the sample identifies as the **top-left** corner.
- In `MTKTextureLoader`, omitting `.origin` does **not** mean "assume top-left" or "assume bottom-left". It means: **do not flip**.
- `MTKTextureLoader.Origin.topLeft` and `.bottomLeft` are **metadata-driven conditional flips**, not unconditional declarations of what the source is.
- Model I/O's `MDLTexture` API clearly supports both top-left-origin and bottom-left-origin texel layouts, but I did **not** find a public getter that exposes the currently stored origin before the texels are materialized. That is an **inference from the public API surface** in the current SDK headers.

So the practical answer is:

1. For a **URL-backed image file**, you can sometimes infer origin **before texture creation**, but only by inspecting **format-specific metadata** yourself.
2. For a `MDLTexture`, you can know the origin ahead of time **only if you created it yourself and recorded it**, or if you inspect the original file / asset metadata before wrapping it in `MDLTexture`.
3. If the source format does not expose reliable origin metadata, there is **no robust way to discover it automatically**. In those cases you need a pipeline convention or explicit per-asset metadata.

## Local Repo Context

Current inconsistency in this repo:

- [`TextureLoader.swift`](/Users/albertinopadin/Desktop/Dev/Xcode%20Projects/ToyFlightSimulator/ToyFlightSimulator%20Shared/AssetPipeline/Libraries/Textures/TextureLoader.swift) uses `.topLeft` by default in:
  - `init(textureName:textureExtension:origin:)`
  - `loadTextureFromBundle()`
  - `LoadTexture(name:scale:origin:)`
- The same file uses `.bottomLeft` by default in:
  - `Texture(name:textureOrigin:)`
  - `Texture(url:textureOrigin:)`
  - `Texture(mdlTexture:textureOrigin:)`

That inconsistency matters because `MTKTextureLoader`'s `.topLeft` / `.bottomLeft` values are not just "preferred conventions"; they change whether the loader vertically flips the source texture data.

## What the Apple APIs Actually Guarantee

### 1. Metal's own texture convention is top-left

Apple's "Creating and sampling textures" sample says:

- when copying image bytes into a Metal texture, it flips source rows as needed "to transform the data to the Metal texture origin, which is the top-left"
- normalized texture coordinate `(0.0, 0.0)` addresses the texel at the first byte of texture data, identified as the **top-left corner**

That is the clearest primary-source statement I found for Metal's practical texture-memory convention.

Implication:

- If you manually populate an `MTLTexture` with `replace(region:mipmapLevel:withBytes:bytesPerRow:)`, the byte stream you feed it should normally already be in **top-left-first** row order if you want texture coordinate `(0, 0)` to sample the visual top-left pixel.

### 2. `MTKTextureLoader.Option.origin` means "when to flip", not "what the source already is"

From the current Xcode SDK's `MTKTextureLoader.h`:

- If `.origin` is omitted, `MTKTextureLoader` **does not flip** loaded textures.
- `.topLeft` means: flip only if file metadata says the source starts at the **bottom-left**.
- `.bottomLeft` means: flip only if file metadata says the source starts at the **top-left**.
- `.flippedVertically` means: **always** flip, regardless of metadata.

This is a subtle but important point:

- `.topLeft` is **not** "force top-left no matter what".
- `.bottomLeft` is **not** "force bottom-left no matter what".
- Both depend on metadata that may or may not exist in the source format.

Also from the same header:

- `.origin` cannot be used with **block-compressed** texture formats.
- `.origin` applies only to **2D, 2D array, and cube map** textures.

That means load-time origin correction is inherently limited.

### 3. `MTKTextureLoader` ignores `.origin` for texture assets in asset catalogs

The `MTKTextureLoader` header states that when loading a **texture asset** from an asset catalog, these options are ignored:

- generate mipmaps
- sRGB
- cube-layout
- origin

The option can still matter when the name resolves to an **image asset** rather than a texture asset, but it is not honored for true texture-set assets.

So if any call site uses `newTexture(name:scaleFactor:bundle:options:)` with asset-catalog texture assets, origin guesses there may be a no-op.

### 4. Model I/O supports both origins, but does not appear to expose a public origin getter

From `MDLTexture.h` in the current SDK:

- `MDLTexture` has an initializer with `topLeftOrigin: Bool`
- `MDLTexture` exposes:
  - `texelDataWithTopLeftOrigin()`
  - `texelDataWithBottomLeftOrigin()`
  - mip-level variants of both

Apple's docs for `texelDataWithTopLeftOrigin()` say:

- if the texture was initialized with bottom-left-origin data, the first call creates and caches top-left-origin data

That proves Model I/O internally tracks enough information to convert between the two layouts.

However, I did **not** find a public property or method like:

- `isTopLeftOrigin`
- `origin`
- `currentTexelOrigin`

for `MDLTexture` or `MDLURLTexture`.

**Inference:** the framework knows the origin internally, but the public API does not currently expose it directly for inspection.

### 5. `MDLURLTexture` is lazy, but laziness does not solve the origin-query problem

Apple's docs for `MDLURLTexture.init(url:name:)` say:

- constructing the object does **not** load texel data immediately
- data is loaded later when one of the texture-data accessors is used

That is useful because it delays I/O, but it still does not provide a public "what is the stored origin?" query before load.

### 6. Model I/O also exposes UV flipping, which is a separate lever

`MDLMesh.flipTextureCoordinatesInAttributeNamed(_:)` is documented as converting UVs via:

```swift
(u, v) = (u, 1 - v)
```

The header specifically says many model files assume a **bottom-left bitmap origin**, while it can be more convenient to use an **upper-left bitmap origin**.

This matters because many "my texture is upside down" bugs are actually one of two different problems:

1. the **image byte origin** is wrong
2. the **mesh UV convention** is wrong

Those are not the same fix.

## Can You Know the Correct Origin Before Creating the `MTLTexture`?

## A. If the source is a URL to a standard raster image

Sometimes, yes, but only as a **best-effort metadata inspection**.

For common image formats handled by Image I/O, you can inspect metadata before creating a `CGImage` or `MTLTexture`:

- `CGImageSourceCopyPropertiesAtIndex`
- `kCGImagePropertyOrientation`
- `CGImagePropertyOrientation`

Important nuance:

- `CGImagePropertyOrientation` is a **display-orientation** concept, not a dedicated "texture origin" API.
- It can describe rotations and mirroring, not just top-left vs bottom-left.
- `CGImagePropertyOrientation.up` is the simple case where the encoded image data already matches the intended display orientation, and Apple's docs say `(0,0)` is the **leftmost column and top row**.

So for ordinary raster images, Image I/O metadata can help you preflight the file, but it is not a universal substitute for explicit texture-origin metadata.

### Code Sample: Best-Effort Preflight for Image I/O Files

```swift
import Foundation
import ImageIO

func imageOrientationMetadata(at url: URL) -> CGImagePropertyOrientation? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let rawValue = props[kCGImagePropertyOrientation] as? UInt32 else {
        return nil
    }

    return CGImagePropertyOrientation(rawValue: rawValue)
}

let orientation = imageOrientationMetadata(at: textureURL)

switch orientation {
case .up?:
    // Encoded data already matches intended display orientation.
    // Per Apple's docs, this is the straightforward top-left / top-down case.
    break
case nil:
    // No orientation metadata found. You do not have enough information here
    // to infer a universal texture origin with confidence.
    break
default:
    // Rotated or mirrored image metadata exists.
    // Decide whether your pipeline normalizes these cases up front.
    break
}
```

## B. If the source is a KTX file

Yes, if you parse the KTX metadata yourself.

The Khronos KTX specs define `KTXorientation` metadata. For 2D textures:

- `rd` means:
  - `r`: S increases to the right
  - `d`: T increases downward
  - practical meaning: **top-left origin**
- `ru` means:
  - `r`: S increases to the right
  - `u`: T increases upward
  - practical meaning: **bottom-left origin**

KTX also explicitly says the preferred default for authoring tools is the logical **upper-left** corner where possible.

So for KTX, the right answer is not guessing with `.topLeft` / `.bottomLeft`; the right answer is parsing `KTXorientation` if present.

### Code Sample: Mapping KTX Orientation Metadata

```swift
enum LogicalTextureOrigin {
    case topLeft
    case bottomLeft
    case unsupported(String)
}

func originFromKTXorientation(_ value: String) -> LogicalTextureOrigin {
    switch value {
    case "rd":
        return .topLeft
    case "ru":
        return .bottomLeft
    default:
        return .unsupported(value)
    }
}
```

Important caveat:

- `MTKTextureLoader.Option.origin` cannot be used with block-compressed texture formats.
- Many KTX files are block-compressed.
- So even when the source orientation is knowable, the load-time fix may still need to happen at **authoring time**, by **UV transform**, or by using a different import path.

## C. If the source is already an `MDLTexture`

Usually **no**, not from the public API alone.

Cases:

1. **You created the `MDLTexture` yourself with `init(data:topLeftOrigin:...)`**
   - Then yes, you know the answer, because you supplied it.
2. **You received an `MDLURLTexture` or a `MDLTexture` from imported asset data**
   - I did not find a public origin getter.
   - You can force texel access in top-left or bottom-left form, but that is already part of materializing / converting the texture data.

If you need this to be deterministic, the asset pipeline should carry origin information alongside the `MDLTexture`.

### Code Sample: Sidecar Metadata for Model I/O Textures

```swift
import Foundation
import MetalKit
import ModelIO

enum KnownTextureOrigin {
    case topLeft
    case bottomLeft
    case unknown
}

struct TextureRecord {
    let url: URL?
    let mdlTexture: MDLTexture
    let knownOrigin: KnownTextureOrigin
}

func loaderOrigin(for record: TextureRecord) -> MTKTextureLoader.Origin? {
    switch record.knownOrigin {
    case .topLeft:
        return .topLeft
    case .bottomLeft:
        return .bottomLeft
    case .unknown:
        return nil
    }
}
```

## What Is the Default Origin?

This question has three different answers depending on which layer you mean.

### 1. Metal texture memory / sampling convention

For practical Metal usage, the default convention is **top-left**.

Primary basis:

- Apple's Metal sample explicitly calls top-left the "Metal texture origin".
- The sample also says `(0, 0)` texture coordinates identify the texel at the first byte of texture data, the top-left corner.

### 2. `MTKTextureLoader` when `.origin` is omitted

The default is **no flip**.

That is different from saying the default is top-left or bottom-left.

It means the resulting `MTLTexture` preserves whatever vertical ordering the loader got from the source path, subject to whatever metadata normalization the underlying image stack may or may not already have performed.

### 3. Model I/O `MDLTexture`

I did **not** find a documented universal default origin for every `MDLTexture` source type.

What is documented:

- `MDLTexture` can be initialized with explicit `topLeftOrigin`
- it can return texels in either top-left or bottom-left organization

What is **not** documented, as far as I found:

- a universal statement that every `MDLURLTexture` or every imported `MDLTexture` always starts life as top-left or bottom-left

So the safe answer is:

- `MDLTexture` supports both, but there is no public, universal default contract you should rely on across all source types.

## The Most Important Behavioral Trap in `MTKTextureLoader`

`MTKTextureLoader.Origin.topLeft` and `.bottomLeft` only help when the loader can tell what the source origin already is.

If the source file or in-memory representation does **not** carry metadata that the loader understands:

- `.topLeft` may do nothing
- `.bottomLeft` may do nothing

If you already know the texture is upside down regardless of metadata, `.flippedVertically` is the only option that explicitly says "always flip".

That is why "I want the correct origin instead of guessing" has a hard limit:

- if the source itself does not tell you, there may be nothing to discover automatically

## Practical Guidance for This Repo

Based on the research above, the safest design direction for this codebase is:

1. Choose one engine convention for runtime `MTLTexture` data.
   - For Metal, top-left is the most natural convention.
2. Treat `MTKTextureLoader.Option.origin` as a **conditional correction** for sources that carry usable metadata.
3. Do not rely on `.topLeft` or `.bottomLeft` as universal fixes.
4. For imported 3D assets, separately decide whether the mismatch lives in:
   - the image bytes
   - the UVs
   - a `MDLTextureSampler.transform`
5. If the asset pipeline cannot reliably expose origin metadata, store explicit per-asset origin information rather than guessing at each load site.

## Repo-Specific Interpretation

Applied to [`TextureLoader.swift`](/Users/albertinopadin/Desktop/Dev/Xcode%20Projects/ToyFlightSimulator/ToyFlightSimulator%20Shared/AssetPipeline/Libraries/Textures/TextureLoader.swift):

- the `.topLeft` defaults and `.bottomLeft` defaults are not just inconsistent style choices
- they encode different flipping behavior
- because those choices are spread across overloads, the same underlying image could load differently depending on which overload a caller happens to use

That should be treated as a correctness problem, not just an API-cleanup problem.

## Additional Note: UV Transforms Can Also Matter

Model I/O's `MDLTextureSampler` has a `transform` property that applies a transform to texture coordinates before sampling.

That means an imported material can look "correct" or "upside down" for reasons that are **independent** of the raw image's byte origin.

So if you later standardize this pipeline, texture-origin handling and texture-coordinate handling should be audited together.

## Bottom-Line Answers

### Is there a way to know the correct texture origin before actually loading / creating the texture?

- **Sometimes**, but only when the source format exposes metadata you can inspect first.
- For ordinary raster files, Image I/O can expose orientation metadata.
- For KTX, `KTXorientation` can expose the logical orientation.
- For a generic `MDLTexture`, there is **no public universal getter** for the stored origin that I found.
- If the source does not expose reliable metadata, you cannot robustly infer the correct origin automatically.

### What is the default origin for textures?

- **Metal texture convention:** top-left.
- **`MTKTextureLoader` default when `.origin` is omitted:** no flip.
- **Model I/O:** supports both, but I did not find a documented universal default for all `MDLTexture` sources.

## Local Primary Sources Used

- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/MetalKit.framework/Headers/MTKTextureLoader.h`
- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/ModelIO.framework/Headers/MDLTexture.h`
- `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.4.sdk/System/Library/Frameworks/ModelIO.framework/Headers/MDLMesh.h`
- `/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AssetPipeline/Libraries/Textures/TextureLoader.swift`
- `/Users/albertinopadin/Desktop/Dev/Xcode Projects/ToyFlightSimulator/ToyFlightSimulator Shared/AssetPipeline/Material.swift`

## URLs Visited

- https://developer.apple.com/documentation/metalkit/mtktextureloader/origin?language=objc
- https://developer.apple.com/documentation/MetalKit/MTKTextureLoader?language=_3
- https://developer.apple.com/documentation/metalkit/mtktextureloader/option
- https://developer.apple.com/documentation/metalkit/mtktextureloader/origin/flippedvertically
- https://developer.apple.com/documentation/metalkit/mtktextureloader/newtexture%28texture%3Aoptions%3A%29
- https://developer.apple.com/documentation/metal/textures/creating_and_sampling_textures
- https://developer.apple.com/documentation/imageio/cgimagepropertyorientation?language=objc
- https://developer.apple.com/documentation/imageio/kcgimagepropertyorientation
- https://developer.apple.com/documentation/imageio/cgimagesourcecopypropertiesatindex%28_%3A_%3A_%3A%29?changes=la
- https://developer.apple.com/documentation/imageio/cgimagepropertyorientation/kcgimagepropertyorientationup?language=o_3
- https://developer.apple.com/documentation/ModelIO/MDLTexture/texelDataWithTopLeftOrigin%28%29
- https://developer.apple.com/documentation/modelio/mdltexture/texeldatawithtopleftorigin%28%29
- https://developer.apple.com/documentation/modelio/mdltexture/texeldatawithtopleftorigin%28%29?changes=l_2&language=objc
- https://developer.apple.com/documentation/modelio/mdltexture/texeldatawithtopleftorigin%28atmiplevel%3Acreate%3A%29?changes=la&language=objc
- https://developer.apple.com/documentation/modelio/mdlurltexture/init%28url%3Aname%3A%29?changes=_6__8
- https://developer.apple.com/documentation/modelio/mdltexturesampler
- https://registry.khronos.org/KTX/specs/2.0/ktxspec.v2.html
- https://registry.khronos.org/KTX/specs/1.0/ktxspec.v1.html
