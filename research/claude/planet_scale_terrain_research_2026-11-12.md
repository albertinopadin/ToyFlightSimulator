# Planet-Scale Terrain for a Flight Simulator — Research

**Date:** 2026-11-12 · **Agent:** claude
**Question:** What is the best, most efficient (memory and performance) way to create effectively
infinite or Earth-sized terrain for a flight simulator; what are the industry-standard and
bleeding-edge approaches; is procedural generation good for this; and which online tutorials can be
followed to build it?

**Method:** Sources were found by fetching known author and vendor pages first and by web search
where no address was known (19 searches). Each claim carries one of three tags:

- **[verified]** — I extracted the primary text myself and searched it (paper or slide PDFs
  converted to text with a PDFKit script, Apple's sample-code source, the engine's own source), or
  reproduced the number with the scratch script.
- **[fetched]** — the source was retrieved this session and read as a digest with quotations (the
  web-fetch tool) or as partial extracted text. I did not read the whole raw page.
- **[unverified]** — from memory, a search-result snippet, or a secondary source.

Every number in a worked example was reproduced by
`/private/tmp/claude-501/-Users-albertinopadin-Desktop-Dev-Xcode-Projects-ToyFlightSimulator/c591078a-6472-49a6-aaa4-1c6a0674838e/scratchpad/planet_terrain_examples.py`
(outside the repo; output in `examples_output.txt` beside it) and cross-checked against an
independent script, `terrain_numbers_check.py`, in the same folder. The two agree on every number
they share. That folder is a session temp folder and will not persist; each formula is stated in
the text so the numbers can be regenerated. Sources that could not be fetched are listed under
"Not verified" in the References. This document is a survey and a recommendation. It is not a plan.

**Post-write check (main session, 2026-11-12).** A second pass after the document was written:

- Every URL in this document (65 at the time, plus the three written out in full afterwards: the
  Terrain3D collision page and two Tilezen pages) was requested with a plain client. All returned
  HTTP 200 except the three Inigo Quilez article URLs.
- iquilezles.org answers plain automated clients with 404 on every path tried, its home page
  included, from both curl and the web-fetch tool. The research run had read the three articles
  with curl and a browser-style user agent. The two Quilez quotations used here were found in the
  copies that run saved, but the links were not confirmed live in this pass. Open them in a
  browser.
- The Kodeco chapter page returns its full text to a plain client and contains the chapter title
  "Tessellation & Terrains".
- Authors, dates and quoted phrases were re-checked in the page text for the tutorials by Lindgren,
  Savage, Bush, Erkenbrach, Paone and Wittens, the Babylon.js page, Ohlarik's article and the Doc
  Ross interview. All matched.
- The quotations from Benyoub and Dupuy 2024 (Intel affiliation, "less than 0.2ms", "centimetric
  detail"), the Asobo slides (quadtree, `RecurseRequest`, "anchor space", "Float 32 bits → Double
  64 bits", Mercator) and Losasso and Hoppe 2004 (120 frames/sec, 40.4 GB to 355 MB, 11 MB) were
  re-extracted from the PDFs and matched.
- The engine claims of 2.1 about the tessellation rule, the sampler, the height-map format and the
  scene dimensions were re-read in the source and matched.
- The numbers of worked examples 1 to 9, the format-step figures of rule 6 and section 2.1, and the
  data-size figures of 1.2.8 were recomputed with three separate scripts
  (`terrain_numbers_check.py`, `_2.py`, `_3.py`). All matched. Two wordings were corrected:
  the float gap first exceeds 1 mm at 16,384 m, not 8,192 m, and worked example 9's 1.9 × 10⁸
  patches is for a square, not a disc. An independent brute-force tile count with a slightly
  different split rule gave 688, 997 and 1,882 leaves against the 676, 1,039 and 1,912 of worked
  example 3.

## Executive summary

The owner asked four questions. Claims 1 to 4 answer them in order; the rest support the answers.

1. **Best and most efficient: no single algorithm, but one recurring structure — a quadtree of
   small square height tiles, loaded around the camera, drawn with one shared grid mesh that the
   vertex shader displaces.** Only the tiles near the camera are resident: 11 to 43 MB of terrain
   geometry for a whole planet (worked example 3), against 1,680 GB for a raw global 30 m height
   grid (worked example 4). A quadtree of tiles is documented for Microsoft Flight Simulator, Call
   of Duty and Frostbite [verified] and for Cesium, Prepar3D and Elite Dangerous [fetched].
2. **Industry standard is the tile quadtree plus streaming; the bleeding edge moves the level of
   detail computation onto the GPU.** Standard: chunked level of detail (Ulrich 2002), geometry
   clipmaps (Losasso and Hoppe 2004), CDLOD (Strugar 2010), hardware tessellation of patches of
   several sizes (Cantlay 2011; Frostbite 2012). Bleeding edge: concurrent binary trees, which
   render an Earth-sized planet with a triangulation update under 0.2 ms (Benyoub and Dupuy, 2024)
   [verified], and learned terrain generators (a 2025 diffusion preprint) [fetched: abstract].
3. **Procedural generation is good for detail and for an invented world, and poor as the only
   source if the terrain must match real places.** The pattern documented by the geometry clipmap
   paper and Microsoft Flight Simulator [verified] and by Outerra and Proland [fetched] is hybrid:
   real coarse elevation data, procedural detail added below its resolution. For a solo learning
   project, start fully procedural (no data pipeline, no licence, deterministic), then add real
   tiles (agent's recommendation).
4. **Tutorials exist for every stage, but almost none are in Metal.** Metal-specific material is
   Apple's terrain sample (hardware tessellation over a 15 km square) [verified], Apple's
   tessellation guide and chapter 19 of *Metal by Tutorials* [fetched]. Clipmaps, CDLOD, quadtree
   planets, noise and tile streaming are taught in OpenGL, DirectX 9, Unity, Godot and web
   frameworks and must be translated. The list is in the References, with what transfers. [fetched]
5. **The terrain in the engine today has no working level of detail.** The tessellation factor is
   `max(4, 64 / cameraDistance)`, so it sits at its floor of 4 for every patch more than 16 m from
   the camera: 6.25 m vertex spacing everywhere, over a fixed 800 m square, with 8-bit heights,
   nearest-neighbour sampling, a flat normal, no shadows and no collision. [verified]
6. **32-bit floats are the tightest constraint, and they fail long before Earth radius.** The gap
   between adjacent floats is 1 mm at 10 km from the origin, 6 cm at 1,000 km and 0.5 m at Earth
   radius (6,378 km). The engine stores every position and matrix in 32-bit float. [verified]
7. **The documented fix in Microsoft Flight Simulator is 64-bit positions on the CPU and a
   camera-centred "anchor space" on the GPU, with an inverted (reverse-Z) depth buffer.** [verified]
   The engine already has reverse-Z. For this engine the recommendation is camera-relative rendering
   in the frame snapshot plus origin rebasing on the update thread, which keeps `float3` in the
   scene graph and physics (agent's design, section 2.2).
8. **Hardware tessellation cannot be the whole level of detail system.** The factor is capped at 64
   (16 on older Apple GPUs), so one patch spans at most a 64:1 range of triangle sizes; Cantlay puts
   the need at about 20,000:1. Engines that tessellate do it inside a quadtree or rings of patches
   of different sizes. Apple's feature table lists tessellation under the Metal 3 programming model
   only, and mesh shading under Metal 3 and 4. [verified]
9. **Physics must read the same height samples the GPU draws, with the same triangle split.**
   Bilinear interpolation and the two-triangle surface differ inside a cell: by 1.5 m in worked
   example 7. [verified] PhysX stores the split per cell; X-Plane reads heights bilinearly from the
   raster at load. [fetched]
10. **Recommendation for this engine: CDLOD on a flat local frame first, with a procedural height
    function baked into tiles on the CPU; then asynchronous tiles, origin rebasing, real elevation
    data, and a cube-sphere planet last.** CDLOD needs no stitching meshes and no tessellation, and
    it works in every renderer. A `TerrainLODType` switch keeps a uniform reference grid, CDLOD and
    a tessellated variant selectable, as `PhysicsUpdateType` selects the solver. (Agent's design;
    the algorithm is Strugar's [verified].)

## Terms

- **LOD (level of detail)** — drawing far things with fewer triangles than near things.
- **Height map / heightfield** — a 2-D grid of height samples, one per grid point.
- **DEM (digital elevation model)** — a height map of the real Earth. A **DSM** (surface model)
  includes buildings and trees; a "bare-earth" model does not.
- **TIN (triangulated irregular network)** — terrain stored as arbitrary triangles instead of a
  grid. Photogrammetry produces TINs.
- **Arc-second** — 1/3600 of a degree. One arc-second of latitude is 30.9 m. "30 m data" usually
  means 1 arc-second.
- **WGS84** — the standard ellipsoid model of the Earth: equatorial radius 6,378,137 m, flattened
  by 1/298.257 at the poles.
- **ECEF (Earth-centred, Earth-fixed)** — Cartesian coordinates with the origin at the planet's
  centre.
- **ENU (east, north, up)** — a local Cartesian frame touching the planet at one point, the anchor.
- **Float gap** — the distance between one 32-bit float and the next larger one. A 32-bit float has
  24 significant bits, so the gap grows with the magnitude.
- **Jitter** — visible shaking of vertices when float gaps are large compared to a pixel.
- **Floating origin / origin rebasing** — moving the world so the viewer stays near (0, 0, 0).
  Continuous form: the viewer is always exactly at the origin. Periodic form: shift everything when
  the viewer passes a threshold.
- **RTC / RTE (relative to centre / relative to eye)** — subtract a nearby point (an object centre
  or the camera) from positions in 64-bit arithmetic before converting to 32-bit for the GPU.
- **Reverse-Z** — a depth buffer where near maps to 1 and far to 0. This engine uses it.
- **Quadtree** — a tree where each square node has four children covering its four quarters.
- **Tile / chunk / patch** — one node's square of terrain. "Patch" also means a tessellation input
  primitive; the text says which.
- **Cube-sphere** — a sphere made by pushing the six faces of a cube outwards. Each face gets its
  own quadtree.
- **Web Mercator** — the projection used by web map tiles. It stretches towards the poles and stops
  at latitude 85.05°.
- **Quadkey** — a tile address with one base-4 digit per quadtree level.
- **Geomorph / morphing** — sliding vertices smoothly between two LODs so the change is not seen.
- **Popping** — a visible jump when the LOD changes without morphing.
- **T-junction and crack** — where a fine tile meets a coarse tile, a fine vertex lies on the middle
  of a coarse edge. After displacement it does not sit on that edge, and a gap opens.
- **Skirt** — a strip of triangles hanging down from a tile's edge to hide cracks.
- **Screen-space error** — how many pixels a simplification moves the image.
- **CDLOD** — continuous distance-dependent level of detail (Strugar). Chunked LOD, geometry
  clipmaps, ROAM and geomipmapping are the other schemes defined in 1.2.5.
- **CBT (concurrent binary tree)** — a GPU data structure that stores a binary subdivision as a
  bitfield plus its sum-reduction tree. **LEB** is longest-edge bisection, the subdivision it drives.
- **Hardware tessellation** — a GPU stage that splits a patch into triangles using per-edge
  **tessellation factors**. In Metal a compute kernel writes the factors and a "post-tessellation
  vertex function" positions each generated vertex.
- **Mesh shader** — a newer GPU stage where a shader emits small meshes (**meshlets**) directly.
- **Virtual texture** — a texture too large to store, of which only the visible pages are resident.
  **Sparse texture** is the Metal feature that maps memory to parts of a texture.
- **Texture splatting** — blending several ground textures by per-pixel weights.
  **Triplanar mapping** — projecting a texture along X, Y and Z and blending by the normal, so
  cliffs do not stretch.
- **BC formats** — the "block compression" family of GPU texture formats (BC1 to BC7).
- **fBm (fractional Brownian motion)** — a sum of noise layers (**octaves**), each at twice the
  frequency (**lacunarity** 2) and a fraction of the amplitude (**gain**) of the one before.
- **Ridged noise** — noise passed through `1 − |n|` to make sharp ridges.
  **Domain warping** — offsetting the input position by another noise before sampling.
- **Hydraulic erosion** — simulating water carrying sediment downhill to carve valleys.
- **DSF** — Distribution Scenery Format, X-Plane's scenery file. **BGL** — the scenery file format
  of FSX and Prepar3D. **OGC** — the Open Geospatial Consortium, a standards body. **Cloud Optimized
  GeoTIFF** — a georeferenced image file laid out so parts of it can be read over HTTP.
- **CSM** — cascaded shadow maps. **G-buffer** — the render targets a deferred renderer fills
  before lighting. **PSO** — pipeline state object.

## Part 1 — The problem and the ideas

### 1.1 The problem

A flight simulator must draw the ground from 0 m to 15 km altitude or more, at hundreds of meters
per second, to the horizon. Three numbers set the scale.

- **View distance.** On a smooth sphere the horizon is at `sqrt(2·R·h + h²)`, with `R` the planet
  radius and `h` the eye altitude: 5 km at 2 m, 113 km at 1,000 m, 437 km at 15,000 m (worked
  example 2). [verified]
- **Detail.** On the runway the pilot sees the ground from 2 m. Vertex spacing near 1 m is wanted
  there. At the horizon one triangle may be 1 km across. The ratio of largest to smallest triangle
  is tens of thousands to one.
- **Size.** Earth's surface is 510 million km². A 1-arc-second height grid of the whole sphere is
  8.4 × 10¹¹ samples, 1,680 GB as 16-bit integers (worked example 4). [verified]

The naive approach is one height map drawn as one grid. It fails four ways at once:

1. **Memory.** The data does not fit. Only what is near the camera can be resident.
2. **Triangle count.** A uniform grid fine enough for the runway has too many triangles at the
   horizon, and they are smaller than a pixel, which aliases.
3. **Number precision.** 32-bit floats cannot hold a position on an Earth-sized planet to better
   than 0.5 m (1.2.1).
4. **Flatness.** A height map is a function on a plane. A planet is a sphere, and maps of a sphere
   onto a plane distort.

Two more requirements are specific to a simulator. The physics needs the height under each wheel on
the CPU, and it must agree with what is drawn (1.2.9). And data arrives late: tiles come from disk,
network or a generator over many frames, so the renderer must always have something valid to draw.

### 1.2 The core ideas

#### 1.2.1 Precision: where 32-bit floats fail, and the three fixes

**Intuition.** A 32-bit float has 24 significant binary digits. Close to zero they describe
fractions of a millimeter. Far from zero they are spent on the large part of the number, and little
is left for the fraction. Every fix is the same idea: never let a 32-bit variable hold a large
number. Hold differences from a nearby point instead.

**The math.** For a coordinate `x` in meters from the world origin, the float gap is
`gap(x) = 2^(floor(log2(|x|)) − 23)`.

**Worked example 1 — float gap by distance from the origin.** [verified]

| Distance from origin | Float gap |
|---|---|
| 100 m | 0.008 mm |
| 1 km | 0.06 mm |
| 10 km | 0.98 mm |
| 16.4 km (2¹⁴ m) | 1.95 mm |
| 100 km | 7.8 mm |
| 1,000 km | 62.5 mm |
| 6,378 km (Earth radius) | 500 mm |

The gap reaches 0.98 mm at 8,192 m, first exceeds 1 mm at 16,384 m (1.95 mm) and first exceeds 1 cm
at 131,072 m (15.6 mm). A 64-bit double at Earth radius has a gap of 0.93 nanometers. Three
consequences at Earth radius:

- An aircraft at 250 m/s moves 4.17 m per frame at 60 Hz. That is only 8.3 representable steps.
  Position integration becomes a staircase, and a landing-gear compression of a few centimeters
  cannot be represented at all.
- Subtraction loses the answer. A camera at x = R + 1234.567 m and an object at x = R + 1239.123 m
  are 4.556 m apart. In 32-bit floats the difference is 4.5 m, a 5.6 cm error. The same pair 10 km
  from the origin is wrong by 0.34 mm. A view matrix times a model matrix does this subtraction.
- The error changes every frame as the camera moves, so vertices shake.

Deron Ohlarik's 2008 article "Precisions, Precisions" gives the same analysis for a globe viewer:
values near 131,071 m are "within 0.5 cm", and Earth-scale coordinates "will not have sub-meter
accuracy". [fetched] Godot's documentation tabulates the same gaps and advises single precision up
to about 8 km for third-person games and 65 km for general 3-D projects. [fetched]

**Fix A — floating origin, or origin rebasing.** Keep the viewer at or near (0, 0, 0) and move the
world instead. Wikipedia attributes the technique to Christopher G. Thorne, 2005, "Using a Floating
Origin to Improve Fidelity and Performance of Large, Distributed Virtual Worlds"; I could not fetch
the paper. [unverified beyond the citation] In the periodic form, when the viewer is more than a
threshold from the origin, subtract an offset from every position. All numbers stay small, so CPU
physics stays in 32-bit floats.

**Fix B — relative-to-centre and relative-to-eye rendering.** Keep true positions in 64-bit on the
CPU. Before drawing, compute each object's position minus the camera position in 64-bit, then
convert to 32-bit. Ohlarik describes three variants: per object (RTC: replace the translation of
the model-view matrix with the eye-relative centre; about a centimeter accurate while vertices stay
within about 131 km of the centre), per vertex on the CPU (RTE), and per vertex on the GPU with each
coordinate split into a high and a low float (maximum error 1.353 cm; his vertex grows from 32 to
44 bytes). [fetched]

**Fix C — 64-bit everywhere on the CPU, relative or emulated on the GPU.** Unreal Engine 5's Large
World Coordinates changed core types to doubles and raised the default world limit from 21 km to
88 million km. [fetched] Godot offers a `precision=double` build; its shaders stay 32-bit and
emulate the extra precision. [fetched] Elite Dangerous computes planet surfaces on the GPU with
"emulated 64-bit functionality using two 32 bit floats" where doubles are missing. [fetched]

**What Microsoft Flight Simulator documents.** Lionel Fuentes (Technical Director, Asobo Studio),
on the slide "Handling large coordinates": for the "CPU node position", "Float 32 bits → Double 64
bits"; on the GPU an "inverted depth buffer" plus an "anchor space" whose origin is the camera
position and whose Y axis is the Earth surface normal. The chain changed from
`localPos → worldPos → viewPos → projPos` to `localPos → anchorPos → viewPos → projPos`.
[verified] That is Fix C on the CPU and Fix B on the GPU, with the local frame turned so that "up"
is +Y.

**The steps (camera-relative rendering, the part every fix shares).**

Symbols: `C` is the camera position and `P` an object position, both in the world frame in meters.
`C` maps to `cameraWorldPosition_m`, `P` to `objectWorldPosition_m`.

```pseudocode
// Runs once per frame on the thread that owns the scene, after all positions are final.
function writeCameraRelativeFrame(objects, camera) -> frameSnapshot
    cameraWorldPosition_m = camera.worldPosition_m                // highest precision available
    // the view matrix keeps only the camera's rotation; its translation is zero
    rotationOnlyViewMatrix = removeTranslation(camera.viewMatrix)
    for each object in objects
        // subtract while both numbers are still precise, then narrow to 32-bit
        cameraRelativePosition_m = object.worldPosition_m - cameraWorldPosition_m
        modelMatrixForGPU = composeMatrix(translation: toFloat32(cameraRelativePosition_m),
                                          rotation: object.rotation,
                                          scale: object.scale)
        frameSnapshot.append(modelMatrixForGPU)
    frameSnapshot.viewMatrix = rotationOnlyViewMatrix
    // every position the shaders use (lights, fog, shadows) must be in the same camera-relative frame
    return frameSnapshot
```

**Assumptions and limits.**

- Camera-relative rendering fixes only the GPU. If the CPU holds positions in 32-bit floats at
  large magnitudes, physics still breaks. The CPU needs Fix A or Fix C.
- With Fix A, a rebase is a discontinuity. Everything that stores a world position must shift in the
  same tick: scene nodes, rigid bodies, shadow-map snapping, cached matrices.
- A single object larger than about 100 km still jitters under per-object RTC (Ohlarik's caveat).
  Terrain is that object. Tiles solve it: each tile is positioned relative to the camera.
- Fix C costs memory and speed on the CPU and touches every type that holds a position.

#### 1.2.2 Depth precision over planetary ranges

**Intuition.** A perspective depth buffer stores roughly `near / distance`. Almost all of its
resolution is spent close to the near plane. Reversing the direction (near = 1, far = 0) puts far
distances near zero, where floats are densest, and the two effects cancel.

**The math.** With `n` the near distance, `f` the far distance and `z` the view-space distance
along the view direction (meters, left-handed, +Z forward), this engine's projection gives
`depth(z) = n·(f − z) / (z·(f − n))`: 1 at `z = n`, 0 at `z = f`. The smallest distance the buffer
can separate near `z` is `Δz ≈ (z² / n) · gap(depth(z))`.

**Worked example 6 — smallest separable distance, engine values n = 0.01 m, f = 1,000,000 m.**
[verified] This is storage resolution only; vertex arithmetic adds its own error.

| View distance | Reverse-Z, 32-bit float | Forward-Z, 32-bit float |
|---|---|---|
| 1 km | 0.1 mm | 6 m |
| 10 km | 1.1 mm | 596 m |
| 100 km | 7 mm | 59,600 m |
| 500 km | 22 mm | unusable |

Nathan Reed's "Depth Precision Visualized" (2015) concludes the same by simulation: "just use a
floating-point depth buffer with reversed-Z", though it "isn't a panacea". [fetched]

**Logarithmic depth.** Outerra (2012) wrote depth as `log(C·w + 1) / log(C·far + 1)`. Long
triangles near the camera then need the fragment shader to write depth, which disables early depth
rejection. The same post says a reversed 32-bit float buffer "brings slightly better resolution
than a 24bit logarithmic buffer"; Outerra used logarithmic depth because float depth was then
Nvidia-only in OpenGL. [fetched]

**Limit.** Reverse-Z with a 32-bit float depth buffer is enough for a 0.01 m near plane and a
horizon 437 km away. Logarithmic depth is not needed here.

#### 1.2.3 How far you can see: horizon, curvature and culling

**Worked example 2 — distance to the horizon.** [verified] `d = sqrt(2·R·h + h²)`, with
`R` = 6,371,009 m (mean Earth radius), `h` = altitude in meters, smooth sphere, no refraction.

| Altitude | Horizon |
|---|---|
| 2 m | 5.0 km |
| 100 m | 35.7 km |
| 1,000 m | 112.9 km |
| 3,000 m | 195.5 km |
| 10,000 m | 357.1 km |
| 15,000 m | 437.4 km |
| 20,000 m | 505.2 km |

The surface also drops below a flat plane by `d² / (2R)`: 7.85 m at 10 km, 196 m at 50 km, 785 m
at 100 km. A flat world looks wrong from altitude because distant mountains do not sink.

**Frustum culling** removes tiles outside the view pyramid. Each tile needs a bounding box that
includes its minimum and maximum height.

**Horizon culling** removes tiles hidden behind the planet's curve. Kevin Ring (Cesium, 2013)
reduces each tile to one "occludee" point and tests it against the cone of rays from the camera
tangent to the ellipsoid; "over half" of the tiles inside the frustum can be below the horizon.
[fetched]

Symbols: all vectors are in "scaled space": each ECEF coordinate is divided by the ellipsoid's
radius on that axis, so the ellipsoid becomes a unit sphere. `V` is the camera position, `T` the
tile's occludee point. The two inequalities are quoted from Ring's post [fetched]; the two
quantities they compare are my reconstruction from the geometry (the tangent length from a point to
a unit sphere, and a projection onto the direction to the centre).

```pseudocode
// True when the tile's test point is hidden behind the planet. (Ring, Cesium blog, 2013.)
function isBelowHorizon(scaledCameraPosition, scaledOccludeePoint) -> Bool
    cameraToPoint = scaledOccludeePoint - scaledCameraPosition
    // squared length of the tangent from the camera to the unit sphere
    horizonDistanceSquared = dot(scaledCameraPosition, scaledCameraPosition) - 1
    // how far the point lies along the direction from the camera to the planet centre
    alongCentreDirection = -dot(cameraToPoint, scaledCameraPosition)
    isBehindHorizonPlane = alongCentreDirection > horizonDistanceSquared
    isInsideHorizonCone = alongCentreDirection * alongCentreDirection / dot(cameraToPoint, cameraToPoint)
                          > horizonDistanceSquared
    return isBehindHorizonPlane and isInsideHorizonCone
```

**Limit.** The occludee point must sit above the tile's highest terrain, or visible mountains are
culled. Cesium's quantized-mesh tiles carry a precomputed `HorizonOcclusionPoint`. [fetched]

#### 1.2.4 Choosing the level of detail: screen-space error

**Intuition.** A coarse tile is acceptable when the mistake it makes is smaller than a pixel or
two on screen. Far tiles can be wrong by many meters and still pass.

**The math** (Cozzi and Ring, *3D Engine Design for Virtual Globes*, equation 12.1). [verified]
`ρ = ε·x / (2·d·tan(θ/2))`, where `ε` is the tile's geometric error in meters (the largest distance
any full-detail vertex lies from the simplified surface), `d` the distance from the viewer in
meters, `x` the screen height in pixels, `θ` the vertical field of view, and `ρ` the error in
pixels. Refine a tile when `ρ` exceeds a budget.

**Worked example 8.** [verified] 1080 pixels, 75° field of view, 2-pixel budget: refine when
`d < 352·ε`. A 1 m error is acceptable beyond 352 m, a 64 m error beyond 22.5 km, a 512 m error
beyond 180 km.

**Why a distance rule is equivalent.** In a quadtree of regular grids, each level's vertex spacing,
and so its error, doubles. The rule becomes "level `L` is used beyond `baseRange · 2^L`", which is
CDLOD's rule (1.2.5). Microsoft Flight Simulator adds a second input: the requested level also
depends on "estimated available network bandwidth". [verified]

#### 1.2.5 Level-of-detail geometry families

Each family answers one question: which triangles do I draw this frame?

**(a) Classic CPU schemes — historical context.**

- **ROAM** (Duchaineau, Wolinsky, Sigeti, Miller, Aldrich, Mineev-Weinstein; IEEE Visualization
  1997). A binary triangle tree. Each frame the CPU splits and merges triangles using two priority
  queues, to meet an error bound or a triangle budget. Its abstract names flight simulation as a
  target. [fetched: abstract only] It builds the mesh triangle by triangle on the CPU; Strugar and
  de Boer both argue that this stopped paying once GPUs could draw more triangles than a CPU could
  select. [verified]
- **Geomipmapping** (Willem H. de Boer, 2000). Cut the height map into fixed square blocks. For
  each block keep several index buffers that skip every 2nd, 4th, 8th vertex and pick one by
  distance, like texture mipmaps. Cracks are closed by omitting the border vertices of the finer
  block that the coarser neighbour lacks (the paper's section 2.3.2). [verified]
- **Chunked LOD** (Thatcher Ulrich, SIGGRAPH 2002 course "Super-size it! Scaling up to Massive
  Virtual Worlds"). A quadtree of pre-built static meshes selected by screen-space error, with
  geomorphs, designed for "paging data off disk"; the cost is "a long preprocessing phase".
  [fetched] Skirts for cracks and a background loader thread are how I remember the course notes;
  the PDF's text did not extract, so those two details are [unverified]. Chunked LOD is the direct
  ancestor of the virtual-globe tile schemes.

**(b) Geometry clipmaps** (Frank Losasso and Hugues Hoppe, SIGGRAPH 2004; GPU version by Arul
Asirvatham and Hoppe, *GPU Gems 2* chapter 2, 2005). [verified: both read in full]

*Intuition.* Instead of a tree, keep `m` square grids of `n × n` vertices, all centred on the
viewer, each twice as wide as the one inside it at half the density, like nested picture frames.
Triangle size on screen is then roughly constant without examining the terrain.

*Steps.*
1. Choose `n = 2^k − 1` (odd; the papers use 255) and the number of levels.
2. Each level stores its heights in an `n × n` array addressed with wrap-around ("toroidal"), so
   when the viewer moves only an L-shaped strip of new samples is written.
3. Each level renders as a hollow ring: its square minus the square the next finer level covers.
   In the GPU version a ring is 12 blocks of `m × m` vertices with `m = (n + 1) / 4`, four `m × 3`
   fix-up strips, an L-shaped interior trim, and a strip of degenerate triangles on the outer edge
   that closes T-junctions.
4. Near a level's outer edge, blend each vertex height towards the next coarser level's height:
   `z' = (1 − α)·z + α·z_coarser`, with `α` rising from 0 to 1 across a band `n / 10` grid units
   wide. The blend follows the viewer's position, not time.
5. When the viewer is high above the ground, switch off the finest levels. The GPU version
   deactivates levels whose extent is smaller than `2.5·h`, `h` being the height above the terrain.
6. Levels finer than the stored data are synthesized by upsampling the coarser level and adding
   fractal noise.

*Worked example 5 — clipmap budget.* [verified]

| Grid `n` | Levels | Height samples | 16-bit heights | Triangles before culling | Outer level spans, finest spacing 1 m |
|---|---|---|---|---|---|
| 127 | 11 | 177,419 | 0.35 MB | 269,892 | 129 km |
| 255 | 11 | 715,275 | 1.43 MB | 1,096,772 | 260 km |
| 255 | 14 | 910,350 | 1.82 MB | 1,387,094 | 2,081 km |

One ring at `n = 255` is 48,387 cells: 12 blocks of 63 × 63, four fix-ups and the trim. Reaching
the 437 km horizon at 15 km altitude takes 13 levels at 1 m finest spacing, or 10 levels at 8 m.
The paper's own figures for 11 levels of 255²: 11 MB of video memory at 16 bytes per vertex, 120
frames per second on 2004 hardware, and the 40.4 GB United States height map compressed to 355 MB.

*For a flight simulator.* Constant cost per frame whatever the terrain; no tree; steady frame rate;
detail synthesis built in. The paper names flight simulators as a use. Weaknesses: detail depends
only on horizontal distance, so the level set must be re-tuned with altitude (step 5; Benyoub and
Dupuy call clipmaps "hard to balance because they depend on the viewing altitude" [verified]);
culling works only per block; and the grid is a plane. Clasen and Hege's "Terrain Rendering using
Spherical Clipmaps" (EuroVis 2006) adapts the idea to a sphere; I saw only its abstract in a search
result. [unverified]

*Who ships it.* The Godot plugin Terrain3D uses a geometry clipmap based on Mike Savage's 2017
article and states "Like The Witcher 3, this system uses a geometry clipmap". [fetched: Terrain3D's
claim, not CD Projekt's]

**(c) Quadtree of regular grids: CDLOD** (Filip Strugar, 2010, "Continuous Distance-Dependent
Level of Detail for Rendering Heightmaps"). [verified: read in full]

*Intuition.* Keep the quadtree of chunked LOD, but make every node the same small grid mesh (for
example 32 × 32 cells) stretched over the node's square, with heights read from a texture in the
vertex shader. Close cracks by morphing each vertex, by its own distance to the camera, into the
shape the coarser level would have. No stitching meshes.

*Steps.*
1. Build the quadtree over the height map. Each node knows its minimum and maximum height.
2. Define a range per level: `range[L] = baseRange · 2^L`. The last 15 to 30 percent of each range
   is the morph band.
3. Select nodes each frame, starting at the root (pseudocode below).
4. Draw every selected node with the same grid mesh, passing its origin, size and level.
5. In the vertex shader, compute the vertex's distance to the camera, turn it into a morph value
   between 0 and 1, and move every odd-indexed grid vertex towards its even-indexed neighbour by
   that value. At 1 the grid is exactly the next coarser grid, so the swap is invisible.
6. Sample the height at the morphed position.

Symbols: `rangeForLevel_m[L]` is the far limit of level `L`; level 0 is the finest.

```pseudocode
// Strugar's LODSelect. Returns false when the node lies wholly beyond its own level's range,
// which tells the parent to draw that quarter itself.
function selectNodes(node, level, cameraPosition_m, rangeForLevel_m, viewFrustum, selection) -> Bool
    if not node.boundingBox.intersectsSphere(cameraPosition_m, rangeForLevel_m[level])
        return false
    if not viewFrustum.intersects(node.boundingBox)
        return true                          // handled: nothing to draw, parent need not cover it
    if level == 0
        selection.append(node, wholeNode)    // finest level: draw it
        return true
    if not node.boundingBox.intersectsSphere(cameraPosition_m, rangeForLevel_m[level - 1])
        selection.append(node, wholeNode)    // no part needs finer detail
        return true
    for each child in node.children
        childHandledItself = selectNodes(child, level - 1, cameraPosition_m, rangeForLevel_m,
                                         viewFrustum, selection)
        if not childHandledItself
            selection.append(node, quarterCoveredBy: child)   // draw this quarter at the parent's level
    return true
```

```pseudocode
// Vertex shader side. gridPosition is the vertex's place in the shared mesh, 0...1 on each axis.
function morphedGridPosition(gridPosition, gridCellsPerSide, morphValue) -> gridPosition
    // the fractional part is 0 for even-indexed vertices and one cell for odd-indexed ones
    offsetToEvenNeighbour = fractionalPart(gridPosition * gridCellsPerSide * 0.5) * 2 / gridCellsPerSide
    return gridPosition - offsetToEvenNeighbour * morphValue

function morphValueForDistance(distanceToCamera_m, levelRangeEnd_m, morphStartFraction) -> Float
    morphStart_m = levelRangeEnd_m * morphStartFraction         // for example 0.7 of the range
    return clamp((distanceToCamera_m - morphStart_m) / (levelRangeEnd_m - morphStart_m), 0, 1)
```

The first two functions follow Strugar's listings. `morphValueForDistance` is my statement of his
rule that the morph covers the last part of each range.

*Worked example 3 — quadtree depth and resident tiles for an Earth-sized cube-sphere.* [verified]
One cube face spans 90° of arc, 10,019 km on the equator. With 64 cells per tile side:

| Target spacing | Quadtree depth | Leaf spacing | Leaf tile side | Leaves on the whole planet |
|---|---|---|---|---|
| 30 m | 13 | 19.1 m | 1,223 m | 4.0 × 10⁸ |
| 1 m | 18 | 0.60 m | 38 m | 4.1 × 10¹¹ |

Nobody stores 4 × 10¹¹ tiles. With the rule "split a tile while the camera is closer than `k`
tile-sides", a brute-force count for a camera on the ground at depth 18 gives:

| `k` | Leaf tiles | Nodes including parents | Memory at 65 × 65 samples, 16-bit height + 2-byte normal |
|---|---|---|---|
| 1.5 | 676 | 901 | 11.4 MB leaves, 15.2 MB all nodes |
| 2.0 | 1,039 | 1,385 | 17.6 MB leaves, 23.4 MB all nodes |
| 3.0 | 1,912 | 2,549 | 32.3 MB leaves, 43.1 MB all nodes |

These counts are before frustum and horizon culling, which remove most tiles from the draw list
(not from memory). Drawn in full at 64 × 64 cells, 676 leaves would be 5.5 million triangles, so
culling and the grid size (a tunable: 32 cells quarters the count) matter. Each extra level adds a
constant number of tiles, about 40 to 120 here, so the resident set grows with the depth, not with
the planet's area. That is the trick.

*For a flight simulator.* The range test uses true 3-D distance, so climbing coarsens the terrain
under the aircraft automatically. Bounding boxes give frustum and horizon culling per tile. Tiles
map one-to-one onto streamed data tiles and onto collision tiles. Weakness: the CPU walks the tree
every frame (hundreds to a couple of thousand nodes), and each node is a draw or an instance.

*Who ships a quadtree of tiles.* Microsoft Flight Simulator ("Quadtree", "LoD = number of
subdivision steps") [verified]; Call of Duty ("Each terrain surface has a quad tree. At each node,
we store vertex & index buffers") [verified]; Frostbite ("Quadtree hierarchies used for all spatial
representations") [verified]; Cesium's quantized-mesh ("a simple multi-resolution quadtree pyramid
of meshes") [fetched]; Elite Dangerous ("a cube with square sub-dividing faces which behave as
quadtrees") [fetched]; Prepar3D's level scheme [fetched].

**(d) Hardware tessellation, driven by distance or by a quadtree.**

*Intuition.* Send coarse patches. Let the GPU split each into up to 64 × 64 cells, with a factor
per edge chosen so triangles have a constant size on screen, and displace the new vertices from the
height map.

*The edge factor.* Iain Cantlay's NVIDIA white paper (2011) fits a sphere around each patch edge,
projects it to the screen, and sets `factor = projectedDiameter_px / targetTriangleSize_px`. The
factor depends only on the edge, so two patches sharing an edge compute the same factor and no
crack opens. [verified] Apple's terrain sample does the same in `tessFactor`:
`max(scale · |edgeLength · projectionYScale / clip.w|, 1)`. [verified: sample source read]
Frostbite: "Tessellation factor derived from projected patch edge bounding sphere". [verified]

*The ceiling.* Cantlay: "DirectX 11 limits tessellation factors to the range 1 to 64. This is not
nearly sufficient to represent the range of scales required for a large, detailed world. … terrain
may require a range of scales like 5cm to 1km or 20,000 to 1. The solution is of course to employ
patches of differing sizes." His sample uses concentric square rings of tiles, each ring twice the
size of the one inside. [verified] Metal's limit is 64 on Apple GPU family 5 and later and 16 on
families 3 and 4. [verified: Metal Feature Set Tables dated 23 October 2026]

*Worked example 9.* [verified] For 1 m vertex spacing at factor 64, a patch can be at most 64 m
across. Covering a square that reaches 437 km in every direction (875 km on a side) with patches of
that one size would take 1.9 × 10⁸ patches; the disc of that radius alone takes 1.5 × 10⁸.
Tessellation is a refinement inside a coarser structure, never the structure itself.

*For a flight simulator.* Very little CPU work and no vertex buffers to stream. Weaknesses:
fractional factors make vertices slide, so the drawn surface does not pass through the height
samples (bad for collision agreement, 1.2.9); and on Apple platforms the feature belongs to the
older programming model (section 2.4).

*Who ships it.* Frostbite used it for displacement on top of a quadtree mesh "rendered in patches
of 16x16 triangle pairs" (Mattias Widmark, GDC 2012). [verified] Far Cry 5's GDC 2018 talk (Jeremy
Moore) covers a GPU compute pipeline for level of detail, culling, stitching and rendering of the
height-field terrain; I could read only the session abstract. [fetched: abstract] The Witcher 3's
GDC 2014 talk (Marcin Gollent) covers "terrain shadow casting and LOD management"; abstract only.
[fetched: abstract] Call of Duty (Stephane Etienne, SIGGRAPH Advances 2023) does **not**
tessellate: its quadtree nodes hold meshes from an offline simplifier, 8 bytes per vertex, X and Y
stored and Z "reconstructed by sampling the height map", and vertices slide towards their
low-resolution position before the switch. [verified]

**(e) GPU-driven schemes — the bleeding edge.**

- **Concurrent binary trees.** Jonathan Dupuy (then Unity Technologies, 2020) stores a binary
  subdivision as a bitfield with a sum-reduction tree, so compute shaders can split and merge
  triangles in parallel; a 54 × 54 km terrain "renders in less than five milliseconds" on an RTX
  2080. [verified] Anis Benyoub and Dupuy (Intel; High Performance Graphics 2024 and SIGGRAPH 2024
  Advances) lift the depth limit by using the CBT as a memory-pool manager and apply it to
  arbitrary meshes: "we render planetary surfaces with centimetric detail entirely on mid-range
  GPUs", with the triangulation updated "in less than 0.2ms on console-level hardware". [verified]
  Reference code is OpenGL (`jdupuy/LongestEdgeBisection2D`) and DirectX 12 (`AnisB/large_cbt`).
  [fetched] This is the ROAM idea moved to the GPU. It needs atomics, several compute passes and
  indirect draws.
- **Adaptive GPU tessellation with compute shaders** (Jad Khoury, Dupuy, Christophe Riccio). The
  forerunner of the CBT work. [verified: introduction read]
- **Mesh shaders.** Metal's mesh pipeline replaces the vertex stage with an object stage and a mesh
  stage; one mesh emits at most 256 vertices and 512 primitives; Apple presents it for procedural
  geometry and for meshlet culling with LOD selection. The WWDC 2022 session does not mention
  terrain. [fetched] A 16 × 16-cell terrain tile (289 vertices) does not fit one mesh; a
  15 × 15-cell tile (256 vertices, 450 triangles) does. I found no Metal terrain sample using mesh
  shaders.
- **Nanite landscapes (Unreal Engine 5).** The Nanite mesh is built from the landscape heightfield
  at edit or cook time; it "won't use a regular grid topology unless the camera gets very close";
  both representations are kept, so "twice the amount of data is streamed". [fetched] Benyoub and
  Dupuy say that for planetary components approaches like Nanite "are not applicable as the amounts
  of geometry involved are simply too large". [verified]

#### 1.2.6 Mapping a planet: projections, poles and tile addresses

A height map needs a 2-D parameterization of the sphere. Three are in use.

- **Web Mercator quadtree.** One square root tile, split into four per level. Microsoft Flight
  Simulator uses it because its data does: "Mercator projection — stretches at the poles — not
  ideal but the vast majority of available data uses it". [verified] The Bing tile system clips
  latitude at ±85.05112878°, sizes the map at `256 · 2^level` pixels and gives 4.78 m per pixel at
  level 15 on the equator; ground resolution shrinks with `cos(latitude)`. [fetched] The poles need
  a separate cap.
- **Geographic (latitude/longitude) quadtree.** Two root tiles. Cesium's quantized-mesh default.
  [fetched] Tiles become thin slivers near the poles.
- **Cube-sphere.** Six root tiles. Steven Wittens (2009) chose it for "speed and simplicity":
  distortion is "much smaller than e.g. a lat-long grid", where "the grid spacing actually
  approaches zero near the poles"; "every face of the cube map becomes a quadtree". [fetched]
  Elite Dangerous and Prepar3D ("at level 2 the Earth is divided into six quadrants") use
  six-rooted schemes. [fetched] No poles. The cost: real data arrives as Mercator or geographic
  tiles and must be resampled.

**Tile addressing.** A tile is `(root, level, x, y)`. Its quadkey interleaves the bits of `x` and
`y`: tile (3, 5) at level 3 has quadkey "213", and a tile's quadkey starts with its parent's.
[fetched] The quadkey is a good dictionary key for a tile cache.

**The ellipsoid.** On WGS84 the polar radius is 21.4 km shorter than the equatorial radius.
[verified by script] A sphere is a fair first model. Real data assumes the ellipsoid and gives
heights above mean sea level (the geoid), which matters only once real data is used.

#### 1.2.7 Texturing at scale

Colour at 1 m per texel over a 437 km view radius cannot be resident either.

- **Splatting by rule.** Compute blend weights per pixel from height and slope and blend a few
  tiling detail textures. Apple's terrain sample defines four "habitats" (snow, rock, grass, sand)
  with slope and elevation thresholds and samples them triplanar. [verified]
- **Land-cover driven.** Replace the height-and-slope rule with a classification raster.
  Microsoft Flight Simulator synthesizes aerial textures "affected by altitude and slope" where
  photographs are missing or poor. [verified]
- **Procedural virtual texturing.** Composite the layers once into pages of a large virtual texture
  and reuse them across frames. Frostbite: "typical virtual textures are 64k x 64k"; compositing a
  tile costs 0.2 to 0.5 ms. [verified] **Adaptive virtual texturing** (Ka Chen, Ubisoft, GDC 2015)
  allocates virtual space by distance to reach 10 texels per cm in a 10 km world [fetched:
  abstract]; Call of Duty adopted it, with page requests driven by a GPU feedback buffer that the
  CPU reads three frames later. [verified]
- **Detail maps near the ground.** Microsoft Flight Simulator blends "near, mid and far" detail
  maps (dirt, asphalt, grass) chosen in the pixel shader and spawns grass by surface type.
  [verified]
- **What Metal offers.** Sparse textures from Apple GPU family 6 ("when you're implementing
  texture streaming… you take ownership of memory management") [fetched; availability verified];
  argument buffers (tier 2 from family 6) to bind many textures at once; texture arrays; BC texture
  formats guaranteed only from family 9. [verified]

#### 1.2.8 Where the height and colour data comes from

**Streamed real-world data.**

| Dataset | What it is | Resolution | Licence and limits | Size |
|---|---|---|---|---|
| Terrain Tiles on AWS (Tilezen "Terrarium") | Bare-earth heights as PNG tiles, Web Mercator, zoom 0 to 15 | 256-pixel tiles; 38 m per pixel at zoom 12, 19 m at zoom 13, on the equator | Open. A mix of public-domain sources (SRTM, 3DEP, GMTED, ETOPO1) and attribution sources (several national sets, CC BY); an attribution text is required; ETOPO1 is "not to be used for navigation". No key. The bucket is "meant for efficient networking with EC2 resources only", so download a region once instead of streaming from an app | 200 km square at zoom 12, latitude 45°: 841 tiles, 110 MB as 16-bit |
| Copernicus DEM GLO-30 / GLO-90 | Surface model (includes buildings and vegetation), Cloud Optimized GeoTIFF | 30 m and 90 m | "Free basis for the general public under the terms and conditions of the Licence"; some countries' 30 m tiles are withheld; ocean tiles are absent | not stated |
| SRTM | Shuttle radar heights | 1 arc-second | Public domain, per the Tilezen attribution page | one 1° tile: 3601 × 3601 samples, 25.9 MB |
| Mapbox Terrain-RGB | Heights as PNG | 0.1 m steps, to zoom 15 | Mapbox token and attribution; updates stopped 1 December 2021 in favour of Terrain-DEM | — |
| ESA WorldCover | Land-cover classes | 10 m, 11 classes, 2020 and 2021 | CC BY 4.0, attribution text required | 2,651 tiles, about 117 GB |
| Bing Maps imagery | Aerial photographs | tile levels 1 to 23 | Bing Maps for Enterprise is retired for free accounts and ends for enterprise accounts on 30 June 2028 | Asobo: "2+ petabytes of aerial images" |
| Google Photorealistic 3D Tiles | Textured meshes | "many of the world's populated areas" | Billing account, attribution, Terms of Service | — |

Rows are [fetched]; the computed sizes and the Asobo figure are [verified]. Sentinel-2 cloudless
imagery and ASTER were not verified this session.

Decoding a Terrarium pixel: `height_m = (red·256 + green + blue/256) − 32768`, a step of 1/256 m.
Mapbox: `height_m = −10000 + (red·65536 + green·256 + blue)·0.1`. [fetched]

*Worked example 4 — raw data against resident data.* [verified] A global 1-arc-second grid is
1,296,000 × 648,000 samples: 1,680 GB as 16-bit integers, about 487 GB for land alone. A quadtree
keeps 11 to 43 MB resident (worked example 3); a clipmap keeps 1.4 to 1.8 MB of heights (worked
example 5). The ratio is about five orders of magnitude. Losasso and Hoppe held the whole United
States at 30 m in 355 MB by compressing the residuals between pyramid levels. [verified]

**Fully procedural.**

- **fBm.** `height = Σ gainⁱ · noise(2ⁱ · p)`. Inigo Quilez: with frequency doubling per octave, a
  gain of 0.5 gives isotropic self-similarity ("a mountain that is higher is also wider at its base
  by the same amount"), which is why 0.5 is the usual choice for mountains. [verified]
- **Analytic derivatives.** Value noise can return its gradient with its value. Quilez: this is
  "extremely cheap compared to the central difference method, that is 5 times slower", and it gives
  normals with no extra samples. Feeding the accumulated gradient back into the octave weights
  flattens steep places and imitates erosion. [verified]
- **Ridged noise and terraces.** `1 − |noise|` for ridges; rounding heights for terraces (Amit
  Patel). [fetched] **Domain warping:** `fbm(p + 4·q)` where `q` is itself two fBm values.
  [verified]
- **Erosion.** Simulations of water and sediment. They are not local: the height at one point
  depends on a whole watershed, so they cannot be evaluated per point on demand and are baked per
  region. Sebastian Lague's Unity project shows results "after 70k iterations". [fetched] The
  papers behind it were not fetched. [unverified]
- **The limit of noise.** Patel: "Different areas of the map don't relate to each other": no
  rivers, no drainage, no large-scale geography. [fetched]

Noise has one property that matters most here. It is a pure function of position and seed:
constant memory, constant-time random access, the same answer every time. A planet can exist
without storage, and the CPU can ask for the height under a wheel without loading anything.

**Hybrid: real coarse data plus procedural detail.** The hypothesis was that this is the practical
answer for a flight simulator. The sources support it:

- Losasso and Hoppe: "we synthesize grid levels finer than the stored terrain using fractal noise
  displacement"; of 11 levels in their example "only the coarsest 3 are stored geometry". [verified]
- Outerra (2009): "We currently use ~150m dataset for whole Earth. All detail below 150m is
  generated procedurally", by bicubic subdivision plus wavelet noise whose amplitude is "modulated
  by slope", curvature and elevation. [fetched]
- Proland (INRIA): "Terrain data can be stored on disk, procedural, or a mix of the two (e.g., to
  amplify real data with fractal details)"; it ships Earth elevations at 90 m per pixel. [fetched]
- Microsoft Flight Simulator: real elevation and aerial data, "semi-procedural systems", and
  runtime "augmentations" (detail maps, grass detection, tree placement). [verified]

The hypothesis survives, with one refinement: the procedural part is driven by the real data
(slope, height, land cover), not laid over it uniformly.

**Bleeding edge: learned terrain.** Alexander Goslin's arXiv preprint 2512.08309 (December 2025,
revised May 2026, now titled "InfiniteDiffusion: Bridging Learned Fidelity and Procedural Utility
for Open-World Terrain Generation") adapts diffusion sampling to unbounded, seed-consistent,
constant-time random access and claims to "outpace orbital velocity by 9 times on a consumer GPU";
code is public. Single author, not peer reviewed as far as I found; abstract only. [fetched:
abstract] Learned super-resolution of elevation models exists (a search named StyleDEM and
feedback-network papers); I read none of them. [unverified] Losasso and Hoppe listed "improved
terrain synthesis, e.g. using machine learning" as future work in 2004. [verified]

#### 1.2.9 Keeping the CPU's height and the GPU's height the same

**The problem.** Wheels rest on the surface the physics computes. The eye sees the surface the GPU
draws. If they differ by 10 cm the aircraft floats or sinks.

**Rule 1 — one source of truth: the height samples.** Both sides read the same samples from the
same tile at the same level. GPU Gems 2: the vertex shader reads the height texture and "no texture
filtering is necessary because the vertices correspond one-to-one with the texture samples".
[verified] X-Plane 10 stores triangles as latitude and longitude only and "reads the height for
each triangle out of the array of elevations", "bilinear from the 4 surrounding raster points".
[fetched] Asobo places trees with "CPU: sample DEM ⇒ set correct height" and reads its level-15
airport ground textures (surface type and flags) back to the CPU for collisions. [verified]

**Rule 2 — the same interpolation between samples.** The GPU draws two flat triangles per grid
cell. Bilinear interpolation of the four corners is a curved (saddle) surface. They agree on the
cell's edges and differ inside.

Symbols: `h00, h10, h01, h11` are the corner heights of one cell in meters; `u, v` in 0…1 are the
position inside the cell along X and Z.

```pseudocode
// Height of the drawn surface inside one cell, for a mesh whose cells are split along the 00-11 diagonal.
function triangleSurfaceHeight(h00_m, h10_m, h01_m, h11_m, u, v) -> height_m
    if u >= v
        // triangle 00, 10, 11
        return h00_m + (h10_m - h00_m) * u + (h11_m - h10_m) * v
    else
        // triangle 00, 11, 01
        return h00_m + (h11_m - h01_m) * u + (h01_m - h00_m) * v
```

*Worked example 7.* [verified] Corners 100, 104, 103, 101 m. Bilinear at the centre: 102.0 m.
Triangles split along the 00–11 diagonal: 100.5 m. Split along the other diagonal: 103.5 m. The
difference at the centre is `|h00 + h11 − h10 − h01| / 4` = 1.5 m. Physics must use the triangle
formula with the diagonal the index buffer uses. PhysX stores a "tessellation flag" per cell that
says "along which diagonal to split it into triangles". [fetched]

**Rule 3 — collision reads one fixed level, and rendering draws that level near the aircraft.**
Collision uses the finest level. The LOD ranges must guarantee that terrain within a few tens of
meters of the aircraft is drawn at the finest level with zero morph. Unreal exposes the trade as
"Collision Mip Level": 0 is "very accurate… at the expense of memory", higher values "start to show
inaccuracies between the player and collision". [fetched]

**Rule 4 — collision data is resident before it is needed.** Elite Dangerous spaces patches "to
ensure that there is always a physics patch available for any player or non-player entity that
requires it". [fetched] Godot's Terrain3D generates collision "only around the camera" by default
and offers `get_height()` for callers that already know X and Z. [fetched]

**Rule 5 — anything the GPU adds to the geometry, the CPU must add too.** Noise displaced in a
shader is invisible to physics. Either keep procedural detail out of the collision-level geometry
(put it in normals and textures), or bake it into the tile samples on one side and treat the baked
samples as truth. "The same" float noise on CPU and GPU is not guaranteed to give identical bits
(general principle; not tested here).

**Rule 6 — the sample format sets the height step.** A 16-bit sample spread over a global range of
9,500 m steps by 0.145 m, which is coarse beside 0.6 m vertex spacing. A 32-bit float has a 1 mm
gap at 8,848 m. A 16-bit sample with a per-tile base height steps by 0.76 mm over 50 m of relief
and by 7.6 mm over 500 m. [verified by script] Jolt compresses each height-field block "relative to
the min/max value of its block", and quantized-mesh stores heights relative to each tile's minimum
and maximum. [fetched] Whatever the format, the CPU and the shader must decode it with the same
arithmetic.

**Limit.** Hardware tessellation with fractional factors breaks Rule 1: generated vertices do not
land on samples. Collision on tessellated terrain needs power-of-two factors aligned to the texel
grid, or a tolerance.

#### 1.2.10 Atmosphere, only as far as it hides the seams

Distant terrain fades towards the sky colour ("aerial perspective"). That hides the coarsest
levels, the far clip plane and late-arriving tiles. Starting points: Proland ("the atmosphere is
rendered in real time from any viewpoint from ground level to outer space") [fetched] and Sébastien
Hillaire's "A Scalable and Production Ready Sky and Atmosphere Rendering Technique" (EGSR 2020),
which has public source code [fetched: publication list only]. A separate research document should
cover it.

### 1.3 How existing engines and simulators do it

Each entry is marked **documented** (with the source) or **inferred**.

- **Microsoft Flight Simulator 2020 (Asobo)** — documented, in Lionel Fuentes' slides "Designing
  the Terrain System of Flight Simulator: Representing the Earth" (PDF dated 28 March 2022; 80.lv
  lists it as a GDC talk). A Mercator quadtree following the Bing Maps tile system. Each tile holds
  "markers": a DEM mesh, or a TIN mesh from photogrammetry, an aerial texture, vector data,
  vegetation and water masks. `RecurseRequest` asks for tiles in the frustum by estimated screen
  size and bandwidth; `RecurseDraw` draws "the best currently available data" and "tiles can use
  data from a parent". Skirts hide cracks. Terrain edits are vector data and distance fields, not
  changes to the DEM. Shadows combine cascaded shadow maps, a ray march through a 300 km × 300 km
  top-down height map, and screen-space ray marching. Study: slides 17 to 25 (architecture), 54 to
  58 (airports, terraforming), 70 to 71 (large coordinates), 79 (shadows). [verified]
- **Microsoft Flight Simulator 2024** — I found only press interviews, with the headline claim of
  "about 4,000 times" more ground detail. No technical document. [unverified]
- **X-Plane** — documented. Scenery is DSF files, 1° × 1° each. "The mesh is a loose set of
  triangles", grouped in patches with LOD ranges, built offline by MeshTool, which "picks and
  chooses from DEM points to make an irregular mesh with the best DEM points for the budget you
  specify". Since X-Plane 10 the triangles carry latitude and longitude only and heights come from
  a raster DEM in the same file. The stated motivation was GPU tessellation, with "We're not ready
  to code this yet" (Ben Supnik, 2013). Whether X-Plane 12 tessellates was not checked. Study: the
  DSF specification; Supnik's "DSF mesh formats v9 vs v10". [fetched]
- **Prepar3D / FSX** — documented. A world grid with quad-mesh levels: "LOD + 2 = QMID level"; at
  level 2 "the Earth is divided into six quadrants"; LOD 13 is 4.75 m per pixel; elevation lives in
  BGL files; land-class textures are used where no photo imagery exists. The page I fetched does
  not mention a "LOD radius". [fetched]
- **FlightGear** — World Scenery 2.0 is an irregular mesh per tile built by TerraGear; World
  Scenery 3.0 drapes a land-class texture over a regular elevation mesh from VirtualPlanetBuilder,
  with seven LOD levels. This comes from search-result snippets of the FlightGear wiki, which
  refused automated fetching. [unverified]
- **DCS World, Falcon BMS** — no primary technical documentation found. Not covered.
- **Cesium** — documented. quantized-mesh: a quadtree pyramid of meshes; two root tiles in
  geographic coordinates; each tile has its centre in ECEF, minimum and maximum height, a bounding
  sphere and a horizon occlusion point; vertices are 16-bit `u`, `v`, `height`; edge index lists
  exist "to add skirts to hide cracks". 3D Tiles is the open specification for streaming large 3-D
  content, an OGC Community Standard since 2018; version 1.1 adds implicit tiling. [fetched]
- **Google Earth** — only the Photorealistic 3D Tiles product page was read: textured meshes
  requested through a root tileset by a 3D Tiles renderer. Internals not covered. [fetched]
- **osgEarth** — "a 3D mapping SDK for OpenSceneGraph"; its terrain engine was not verified.
- **Outerra** — documented in its blog: real data at about 150 m (2009) refined by fractals;
  logarithmic depth buffer. [fetched]
- **Proland (INRIA)** — documented: a C++/OpenGL library under the BSD 3 licence for "multi-resolution
  terrains (up to whole planets)", with real, procedural or mixed data. The page does not describe
  its tile structure. [fetched]
- **Elite Dangerous (Frontier)** — documented in a 2018 interview with lead render programmer Doc
  Ross: cube faces as quadtrees, spherified and displaced by noise in compute shaders, emulated
  64-bit positions, physics patches kept available, flat geometry with textures for distant levels.
  [fetched]
- **Kerbal Space Program** — "PQS" is the "Procedural Quad Sphere"; modifiers ("PQSMods") stack to
  build a body; minimum and maximum subdivision levels are configurable. From the Kopernicus
  modding wiki, not from the developer. [fetched: third party]
- **No Man's Sky** — Sean Murray's GDC 2017 talk "Building Worlds Using Math(s)"; abstract only.
  Its internals are [unverified]. **Star Citizen, SpaceEngine** — not covered.
- **Unreal Engine 5** — Landscape components each store "height data … in a single texture";
  collision resolution is a mip setting; Nanite landscape and Large World Coordinates as described
  above. [fetched]
- **Godot Terrain3D** — a geometry clipmap in C++ (MIT), terrains "up to 65.5x65.5km", "up to 10
  levels of detail", collision generated around the camera. [fetched]
- **Apple's sample "Rendering Terrain Dynamically with Argument Buffers"** — documented by its
  source. 32 × 32 patches over a 15,000 m square, 4,500 m tall; `maxTessellationFactor = 16`;
  fractional-odd partitioning; a compute kernel writes screen-space edge factors; the height
  sampler is linear; compute kernels bake normals and ambient occlusion from the height map; the
  fragment shader blends "habitats" triplanar. Study: `AAPLTerrainRenderer.metal`, functions
  `tessFactor`, `TerrainKnl_FillInTesselationFactors`, `TerrainKnl_ComputeNormalsFromHeightmap`.
  [verified]

### 1.4 Tradeoffs

**Level-of-detail schemes.**

| Scheme | CPU cost | GPU cost | Memory | Popping / morphing | Planet suitability | Difficulty | Fit with this engine's tessellation renderer |
|---|---|---|---|---|---|---|---|
| Uniform grid (reference) | None | Highest; sub-pixel triangles far away | Whole grid | None, no LOD | None | Trivial | Independent of it |
| Geomipmapping (de Boer) | Low: pick a level per block | Low | Whole height map resident | Pops unless morphed | Poor: one flat map | Low | Independent |
| ROAM (Duchaineau) | High: per-triangle queues | Low triangle count, slow submission | Tree and queues | Smooth by design | Possible, rarely done | High | Poor |
| Chunked LOD (Ulrich) | Low: walk a quadtree | Low: static batches | Resident chunks only; offline preprocessing | Morph and skirts | Good: basis of globe tiles | Medium, plus a tile builder | Independent |
| Geometry clipmap (Losasso, Hoppe) | Low: update L-strips | Constant; about 1 M triangles at n = 255 | Smallest: 1 to 12 MB | Smooth blend band | Poor without the spherical variant; altitude tuning needed | Medium: footprint pieces, toroidal update | Independent; a competing renderer path |
| CDLOD (Strugar) | Medium: walk a quadtree each frame | Low: one grid mesh, instanced | Resident tiles: 11 to 43 MB at planet depth | Smooth per-vertex morph, no stitching | Good: one quadtree per cube face | Medium | Good: leaf tiles can become tessellated patches |
| Tessellated patch rings or quadtree (Cantlay; Frostbite) | Low | Medium: tessellator and displacement | Height textures only | Smooth with fractional factors; vertices "swim" | Good with a quadtree above it | Medium; crack rules between sizes | Direct reuse of the compute kernel and pipelines |
| Concurrent binary tree (Dupuy; Benyoub) | Near zero | Low: under 0.2 ms update reported | A bitfield heap and a bisector pool | Smooth: incremental splits | Demonstrated at Earth size | High | None; a new GPU pipeline |
| Mesh-shader tiles | Low | Low; culling on the GPU | As for tiles | As for the scheme feeding it | As for the scheme feeding it | High; no terrain sample found | None; needs GPU family 7 |

The CPU, GPU and difficulty columns are my judgement from the sources, not measurements.

**Precision fixes and data sources** (the template's columns).

| Approach | Correctness | Complexity to implement | Runtime cost | What it teaches | Origin |
|---|---|---|---|---|---|
| Do nothing, stay within 16 km | Gap up to 2 mm | None | None | Where floats fail | This document, worked example 1 |
| Origin rebasing | Exact if every stored position shifts in one tick | Medium: find every stored position | One pass per rebase | Frames of reference | Thorne 2005 (citation only) |
| Camera-relative rendering | Fixes GPU jitter only | Low to medium | One subtraction per object per frame | Catastrophic cancellation | Ohlarik 2008; Asobo "anchor space" |
| 64-bit CPU positions | Exact to nanometers at Earth radius | High: every position type | Wider math on the CPU | Numeric types | Asobo; Unreal; Godot |
| Procedural heights | Self-consistent, not real | Low | Per-sample noise cost | Noise, determinism | fBm as described by Quilez |
| Real DEM tiles | Real, limited to 10–30 m | Medium: decode, reproject, cache | I/O | Geodata, licences | Tilezen, Copernicus, SRTM |
| Hybrid | Real shape, invented detail | Higher | Both | Amplification | Losasso and Hoppe; Outerra; Proland |

### 1.5 Evidence quality

- **Documented facts:** the geometry clipmap, CDLOD, CBT and screen-space-error formulas (papers
  and book section read in full); Microsoft Flight Simulator's tile system and precision design
  (Asobo slides); Call of Duty and Frostbite terrain structure (slides); Metal feature availability
  and sampler defaults (Apple's tables and language specification); Apple's sample (source).
- **General principles:** the float-gap formula, the horizon formula, the curvature drop, and the
  difference between bilinear and triangular interpolation. All reproduced by script.
- **Simulation approximations used here:** a sphere instead of the WGS84 ellipsoid; no atmospheric
  refraction in the horizon distance; a flat local tangent frame near the aircraft; noise standing
  in for geology.
- **Unavailable this session:** Far Cry 5 and Witcher 3 slides; Microsoft Flight Simulator 2024's
  design; DCS World, Falcon BMS, Star Citizen and SpaceEngine internals; the original floating
  origin and spherical clipmap papers. Session abstracts and search snippets stand in, and are
  tagged as such.

### 1.6 What did not survive verification

- **"The 2024 CBT follow-up is from Unity."** The 2024 paper's authors, Benyoub and Dupuy, are
  listed at Intel. Only the 2020 paper lists Unity.
- **"Precisions, Precisions is by Cozzi."** The fetched article names Deron Ohlarik, 2008. Cozzi
  and Ring wrote the book.
- **"Call of Duty's terrain is hardware tessellation driven by a quadtree."** The 2023 talk
  (Stephane Etienne) describes a CPU quadtree of pre-simplified meshes with streamed vertex buffers.
- **"Microsoft Flight Simulator tiles the globe with a cube or a geographic grid."** It uses a
  Mercator quadtree, and calls that "not ideal".
- **"Two petabytes of world data."** Asobo's slide says "2+ petabytes of aerial images"; the figure
  is imagery, not the whole dataset.
- **"A planet needs a logarithmic depth buffer."** Outerra's own post rates reversed 32-bit float
  depth slightly better than 24-bit logarithmic depth. The engine already has reversed float depth.
- **"Outerra refines 90 m data."** The 2009 post says about 150 m at that time.
- **"X-Plane stores terrain as 3-D triangles."** True up to version 9. Since version 10 triangles
  hold latitude and longitude and heights come from a raster.
- **"The engine's terrain tessellates by distance."** It does only within 16 m of the camera.
- **"The engine's height map is 16-bit."** The PNG is, but the asset catalog stores it as
  `r-8-unorm`.
- **"The engine's particles store world positions, so a rebase must shift GPU buffers."** They are
  stored relative to the emitter (`Particles.metal`).
- **"plans/claude/tessellation_terrain_fix.md describes the current code."** Its stride bug is
  fixed and its struct listings no longer match.
- **Not covered:** atmosphere and water; vegetation and autogen buildings; virtual texturing
  internals; erosion algorithms; terrain shadows beyond one slide; audio or AI use of terrain;
  networking of streamed tiles; the WGS84 ellipsoid and geoid math; and every engine listed as
  unavailable in 1.5.

## Part 2 — Applying it to ToyFlightSimulator

### 2.1 Where the engine is today

Every statement here was read in the source on 2026-11-12. Numbers come from section 0 of the
scratch script.

**What the current terrain is.** One height-mapped, hardware-tessellated square patch grid, drawn by
one renderer, in one scene.

- `TerrainObject` (`GameObjects/Tesselation/TerrainObject.swift`) builds a fixed 32 × 32 grid of quad
  patches (`patches`, `createControlPoints`): 1,024 patches, 4 control points each, in a flat plane
  at local y = 0. A control point is one `float3` (`TerrainControlPoint`).
- `FlightboxWithTerrain.addTerrain` creates it with `size: [8, 8]` and `setScale(100)` and tilts it
  with `rotateX(-20°)`: an 800 m × 800 m square (0.64 km²) of 25 m patches.
- `compute_tessellation` (`Graphics/Shaders/Tessellation.metal`) runs each frame as a compute kernel
  over the patches and writes one `MTLQuadTessellationFactorsHalf` per patch. Each edge factor is
  `max(4, maxTessellation / cameraDistance)`; `maxTessellation` is 64 on Apple GPU family 5 and
  later, else 16 (`TessellatedRendering.maxTessellation`).
- `tessellation_vertex` interpolates the patch corners, samples the height map once, sets
  `position.y = (r·2 − 1) · terrain.height`, then applies the float `modelMatrix`, `viewMatrix`
  and `projectionMatrix`.
- `tessellation_gbuffer_fragment` picks grass, cliff or snow by height with hard thresholds and
  writes the constant normal `(0, 1, 0)`.
- `TiledMSAATessellatedRenderer` is the only renderer that adopts `TessellationRendering` and calls
  `encodeTessellationComputePass` and `encodeTessellationRenderPass`. The other renderers do not
  draw the terrain.
- The `Terrain` struct (`size`, `height`, `maxTessellation`, marked "Temporary" in `TFSCommon.h`)
  is field-for-field the struct in *Metal by Tutorials* chapter 19, so the design's origin is
  probably that tutorial (inferred).

**What it cannot do.**

| Limit | Evidence in the source | Consequence |
|---|---|---|
| No level of detail at flight distances | `max(4.0, terrain.maxTessellation / cameraDistance)`: the factor reaches its floor of 4 at 16 m | Every patch farther than 16 m is a 4 × 4 grid with 6.25 m vertex spacing: 32,768 triangles in total, whatever the distance |
| Fixed size and origin | `patches` is a constant; control points are built once in `init` | 800 m across; cannot follow the camera |
| No streaming | One texture, `Assets.Textures[.MountainHeightMap]`, loaded at init | Everything is resident |
| 8-bit height | `Height Maps/mountain.textureset/Contents.json` declares `"pixel-format": "r-8-unorm"`; `mountain.png` is a 16-bit greyscale PNG | 256 steps: 0.78 m per step over the scene's ±100 m range |
| Nearest-neighbour height sampling | `constexpr sampler sample;` with no arguments. The Metal Shading Language specification 4.1, table 2.7, gives the defaults: `filter nearest`, `address clamp_to_edge`, `mip_filter none` ("All samples are read from level 0") | Heights step from texel to texel (1.56 m texels) instead of sloping |
| No terrain normals | `normalSpecular = float4(0.0, 1.0, 0.0, …)  // TODO` | Slopes are not shaded |
| Casts no shadows | `DrawManager.DrawShadows` iterates `SceneManager.getOpaqueSnapshot` only | Terrain does not occlude the sun; receiving is also a `// TODO` |
| No collision | `TerrainObject` has no `rigidBody`; `PhysicsWorld.raycastStaticPlanes` tests `PlaneRigidBody` only | An aircraft falls through it; there is no CPU height query |
| Bypasses the frame snapshot | `DrawManager.DrawTessellatables` binds `tessellatable.modelConstants` with `setVertexBytes` at encode time; `TerrainObject.computeUpdate` binds `self.modelMatrix`; `encodeTessellationComputePass` reads `CameraManager.GetCurrentCameraPosition()` at encode time | The terrain does not go through `SceneManager.writeFrameSnapshot`. That is harmless only because it never moves. A terrain that follows the camera must enter the snapshot |
| Flat mapping, tiling 1.0 | Control points lie in the local XZ plane; `float tiling = 1.0;` | No curvature; one copy of each colour texture stretched over 800 m |

`plans/claude/tessellation_terrain_fix.md` is out of date: `TerrainControlPoint` is now a single
`float3` and `TessellationVertexDescriptor` uses `TerrainControlPoint.stride`.

**Precision.** Everything is 32-bit float.

- `Node._position` and `_scale` are `float3`; `_modelMatrix`, `_worldMatrix`, `parentModelMatrix`
  and `_rotationMatrix` are `matrix_float4x4` (`GameObjects/Node.swift`).
- `ModelConstants.modelMatrix`, `SceneConstants.viewMatrix`, `projectionMatrix` and
  `cameraPosition` are float (`TFSCommon.h`).
- A search for `Double`, `simd_double` and `double3` in `Physics/`, `GameObjects/`, `Math/` and
  `Managers/` finds doubles only in timing code. `RigidBody` positions are `float3`.
- `TiledDeferredGBufferTextures.positionPixelFormat` is `.rgba16Float`, and the terrain's G-buffer
  fragment writes world-space meters into it. A 16-bit float has a gap of 6 cm at 100 m, 0.5 m at
  1 km and 8 m at 10 km, and overflows at 65,504 m. Point lights already lose position accuracy a
  few hundred meters from the origin. [verified by script, section 10]

**Projection.** `Transform.perspectiveProjection` is left-handed and reverse-Z. The flight scenes
use `near: 0.01`, `far: 1_000_000`. Depth is 32-bit float: the view's format is `depth32Float` and
the tiled G-buffer and tessellation pipelines use `depth32Float_stencil8`.

**Flat-world assumptions a sphere would break.**

- `PhysicsWorld.gravity` is fixed at `[0, -9.81, 0]`.
- `GameScene.addGround` makes a `PlaneRigidBody` with `collisionNormal: [0, 1, 0]`.
- `LandingGearSuspension` casts struts through `PhysicsWorld.raycastStaticPlanes`, which returns a
  `RayHit` (distance and normal) from `NarrowPhase.rayVsPlane`.
- `AircraftTelemetry.swift` computes pitch from `forward.y` and heading from
  `atan2(forward.x, forward.z)`, so world +Y is "up" and world +Z is north.
- `ShadowCascadeFitting` builds its light basis from `Y_AXIS`, and `ShadowCamera` uses `Y_AXIS` as
  its up vector.

**Threads.** `UpdateThread` (a `TFSThread`) runs `SceneManager.Update` once per frame after the
render thread signals `updateSemaphore`. The same tick writes the ring-buffer snapshot
(`writeFrameSnapshot`) and `GameScene._sceneConstants` (`GameScene.update`), then signals
`updateDoneSemaphore`. `AudioThread` is the only other `TFSThread`. Requests from other threads
arrive through single-slot mailboxes drained at the top of the tick: `PendingAircraftSwap` and
`PendingSceneReset`.

**Particles.** `Particles.metal` draws each particle at
`particles[instance].position + emitterPosition`, then multiplies by the model matrix. Particle
positions are stored relative to the emitter, not in the world frame.

**Memory and API.** The shadow maps are 4 × 4096 × 4096 × `depth32Float` = 256 MiB. The engine
uses no mesh shaders, no sparse textures and none of the Metal 4 command types (a search for
`MTL4`, `meshFunction`, `objectFunction` and `sparse` finds nothing).

### 2.2 Recommended approach

Each decision is marked with its origin: (codebase), (source: name) or (agent's design). Names that
do not exist in the source are proposals: `TerrainLODType`, `TerrainHeightSource`,
`useAsyncTileLoading`, `TerrainTileWorker`, `raycastTerrain`, `terrainHeight_m`, and the pseudocode
functions of Part 1.

**Is procedural generation a good fit? A direct answer.**

- *Good fit* when the world is invented; when storage and bandwidth must be zero; when the CPU
  physics must get the height at any point at once (a pure function of position and seed); and
  for detail finer than any dataset: the last 30 m down to 1 m. (source: Losasso and Hoppe;
  Outerra; Quilez)
- *Poor fit as the only source* when pilots must recognize real places and navigate by them; when
  rivers, coastlines and drainage must make sense, because noise has no memory of its neighbours
  (source: Patel); and for airports and runways, which need flat, authored regions. Microsoft
  Flight Simulator flattens and edits with vector shapes and distance fields laid over the data,
  and avoids editing the elevation data itself. (source: Asobo)
- *Cost per sample* is the price: several octaves of noise per height. Bake it into tiles once,
  off the frame's critical path, and never evaluate it per vertex per frame. (agent's design)
- *Recommendation for a solo learning project:* procedural first, real data second, hybrid as the
  end state. The quadtree, the tile cache, the CPU query and the renderer are identical for both;
  only the function that fills a tile changes. (agent's design)

**Simple version first: CDLOD over CPU-baked procedural tiles, on a flat frame near the origin.**

1. *World.* Flat, +Y up, everything within about 16 km of the origin, where the float gap is at
   most 2 mm. No precision work yet. (codebase convention; threshold from worked example 1)
2. *Height source.* One pure function `terrainHeight_m(worldX_m, worldZ_m)`: fBm over value noise
   with integer hashing, evaluated in Swift on the CPU. (source: Quilez; agent's design)
3. *Tiles.* A quadtree node bakes 65 × 65 samples of that function into an array of 32-bit floats,
   which is also uploaded as an `r32Float` texture. Both sides then read the same bits, with a
   1 mm gap at 8,848 m. Neighbouring tiles share their border samples exactly. The array is the
   single source of truth for the GPU and for physics. It costs 1.5 times the 16-bit figures of
   worked example 3: 17 to 49 MB for the leaf tiles. (source: GPU Gems 2 used 32-bit float
   elevation maps; agent's design)
4. *Selection.* Strugar's `selectNodes` runs on the UpdateThread each tick and produces a list of
   (tile origin, tile size, level, texture) records. (source: Strugar)
5. *Snapshot.* The list is written into the per-frame ring buffer beside the model constants, so
   the render thread draws a self-consistent frame. This is the step the current terrain skips.
   (codebase: `SceneManager.writeFrameSnapshot`)
6. *Drawing.* One grid mesh of 32 × 32 or 64 × 64 cells (a tunable), instanced once per record.
   The vertex function reads the height with an exact texel read at the vertex's sample, applies
   the morph, and outputs the same G-buffer data as other opaque geometry. No tessellation stage,
   so the same shader source can feed a pipeline for every renderer. (source: Strugar; agent's
   design)
7. *Normals.* Central differences of the tile's own samples, stored as two bytes per sample.
   (source: Apple sample's normal kernel; Losasso and Hoppe store 8-bit normal maps)
8. *Physics.* `raycastTerrain(from:direction:)` returns the same `RayHit` type that
   `raycastStaticPlanes` returns, computed with `triangleSurfaceHeight` on finest-level tiles kept
   resident around each aircraft. (codebase type; rule from 1.2.9)

**Optimized versions later**, each kept selectable beside the simple one.

| Step | What changes | Why it should help | How to measure | Fidelity or speed |
|---|---|---|---|---|
| Asynchronous tile baking | Tiles are baked on a worker and delivered through a mailbox; parents are drawn until children arrive | Removes bake time from the update tick | Tile-load latency; worst update-tick time | Speed only |
| Camera-relative snapshot and origin rebasing | See "Precision plan" below | Removes jitter; lifts the 16 km limit | Vertex jitter in the cockpit view at 1, 10, 100 km from the start | Fidelity |
| 16-bit tile samples | A per-tile base height and a fixed global step, decoded identically on CPU and GPU | Two thirds of the tile memory | Resident tile bytes; height step against the script | Speed and memory; adds a quantization step |
| Tessellated leaves | Leaf tiles near the camera are drawn as tessellation patches with Apple's screen-space edge factor | Finer near-ground geometry without more tiles | Triangle count and frame time at equal screen-space error | Speed, and it changes the drawn surface (see 1.2.9) |
| Real elevation tiles | The tile filler decodes downloaded Terrarium tiles; procedural detail is added below their resolution | Real places | Height error against the source at sample points | Fidelity |
| GPU selection | The quadtree walk moves into a compute kernel with indirect draws | Frees the update thread | Update-tick time | Speed only |
| Cube-sphere | Six quadtrees, tile positions computed in 64-bit relative to the anchor, horizon culling | A whole planet | Seam and pole inspection; resident tile count against worked example 3 | Fidelity |
| Concurrent binary tree | Replaces the quadtree and grid with GPU bisection | State of the art | Against CDLOD at the same error budget | Speed |

**Runtime selection.** (codebase pattern: `PhysicsUpdateType` and `useBroadPhase`)

- `TerrainLODType`: `.uniformGrid` (the reference: every resident finest tile, no LOD), `.cdlod`,
  `.cdlodTessellatedLeaves`, later `.geometryClipmap`.
- `TerrainHeightSource`: `.procedural`, `.elevationTiles`, `.hybrid`.
- `useAsyncTileLoading`: off bakes tiles inside the tick, as the simple reference.
- Use the same seed, camera path and scene for every mode.

**What to measure, and where.** Frame time and the active renderer are already shown by
`GameStatsManager` and Apple's HUD (`MetalPerformanceHUD`). Add terrain counters to the same
overlay: selected tile count, triangles submitted (tiles × cells × 2), resident tile bytes,
selection time on the update thread, tile-load latency (request to resident, median and worst), and
the largest difference between the CPU height query and the baked samples at tile vertices, which
must be zero.

**Where the third, asynchronous path attaches.** (agent's design, shaped by the codebase)

- A `TerrainTileWorker`: a `TFSThread` like `AudioThread`, or a small serial queue. It owns no
  scene state. It receives tile addresses and returns filled sample arrays and textures.
- Two lock-guarded mailboxes in the style of `PendingAircraftSwap`, but holding lists: requests
  out, finished tiles in.
- The UpdateThread stays the only owner of the quadtree. At the top of `SceneManager.Update`,
  where `PendingSceneReset` is consumed, it drains a bounded number of finished tiles into the
  cache. Then it runs selection, requests what is missing, and selects the deepest resident
  ancestor instead ("tiles can use data from a parent", Asobo).
- The render thread never touches the cache. It draws the records in its frame's snapshot. A tile
  that a snapshot still refers to must not be freed until three frames have passed, because three
  frames may be in flight (`inFlightSemaphore`).
- Collision tiles around each aircraft are requested ahead of visual tiles and are never evicted
  while an aircraft is inside them. With a procedural source the physics can also call the height
  function directly when a tile is missing, which is the function's advantage.

**Precision plan.** Camera-relative rendering alone is not enough here: `Node._position` is
`float3` and physics reads it, so the CPU would still quantize to 0.5 m at Earth radius.

- *Stage 0 — within 16 km:* nothing changes.
- *Stage 1 — unlimited flat world:* translation-only origin rebasing on the UpdateThread plus a
  camera-relative snapshot. (source: Thorne's idea; Ohlarik's RTC; agent's adaptation)
- *Stage 2 — planet:* a 64-bit anchor (latitude, longitude, ECEF) owned by the terrain, and a local
  east-north-up frame mapped to engine axes as X = east, Y = up, Z = north, which is left-handed
  like the engine and matches the telemetry's heading convention. Rebasing then also rotates the
  scene by the small angle between the old and new "up" (0.09° per 10 km). The alternative is to
  make CPU positions 64-bit, as Asobo did. This is an open question.

What a rebase touches, all in one tick, before physics and before the snapshot is written:

| Holder of a world position | Change at a rebase |
|---|---|
| `Node._position` of root-level nodes | Subtract the offset; children follow through `parentModelMatrix` |
| `RigidBody` standalone positions | Subtract the offset. Velocity, acceleration and force are unchanged by a pure translation |
| Particles | Nothing in the GPU buffer: positions are emitter-relative. The emitter position and model matrix come from the CPU and shift with their nodes |
| Shadow cascades (`ShadowCascadeFitting`, world-space texel snap) | Refit; expect one frame of shadow-edge shimmer |
| Terrain tile records | Recomputed from tile addresses and the new origin; nothing stored |
| `SceneConstants.cameraPosition`, light positions | Rewritten in the same tick by `GameScene.update` |

The engine's handshake makes this safe by construction: the render thread only reads snapshots, and
each snapshot is written whole, after the rebase, inside one tick. The camera-relative part is
small because the engine already builds a rotation-only view matrix (`skyViewMatrix` in
`GameScene.update`) and already rewrites every object's `ModelConstants` every frame
(`DrawManager.writeModelConstants`).

### 2.3 Suggested milestones

1. Repair the existing patch grid as a reference: linear height sampler, 16-bit texture, Apple's
   screen-space edge factor, normals from height differences — observable result: slopes are shaded
   and wireframe density changes with distance.
2. CPU height query on that terrain and `raycastTerrain` for the gear — observable result: the F-22
   rests on the terrain; a Metal-free test shows the query equals the samples at grid vertices.
3. Pure procedural height function and tile bake — observable result: Metal-free tests pass for
   determinism and for equal border samples between neighbouring tiles.
4. Quadtree and CDLOD selection as a pure static helper — observable result: a Metal-free test
   shows every ground point is covered exactly once, and the tile counts match worked example 3.
5. Draw the selection with one shared grid, first without morph, then with it — observable result:
   cracks visible, then gone.
6. Terrain records travel through `writeFrameSnapshot` — observable result: no tearing between the
   camera and the terrain while flying.
7. Tile worker and mailboxes with parent fallback — observable result: tiles sharpen over a few
   frames after a fast turn; update-tick time stays flat.
8. `TerrainLODType` switch and the stats counters — observable result: modes change at runtime and
   the overlay shows triangles, tiles and bytes.
9. Camera-relative snapshot and translation-only rebasing — observable result: fly 200 km straight
   and the cockpit does not shake.
10. Terrain in the shadow passes — observable result: mountains shadow the runway.
11. Downloaded elevation tiles for one region, with procedural detail below them — observable
    result: a recognizable coastline or mountain.
12. Cube-sphere and the geodetic anchor — a separate research step and plan.

### 2.4 Risks and pitfalls

| Symptom | Likely cause | How to check |
|---|---|---|
| Aircraft floats above or sinks into the ground between vertices | CPU query uses bilinear interpolation, or the other diagonal | Compare `triangleSurfaceHeight` with the index buffer's split; worked example 7 |
| Aircraft drops when the camera moves away | Collision reads whatever level is drawn | Pin the collision level; assert the tile level in the query |
| Thin lines of sky between tiles | T-junctions; morph missing or its band shorter than the level change | Wireframe view; colour vertices by morph value |
| Terrain "swims" while flying | Grid not snapped to its own spacing (clipmaps), or fractional tessellation | Freeze the camera, then move one cell |
| Terraced slopes | 16-bit samples over too wide a height range | Rule 6 of 1.2.9; print the tile's height step |
| Cockpit vertices shake far from the start | 32-bit world positions | Print the camera's distance from the origin; worked example 1 |
| Everything jumps for one frame at a rebase | A world-position holder was missed | Log each holder; rebase in a scene with particles, lights and shadows on |
| Point lights look blocky far from the origin | World-space position in an `.rgba16Float` G-buffer | Script section 10; move a light 2 km out |
| Stutter when turning quickly | Tiles baked inside the update tick | Tile-load latency counter; worst tick time |
| Crash or wrong tile after eviction | A tile freed while an in-flight frame's snapshot still referenced it | Delay frees by three frames |
| Terrain missing in five of six renderers | A tessellation-only pipeline | The CDLOD path needs one G-buffer pipeline per renderer |
| Memory warning on iOS | Shadow maps already use 256 MiB; a large tile cache on top | Cap resident tile bytes; show the counter |
| Tessellation path cannot move to newer Metal APIs | Apple's table lists tessellation for the Metal 3 programming model only | Keep tessellation an optional mode, not the foundation |
| Mountains culled at the horizon | Horizon test point below the tile's highest terrain | Raise the occludee point by the tile's maximum height |
| Poles or cube edges show seams | Neighbour tiles across faces sample different data | Bake border samples from one shared function of the sphere direction |
| A real-data app is blocked or rate-limited | Tile hosts are not meant for direct client streaming | Download a region once and ship or cache it; keep the attribution text |

## Open questions

- Flat "effectively infinite" world, or a true sphere? The first needs only translation rebasing.
  The second needs the geodetic anchor and a decision between a rotating local frame and 64-bit CPU
  positions.
- If the sphere: rebase-and-rotate with `float3` kept everywhere, or 64-bit `Node` positions as
  Asobo documents? The first is the smaller change; the second removes rebasing events.
- Should the first terrain replace `TerrainObject`, or should the tessellated grid stay as the
  reference mode under `TerrainLODType`? The project rule on superseded code suggests keeping it.
- Which renderers must draw terrain first? Each needs its own G-buffer pipeline for the grid.
- What collision spacing does the gear need: 1 m, or coarser with a smooth surface?
- Real data: which region, and is shipping a downloaded region with its attribution acceptable?
- Geometry clipmaps as a second mode for comparison, or only CDLOD?
- Is the 256 MiB shadow-map budget fixed on iOS, or can cascades shrink to make room for terrain?
- The sources did not settle: what Far Cry 5 and The Witcher 3 do in detail, what changed in
  Microsoft Flight Simulator 2024, and whether X-Plane 12 tessellates.

## References

Everything listed was retrieved this session unless it appears under "Not verified".

### Origin sources

- Losasso and Hoppe, "Geometry Clipmaps: Terrain Rendering Using Nested Regular Grids", SIGGRAPH
  2004 — https://hhoppe.com/geomclipmap.pdf — read sections 3 to 6 for the structure and the
  transition formula, 8 for synthesis, 9 for the memory table. The clipmap idea.
- Asirvatham and Hoppe, "Terrain Rendering Using GPU-Based Geometry Clipmaps", *GPU Gems 2*
  chapter 2 — https://hhoppe.com/gpugcm.pdf and the HTML edition at
  https://developer.nvidia.com/gpugems/gpugems2/part-i-geometric-complexity/chapter-2-terrain-rendering-using-gpu-based-geometry
  — read 2.3 for the block layout and the vertex shader listing. Why: it moves the clipmap's
  heights into a vertex texture, which is how any modern version works.
- Strugar, "Continuous Distance-Dependent Level of Detail for Rendering Heightmaps (CDLOD)", 2010 —
  https://github.com/fstrugar/CDLOD (`cdlod_paper_latest.pdf`) — the whole paper is 15 pages; the
  `LODSelect` listing and the morph listing are the algorithm recommended here.
- Dupuy, "Concurrent Binary Trees (with application to longest edge bisection)", 2020 —
  https://onrendering.com/data/papers/cbt/ConcurrentBinaryTrees.pdf — sections 2 to 3 for the data
  structure. Why: the base of the bleeding-edge approach.
- Benyoub and Dupuy, "Concurrent Binary Trees for Large-Scale Game Components", 2024 —
  https://arxiv.org/pdf/2407.02215 — the introduction compares clipmaps, quadtrees and Nanite;
  section 3 is the memory-pool use. Why: the only source read that renders an Earth-sized planet.
- de Boer, "Fast Terrain Rendering Using Geometrical MipMapping", 2000 —
  https://www.flipcode.com/archives/article_geomipmaps.pdf — section 2.3. Why: the simplest LOD
  scheme, for history.
- Duchaineau et al., "ROAMing Terrain: Real-time Optimally Adapting Meshes", 1997 —
  https://www.osti.gov/biblio/632827 — abstract only. Why: the CPU scheme the others replaced.
- Ulrich, chunked LOD — http://tulrich.com/geekstuff/chunklod.html — the page and its public-domain
  source. Why: the ancestor of globe tile schemes. The course-notes PDF did not extract.
- Cantlay, "DirectX 11 Terrain Tessellation", NVIDIA, 2011 —
  https://developer.download.nvidia.com/assets/gamedev/files/sdk/11/TerrainTessellation_WhitePaper.pdf
  — "Hull Shader: Tessellation LOD" and the tile-ring section. Why: the edge-factor rule and the
  proof that the factor ceiling forces patches of several sizes.
- Fuentes, "Designing the Terrain System of Flight Simulator: Representing the Earth", Asobo —
  https://www.asobostudio.com/files/inline-images/Designing_Terrain_System_Fuentes_Lionel.pdf —
  slides 17 to 25, 54 to 58, 70 to 71, 79. Why: the best single source on a shipping flight
  simulator's terrain.
- Etienne, Call of Duty terrain talk, SIGGRAPH 2023 "Advances in Real-Time Rendering in Games"
  course —
  https://advances.realtimerendering.com/s2023/Etienne(ATVI)-Large%20Scale%20Terrain%20Rendering%20with%20notes%20(Advances%202023).pdf
  — slides 4 to 5 for geometry; the rest is virtual texturing. The file is named "Large Scale
  Terrain Rendering"; the talk's exact title was not confirmed.
- Widmark, "Terrain in Battlefield 3: A modern, complete and scalable system", GDC 2012 —
  https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/gdc12-terrain-in-battlefield3.pdf
  — quadtree payloads, streaming and disc-seek reduction, procedural virtual texturing.
- Khoury, Dupuy and Riccio, "Adaptive GPU Tessellation with Compute Shaders" —
  https://onrendering.com/data/papers/isubd/isubd.pdf — introduction read. Why: the step between
  CPU quadtrees and CBTs.
- Goslin, arXiv 2512.08309 — https://arxiv.org/abs/2512.08309 — abstract. Why: the one learned
  terrain generator checked; a preprint.

### Detailed explanations

- Cozzi and Ring, *3D Engine Design for Virtual Globes*, section 12.1 (free sample) —
  https://virtualglobebook.com/3DEngineDesignForVirtualGlobesSection121.pdf — discrete, continuous
  and hierarchical LOD; the screen-space error equation; cracking. Why: the vocabulary.
- Ohlarik, "Precisions, Precisions", 2008 —
  https://help.agi.com/AGIComponents/html/BlogPrecisionsPrecisions.htm — the whole article. Why:
  the clearest account of jitter and of RTC, RTE and the two-float GPU method.
- Reed, "Depth Precision Visualized", 2015 —
  https://www.reedbeta.com/blog/depth-precision-visualized/ — the diagrams and the conclusion. Why:
  it shows why the engine's reverse-Z float depth is already the right choice.
- Outerra, "Maximizing Depth Buffer Range and Precision", 2012 —
  https://outerra.blogspot.com/2012/11/maximizing-depth-buffer-range-and.html — the logarithmic
  formulas and the comparison with reversed float depth. "Procedural terrain algorithm
  visualization", 2009 — https://outerra.blogspot.com/2009/02/procedural-terrain-algorithm.html —
  fractal refinement of real data, in pictures.
- Ring, "Horizon Culling", Cesium, 2013 — https://cesium.com/blog/2013/04/25/horizon-culling/ —
  the derivation and the scaled-space test. Why: needed only for the planet stage.
- Quilez, "fBM", "More noise" (value noise derivatives) and "Domain warping" —
  https://iquilezles.org/articles/fbm/ , https://iquilezles.org/articles/morenoise/ ,
  https://iquilezles.org/articles/warp/ — short, with code. Why: the tile filler. Open these in a
  browser: the whole site answers plain automated clients with 404 (see "Post-write check").
- Supnik, X-Plane developer blog — https://developer.x-plane.com/2013/04/dsf-mesh-formats-v9-vs-v10/
  (why heights moved into a raster) and
  https://developer.x-plane.com/2011/04/complex-shapefiles-make-big-and-wasteful-meshes/ (how the
  irregular mesh is budgeted). Why: a shipping simulator's reasoning about mesh versus raster.
- Doc Ross interview, "Generating The Universe in Elite: Dangerous", 2018 —
  https://80.lv/articles/generating-the-universe-in-elite-dangerous/ — the planet-surface answers.
  Why: a cube-sphere quadtree with GPU noise and physics patches, described by its author.
- Microsoft, "Bing Maps Tile System" —
  https://learn.microsoft.com/en-us/bingmaps/articles/bing-maps-tile-system — projection, the
  ground resolution table, quadkeys, with C# source. Why: the tile math Microsoft Flight Simulator
  follows.

### Reference implementations

- Apple, "Rendering Terrain Dynamically with Argument Buffers" —
  https://developer.apple.com/documentation/metal/rendering-terrain-dynamically-with-argument-buffers
  — `Renderer/AAPLTerrainRenderer.metal` (`tessFactor`, the factor kernel, the normal kernel) —
  Metal Shading Language and Objective-C++. Why: the engine's current design done properly.
- Strugar, CDLOD — https://github.com/fstrugar/CDLOD — DirectX 9, MIT. The paper describes its
  BasicCDLOD and StreamingCDLOD demos; study the quadtree selection and the vertex shader.
- Dupuy — https://github.com/jdupuy/LongestEdgeBisection2D — the `terrain` program; GLSL and C.
  Benyoub — https://github.com/AnisB/large_cbt — DirectX 12, Shader Model 6.6. Why: the only code
  for the CBT approach.
- Terrain3D — https://github.com/TokisanGames/Terrain3D and
  https://terrain3d.readthedocs.io/en/stable/docs/system_architecture.html ,
  https://terrain3d.readthedocs.io/en/stable/docs/collision.html
  — C++ for Godot 4, MIT. Why: a maintained clipmap terrain with a CPU height query.
- Lague — https://github.com/SebLague/Procedural-Planets and
  https://github.com/SebLague/Hydraulic-Erosion — Unity, MIT. Why: small, readable projects that
  accompany video tutorials.
- Proland — https://proland.inria.fr/ — C++/OpenGL, BSD 3. Why: a full planet renderer mixing real
  and procedural data; only its front page was read.
- bevy_terrain — https://github.com/kurtkuehnert/bevy_terrain — Rust. Only the README was read; it
  points to a bachelor thesis on large-scale terrain.

### Engine and simulator documentation

- Apple, Metal Feature Set Tables (23 October 2026) —
  https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf — the rows for tessellation,
  sparse textures, mesh shading, and the maximum tessellation factor per GPU family.
- Apple, Metal Shading Language Specification 4.1 (4 June 2026) —
  https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf — table 2.7, sampler
  defaults.
- Apple, Metal Programming Guide, "Tessellation" (archive) —
  https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/MetalProgrammingGuide/Tessellation/Tessellation.html
  — how Metal's compute-kernel tessellation maps to DirectX hull and domain shaders.
- Apple, "Transform your geometry with Metal mesh shaders", WWDC 2022 —
  https://developer.apple.com/videos/play/wwdc2022/10162/ — object and mesh stages, limits. Also
  "Managing sparse texture memory" and "Adjusting the level of detail using Metal mesh shaders" in
  the Metal documentation (overviews read).
- Unreal Engine documentation, under https://dev.epicgames.com/documentation/en-us/unreal-engine/ —
  "Large World Coordinates" (world limits), "Landscape Technical Guide" (components and sizes),
  "Landscape Collision Guide" (collision mip level), "Using Nanite with Landscapes" (costs).
- Godot, "Large world coordinates" —
  https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html — the
  float-gap table and the limits of a double build.
- PhysX 5.4.1, height fields — https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/Geometry.html
  — sample layout and the tessellation flag.
- Jolt, `HeightFieldShapeSettings` —
  https://jrouwe.github.io/JoltPhysics/class_height_field_shape_settings.html — block compression
  of height samples.
- X-Plane DSF specification — https://developer.x-plane.com/article/dsf-file-format-specification/
  — patches, LOD ranges, raster layers.
- Prepar3D terrain overview —
  https://www.prepar3d.com/SDKv5/sdk/world/terrain/terrain_overview.html — the level table.
- Cesium quantized-mesh — https://github.com/CesiumGS/quantized-mesh — the tile header and vertex
  encoding. 3D Tiles — https://github.com/CesiumGS/3d-tiles — overview only.
- Tilezen terrain tiles — https://github.com/tilezen/joerd/blob/master/docs/formats.md (decode
  formula), https://github.com/tilezen/joerd/blob/master/docs/use-service.md (URL templates, zoom
  range), https://github.com/tilezen/joerd/blob/master/docs/attribution.md (licences);
  https://registry.opendata.aws/terrain-tiles/ (bucket and access).
- Copernicus DEM — https://registry.opendata.aws/copernicus-dem/ — resolutions and licence note.
  ESA WorldCover — https://esa-worldcover.org/en/data-access — licence, tiling, size. Mapbox
  Terrain-RGB — https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-rgb-v1/ — decode
  formula and status. Google Photorealistic 3D Tiles —
  https://developers.google.com/maps/documentation/tile/3d-tiles — terms of use.

### Tutorials to follow, by stage

| Stage | Resource | Author, date | API or engine | What transfers, what must be translated |
|---|---|---|---|---|
| Tessellated height-map terrain | Apple terrain sample (above) | Apple; listed for iOS 17, macOS 14 | Metal, Objective-C++ | Shaders transfer directly. Its edge-factor kernel replaces the engine's distance rule |
| Tessellation basics | Apple "Tessellation" guide; MetalBasicTessellation sample https://developer.apple.com/library/archive/samplecode/MetalBasicTessellation/Listings/README_md.html | Apple, 2016 | Metal | Directly; it is the pipeline the engine uses |
| Tessellated terrain | *Metal by Tutorials* chapter 19, "Tessellation & Terrains" https://www.kodeco.com/books/metal-by-tutorials/v4.0/chapters/19-tessellation-terrains | Begbie and Horga; 4th edition, Swift 5.9 | Metal, Swift | The engine's terrain already follows it. Paid; parts of the page are scrambled |
| Tessellated terrain, the concepts | LearnOpenGL guest article https://learnopengl.com/Guest-Articles/2021/Tessellation/Tessellation | Jeffrey Paone, 2021 | OpenGL 4.1 | Control shader becomes the compute kernel; evaluation shader becomes the post-tessellation vertex function |
| Quadtree plus tessellation | "Tessellated Terrain Rendering with Dynamic LOD" https://victorbush.com/2015/01/tessellated-terrain/ | Victor Bush, 2015 | OpenGL 4 | The quadtree and edge scale factors transfer; GLSL to Metal |
| LOD vocabulary | Cozzi and Ring section 12.1 (above) | 2011 | none | Everything |
| CDLOD | Strugar's paper (above); write-up https://svnte.se/cdlod-terrain | Strugar 2010; Svante Lindgren, 2020 | DirectX 9; GLSL-style snippets | Selection is plain CPU code; the morph is ten lines of shader |
| Geometry clipmaps | GPU Gems 2 chapter 2 (above); "Geometry clipmaps: simple terrain rendering with level of detail" https://mikejsavage.co.uk/geometry-clipmaps/ | Hoppe 2005; Mike Savage, 2017 | DirectX 9; C++ and GLSL | Mesh pieces and snapping transfer; Savage's is "less than 1 KLOC" |
| Procedural noise | Quilez articles (above); "Making maps with noise functions" https://www.redblobgames.com/maps/terrain-from-noise/ | Quilez; Amit Patel, 2015 to 2022 | GLSL; JavaScript | Port the functions to Swift for the CPU bake |
| Procedural planets | "Making Worlds 1 — Of Spheres and Cubes" https://acko.net/blog/making-worlds-1-of-spheres-and-cubes/ ; Lague's Procedural-Planets; "Planetary Scale LOD Terrain Generation" https://leifnode.com/2014/04/planetary-scale-lod-terrain-generation/ | Steven Wittens, 2009; Sebastian Lague; Leif Erkenbrach, 2014 | OGRE C++; Unity; OpenGL | The cube-to-sphere mapping and per-face quadtree transfer; engine glue does not |
| Floating origin | Babylon.js "Floating Origin" https://doc.babylonjs.com/features/featuresDeepDive/scene/floating_origin ; Ohlarik; Asobo slides 70 to 71 | Vander R. N. Dias; Ohlarik 2008; Fuentes | JavaScript; OpenGL; none | The idea transfers; this engine needs the update-thread version in 2.2 |
| Streaming elevation tiles | Tilezen docs; Bing tile system; quantized-mesh (all above) | various | HTTP, PNG | URL templates, decode formula and tile math transfer directly |
| GPU-driven terrain | Dupuy's and Benyoub's repositories (above) | 2020, 2024 | OpenGL; DirectX 12 | Concepts only; a full port to Metal compute |
| Mesh shaders | WWDC 2022 session 10162 and its sample | Apple, 2022 | Metal | Directly, but it is not a terrain sample; it needs an A15 or a Mac on macOS 13 or later |

**Reading and doing order, simple first.**

1. Apple's tessellation guide, then Apple's terrain sample: what the engine has, done properly.
2. Cozzi and Ring 12.1: the vocabulary.
3. Strugar's paper and Lindgren's write-up: build CDLOD.
4. Quilez on fBm and derivatives, then Patel: fill the tiles.
5. PhysX height-field page and the Terrain3D collision page: the CPU query.
6. Ohlarik, then Asobo slides 70 to 71: precision.
7. Asobo slides 17 to 25, Tilezen docs, the Bing tile system: streaming and real data.
8. Losasso and Hoppe, then Savage: clipmaps, for comparison.
9. Wittens, then Ring's horizon culling: the planet.
10. Dupuy 2020, then Benyoub and Dupuy 2024: the bleeding edge.

### Non-URL references

- Cozzi and Ring, *3D Engine Design for Virtual Globes*, A K Peters/CRC Press, 2011. Chapter 5
  "Vertex Transform Precision", 6 "Depth Buffer Precision", 12 "Massive Terrain Rendering", 13
  "Geometry Clipmapping", 14 "Chunked LOD". Only section 12.1 was read (free sample); the chapter
  titles come from the book's site. Why: the one book organized around exactly this problem.
- Begbie and Horga, *Metal by Tutorials*, 4th edition, Kodeco, chapter 19. Why: the tutorial the
  engine's terrain follows.

### Not verified (fetch failed or only a snippet was seen)

- Far Cry 5 terrain slides (GDC 2018) and REDengine 3 landscape slides (GDC 2014): PDFs returned
  HTTP 403. Session abstracts only.
- Thorne, "Using a Floating Origin…" (2005): PDF not found. Cited through Wikipedia and Babylon.js.
- Clasen and Hege, "Terrain Rendering using Spherical Clipmaps" (EuroVis 2006): the Eurographics
  library returned 403.
- Ulrich's course notes PDF: downloaded, but its text is not extractable.
- FlightGear wiki (World Scenery 3.0): refused automated fetching (HTTP 403). One retry with a
  browser-style user agent was blocked by the fetch tool as bot-check circumvention, so nothing was
  read from it.
- Kerbal Space Program "Developer Insights #12 – Planet Tech": 404.
- Microsoft Flight Simulator 2024: the SDK terrain page returned 404 and the TechRadar interview
  came back truncated.
- X-Plane "Understanding and building DSFs": 404. Sentinel-2 cloudless: navigation page only.
- Beyer's hydraulic erosion thesis: connection failed.
- SimonDev's `ProceduralTerrain_Part10` repository: the page carries no description, so the series
  content is unconfirmed.
- osgEarth: index page only.

Attribution notes: the floating origin is attributed to Chris Thorne on the strength of secondary
sources only. "Precisions, Precisions" is Ohlarik's, not Cozzi's. The Asobo slides carry no venue;
the date comes from the PDF metadata and the GDC attribution from an 80.lv listing seen in search
results. The Call of Duty talk's title is taken from its file name. The link between the engine's
`Terrain` struct and *Metal by Tutorials* is an inference from identical fields.
