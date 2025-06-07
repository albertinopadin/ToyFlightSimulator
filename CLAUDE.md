# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

### macOS
```bash
# Build Debug configuration
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Build Release configuration
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### iOS
```bash
# Build for iOS Simulator
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```

### Running the Application
After building, the application can be run through Xcode or by executing the built product directly:
```bash
# macOS (after Debug build)
./build/Debug/ToyFlightSimulator\ macOS.app/Contents/MacOS/ToyFlightSimulator\ macOS
```

## Architecture Overview

### Rendering Pipeline
The project implements multiple advanced rendering techniques, each with its own pipeline:

1. **Order Independent Transparency (OIT)** - Uses image blocks for proper transparency rendering
2. **Single Pass Deferred Lighting** - GBuffer pass followed by lighting calculation with shadow mapping
3. **Tiled Deferred Rendering** - Divides screen into tiles for efficient light culling
4. **Forward Plus Tile Shading** - Modern forward rendering with light culling
5. **Tiled MSAA with Tessellation** - Anti-aliasing with terrain tessellation support

Renderer selection is done through `RendererType` enum and can be changed at runtime via the menu.

### Scene Graph Architecture
- **Node**: Base class providing transform hierarchy (position, rotation, scale)
- **GameObject**: Extends Node with rendering capabilities (mesh, material, textures)
- **Scene**: Contains root nodes and manages the scene graph
- All transforms are hierarchical - child transforms are relative to parent

### Resource Management
- **Texture Caching**: `TextureLoader` implements a singleton cache to prevent duplicate texture loading
- **Model Loading**: Supports OBJ (with MTL), USDZ formats through ModelIO
- **Mesh Library**: Pre-built meshes (sphere, cube, quad) are cached in `MeshLibrary`

### Physics Integration
The physics system (`PhysicsWorld`) runs independently and updates game objects:
- Supports Euler and Verlet integration
- Collision detection and response using Hecker's method
- Physics entities must implement `PhysicsEntity` protocol

### Threading Model
- **Main Thread**: Rendering and UI updates
- **Update Thread**: Game logic and physics updates (60 Hz)
- **Audio Thread**: Background music playback
- Thread synchronization uses custom `TFSLock` (wrapper around os_unfair_lock)

### Input Handling
Platform-specific input is abstracted:
- **macOS**: Keyboard, Mouse, GameController, HOTAS support
- **iOS**: Touch controls with virtual joystick/throttle
- Input state is centralized in `InputManager` singleton

## Key Development Patterns

### Adding New Game Objects
1. Extend `GameObject` or appropriate base class
2. Override `doUpdate()` for per-frame logic
3. Implement custom vertex/fragment functions if needed
4. Add to scene in appropriate `Scene` subclass

### Adding New Shaders
1. Add Metal shader functions to appropriate .metal file
2. Create pipeline state in relevant pipeline library
3. Update renderer to use new pipeline for specific objects

### Performance Considerations
- Use instanced rendering for multiple identical objects
- Batch draw calls by material/texture
- Update only changed uniforms
- Use compute shaders for parallel operations (particle systems)

## Testing Specific Functionality

### Test a Single Renderer
```swift
// In GameViewController, modify renderer initialization:
renderer = SinglePassDeferredLightingRenderer()
```

### Debug Camera Controls
- Press 'C' to toggle between attached and debug camera
- Debug camera: WASD + mouse for free movement
- Attached camera: Follows selected aircraft

### Performance Profiling
- Use Xcode's GPU Frame Capture for detailed GPU analysis
- Monitor FPS counter (displayed in top-left)
- Check memory usage in Xcode's Debug navigator