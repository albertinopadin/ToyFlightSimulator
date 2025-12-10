# ToyFlightSimulator - Project Structure

## Directory Layout

```
ToyFlightSimulator/
├── ToyFlightSimulator Shared/     # Cross-platform shared code
│   ├── Assets/                    # Models, textures, materials
│   │   ├── Libraries/             # Mesh, Model, Texture libraries
│   │   └── Assets.xcassets/       # Asset catalog (textures, icons)
│   ├── Audio/                     # Audio system
│   ├── Core/                      # Engine fundamentals
│   │   ├── Input/                 # Keyboard, Mouse, Joystick, HOTAS
│   │   ├── Resources/             # Runtime resources (models, audio files)
│   │   ├── Threads/               # Threading infrastructure
│   │   └── Types/                 # Core types (GameTime, MetalTypes)
│   ├── Display/                   # Renderers and view management
│   │   └── Protocols/             # Rendering protocols
│   ├── GameObjects/               # Game entities
│   │   ├── Cameras/               # Camera types
│   │   ├── Particles/             # Particle emitters
│   │   └── Tesselation/           # Terrain tessellation
│   ├── Graphics/                  # Metal graphics infrastructure
│   │   ├── Libraries/             # Pipeline states, descriptors
│   │   └── Shaders/               # Metal shader files (.metal, .h)
│   ├── Managers/                  # Singleton managers
│   ├── Math/                      # Math utilities, transforms
│   ├── Physics/                   # Physics simulation
│   │   ├── BroadPhase/            # AABB collision detection
│   │   ├── CollisionResponse/     # Collision handling
│   │   ├── Solver/                # Euler, Verlet integrators
│   │   └── World/                 # Physics world, entities
│   ├── Scenes/                    # Game scenes
│   └── Utils/                     # Utility extensions
├── ToyFlightSimulator macOS/      # macOS-specific code
├── ToyFlightSimulator iOS/        # iOS-specific code
├── ToyFlightSimulator tvOS/       # tvOS-specific code
└── ToyFlightSimulatorTests/       # Unit tests
```

## Key Architecture Patterns

### Scene Graph

- `Node`: Base class with transform hierarchy (position, rotation, scale)
- `GameObject`: Extends Node with rendering (mesh, material, physics)
- `Scene`: Container for root nodes, manages scene graph

### Rendering Pipeline

Multiple renderer implementations in `Display/`:

- `SinglePassDeferredLightingRenderer` - GBuffer + lighting pass
- `TiledDeferredRenderer` - Tile-based light culling
- `ForwardPlusTileShadingRenderer` - Forward+ rendering
- `OITRenderer` - Order-independent transparency
- `TiledMSAATessellatedRenderer` - MSAA with terrain tessellation

### Resource Management

- `TextureLoader`: Singleton cache prevents duplicate texture loading
- `MeshLibrary`: Pre-built meshes (sphere, cube, quad)
- `ModelLibrary`: Loaded 3D models

### Managers (Singletons)

- `SceneManager`: Active scene management
- `InputManager`: Centralized input state
- `CameraManager`: Camera switching
- `LightManager`: Scene lighting
- `AudioManager`: Sound playback
- `DrawManager`: Render batching

## Adding New Features

### New Game Object

1. Create class extending `GameObject` in `GameObjects/`
2. Override `doUpdate()` for per-frame logic
3. Add to scene in appropriate `Scene` subclass

### New Shader

1. Add Metal functions to `.metal` file in `Graphics/Shaders/`
2. Create pipeline state in relevant library under `Graphics/Libraries/Pipelines/`
3. Update renderer to use new pipeline

### New Scene

1. Create class extending `GameScene` in `Scenes/`
2. Override `buildScene()` to add game objects
3. Register in `SceneManager`
