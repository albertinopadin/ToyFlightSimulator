# ToyFlightSimulator - Technical Stack

## Language & Frameworks

- Swift 6 with strict concurrency checking
- Metal (GPU rendering, compute shaders)
- SwiftUI (menus, UI overlays)
- ModelIO (3D model loading)
- AVFoundation (audio)
- GameController framework (input devices)

## Build System

Xcode project (`ToyFlightSimulator.xcodeproj`) with three targets:

- ToyFlightSimulator macOS
- ToyFlightSimulator iOS
- ToyFlightSimulator tvOS

## Build Commands

### macOS Debug Build

```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### macOS Release Build

```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Run Tests

```bash
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### iOS Simulator Build

```bash
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```

## Key Dependencies

- No external package dependencies - uses Apple frameworks only
- 3D models: OBJ (with MTL) and USDZ formats
- Textures: PNG, JPG, BMP via Asset Catalogs

## Threading Model

- Main Thread: Rendering and UI (MTKViewDelegate)
- Update Thread: Game logic and physics (60 Hz)
- Audio Thread: Background music playback
- Synchronization: `TFSLock` (wrapper around `os_unfair_lock`)

## GPU Profiling

Use Xcode's GPU Frame Capture for detailed analysis. FPS counter displayed in top-left corner.
