# Animation Architecture Analysis: F-35 Landing Gear

**Date**: January 2026
**Status**: Research Complete
**Author**: Architecture Investigation

---

## Problem Statement

The current F-35 landing gear animation implementation is "too coupled to the UsdModel class" (per commit 7357b15). We need to determine the optimal location for high-level animation code (e.g., "extend landing gear", "retract landing gear") that orchestrates the low-level animation system.

### Current State

- **Low-level animation code** lives in `UsdModel.swift` - handles skeletons, skins, animation clips, keyframe interpolation
- **F35.swift** is a thin `Aircraft` subclass - only sets model type and camera offset
- **Aircraft.swift** has `gearDown: Bool` but no connection to the animation system
- Animation playback is driven by elapsed time in `UsdModel.update()`, not by triggered actions

### Options Considered

1. **Option A**: Place high-level animation code in `F35.swift` (GameObject subclass)
2. **Option B**: Create `F35Model` (UsdModel subclass) with aircraft-specific animation methods
3. **Option C**: Create a separate `AnimationController` component (industry pattern)

---

## Industry Research: How Game Engines Handle This

### Unity's Mecanim Animation System

Unity uses a **component-based architecture** with clear separation:

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| Data | FBX/Model | Geometry + skeleton + animation clips |
| Controller | Animator Controller (asset) | State machine with transitions |
| Runtime | Animator (component) | Playback state + clip management |
| Gameplay | MonoBehaviour scripts | Triggers via `SetTrigger()`, `SetBool()` |

**Key Quote from Unity Documentation**:
> "An Animator Controller is an asset designed to play animations on a GameObject and its children. Its function is to blend together multiple Animator Layers into one final list of effects."

**Best Practice from Unity**:
> "Avoid writing complex gameplay code inside of them because it can get difficult to track down where your changes in the state are coming from. If you are using State Machine Behaviour to drive gameplay code, leverage a messaging system; talk to a manager class, or trigger your code off of parameters at a higher level."

**Sources**:
- [Unity Animator Controller Documentation](https://docs.unity3d.com/6000.1/Documentation/Manual/class-AnimatorController.html)
- [Unity Animation Layers](https://docs.unity3d.com/Manual/AnimationLayers.html)
- [Tips for Building Animator Controllers](https://unity.com/how-to/build-animator-controllers)

### Unreal Engine Animation Blueprints

Unreal uses a similar separation with Animation Blueprints:

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| Data | Skeletal Mesh | Geometry + skeleton |
| Controller | Animation Blueprint | State machine + event graph |
| Runtime | Anim Instance | Runtime animation state |
| Gameplay | Actor/Pawn Blueprint | Gameplay triggers |

**Key Quote from Unreal Documentation**:
> "State Machines allow Skeletal Animations to be broken up into various states, with full control over how blends occur from one state to another."

**Sources**:
- [Unreal State Machines Documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/state-machines-in-unreal-engine)
- [Setting up Animation State Machines](https://docs.unrealengine.com/4.27/en-US/AnimatingObjects/Paper2D/HowTo/Animation/)

### Model-View-Controller in Games

Research on MVC architecture in game development:

> "In game software it is important to separate game play code from rendering code to ease transitions to new technologies or different platforms. Game development very much benefits from the use of this pattern. A clean separation between the View (interaction) and the Model (simulation) improves the cross-platform support of a game."

**Source**: [Evolution and Evaluation of the Model-View-Controller Architecture in Games](https://www.researchgate.net/publication/281279155_Evolution_and_Evaluation_of_the_Model-View-Controller_Architecture_in_Games)

### Common Pattern Across Engines

Both Unity and Unreal share these principles:

1. **Model is pure data** - meshes, skeletons, animation clips (no behavior)
2. **Animation controller is a separate component** - manages state machine and playback
3. **GameObject/Actor triggers animations** - via simple API (`SetTrigger`, `SetBool`)
4. **Composition over inheritance** - controllers are components, not subclasses

---

## Current Codebase Analysis

### UsdModel Current Responsibilities (Problem)

`UsdModel.swift` currently handles both **data** and **behavior**:

**Data (Appropriate)**:
- `skeletons: [String: Skeleton]` - skeleton data by path
- `meshSkeletonMap: [Int: String]` - mesh-to-skeleton mapping
- `animationClips: [String: AnimationClip]` - animation data by name
- `skeletonAnimationMap: [String: String]` - skeleton-to-animation mapping
- Loading skeletons, skins, animations from USDZ files

**Behavior (Problematic - should be extracted)**:
- `elapsedAnimationDuration: Float` - playback state
- `previousTime: Float` - playback state
- `update()` - animation playback logic
- `updateAnimations(at:)` - animation timing
- `animateForwards(by:)` / `animateReverse(by:)` - playback direction

### Aircraft Class Hierarchy

```
Node (Transform hierarchy)
  └── GameObject (Rendering + Physics)
      └── Aircraft (Flight dynamics)
          ├── F35 (USDZ model with skeletal animation)
          ├── F22 (USDZ model with skeletal animation)
          ├── F18 (OBJ model, manual animation)
          └── F16 (OBJ model)
```

### F18's Existing Animation Pattern

F18 demonstrates a working separation for non-skeletal animation:

```swift
// State machine flags (F18.swift:294-299)
var landingGearDeployed: Bool = false
var landingGearDegrees: Float = 0.0
var landingGearBeganExtending: Bool = false
var landingGearFinishedExtending: Bool = false
var landingGearBeganRetracting: Bool = false
var landingGearFinishedRetracting: Bool = false

// State machine logic in doUpdate() (F18.swift:438-471)
InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
    if !landingGearDeployed {
        landingGearBeganExtending = true
    } else {
        landingGearBeganRetracting = true
    }
}
```

F18 uses `SubMeshGameObject` children with manual rotation - this works because it's an OBJ model without skeletal animation.

---

## Option Analysis

### Option A: High-Level Code in F35.swift

**Approach**: Put animation control directly in the F35 GameObject subclass.

**Pros**:
- F35 already has access to aircraft state (`gearDown`)
- Natural place for aircraft-specific behavior
- Follows the pattern where game object triggers animations

**Cons**:
- F35 would need to know animation clip names, joint paths, timing details
- Would need to reach into UsdModel internals to control animation
- Mixes gameplay logic (aircraft behavior) with animation specifics
- Doesn't scale - each aircraft would duplicate similar animation code
- Violates Single Responsibility Principle

**Verdict**: Not recommended

### Option B: F35Model (UsdModel Subclass)

**Approach**: Create `F35Model` extending `UsdModel` with methods like `extendGear()`, `retractGear()`.

**Pros**:
- Keeps animation details in the Model layer
- Can encapsulate F35-specific animation knowledge (joint names, clips)
- Provides clean API to F35 GameObject

**Cons**:
- Creates parallel class hierarchies:
  - F35 → Aircraft → GameObject
  - F35Model → UsdModel → Model
- Tight coupling - F35 MUST use F35Model
- Still mixes data and behavior in the Model layer
- Violates composition over inheritance principle
- Doesn't match Unity/Unreal patterns
- Harder to test (must instantiate full model)
- Animation logic trapped in specific Model subclass, not reusable

**Verdict**: Not recommended

### Option C: AnimationController Component (Recommended)

**Approach**: Create a separate `AnimationController` component that manages animation state and playback, owned by the GameObject.

**Pros**:
- Follows Unity/Unreal industry patterns
- Clean separation: Model = data, Controller = behavior, GameObject = triggers
- Composition over inheritance
- Reusable across different aircraft types
- Easy to test animation logic independently
- Single Responsibility Principle maintained
- Scalable architecture

**Cons**:
- Requires refactoring UsdModel to remove animation playback logic
- New classes to create and maintain

**Verdict**: Recommended

---

## Recommended Architecture

### Component Diagram

```
F35 (Aircraft/GameObject)
  │
  ├── model: UsdModel              ← Pure data container
  │     ├── skeletons              (skeleton hierarchy data)
  │     ├── animationClips         (keyframe data)
  │     ├── meshSkeletonMap        (mesh-to-skeleton bindings)
  │     └── skins                  (skinning data)
  │
  └── animator: AircraftAnimator   ← NEW: Animation controller
        ├── gearState              (state machine)
        ├── extendGear()           (high-level triggers)
        ├── retractGear()
        └── update(deltaTime:)     (drives skeleton.updatePose())
```

### Proposed File Structure

```
ToyFlightSimulator Shared/
├── Animation/
│   ├── AnimationClip.swift        (existing - data)
│   ├── Animation.swift            (existing - keyframe data)
│   ├── Skeleton.swift             (existing - data)
│   ├── Skin.swift                 (existing - data)
│   ├── TransformComponent.swift   (existing - data)
│   ├── AnimationController.swift  (NEW - base playback engine)
│   └── AircraftAnimator.swift     (NEW - aircraft state machine)
│
├── Assets/
│   ├── Model.swift                (existing - base class)
│   ├── UsdModel.swift             (REFACTOR - remove playback logic)
│   └── ...
│
└── GameObjects/
    ├── Aircraft.swift             (existing - add animator property)
    ├── F35.swift                  (existing - use animator)
    └── ...
```

### Proposed Interfaces

#### AnimationController Protocol

```swift
protocol AnimationController {
    var isPlaying: Bool { get }
    var currentTime: Float { get }
    var duration: Float { get }

    func play(clipName: String, speed: Float, loop: Bool)
    func pause()
    func stop()
    func setNormalizedTime(_ t: Float)  // 0.0 to 1.0
    func update(deltaTime: Float)
}
```

#### AircraftAnimator Class

```swift
enum GearState {
    case up
    case extending
    case down
    case retracting
}

class AircraftAnimator: AnimationController {
    private weak var model: UsdModel?

    private(set) var gearState: GearState = .down
    private var gearAnimationProgress: Float = 1.0  // 0=up, 1=down

    init(model: UsdModel) {
        self.model = model
    }

    func extendGear() {
        guard gearState == .up else { return }
        gearState = .extending
    }

    func retractGear() {
        guard gearState == .down else { return }
        gearState = .retracting
    }

    func update(deltaTime: Float) {
        switch gearState {
        case .extending:
            gearAnimationProgress += deltaTime / gearAnimationDuration
            if gearAnimationProgress >= 1.0 {
                gearAnimationProgress = 1.0
                gearState = .down
            }
            updateSkeletonPose()

        case .retracting:
            gearAnimationProgress -= deltaTime / gearAnimationDuration
            if gearAnimationProgress <= 0.0 {
                gearAnimationProgress = 0.0
                gearState = .up
            }
            updateSkeletonPose()

        default:
            break
        }
    }

    private func updateSkeletonPose() {
        guard let model = model else { return }
        let animationTime = gearAnimationProgress * gearClipDuration
        // Update skeleton poses via model's animation clips
        for (skeletonPath, skeleton) in model.skeletons {
            if let clipName = model.skeletonAnimationMap[skeletonPath],
               let clip = model.animationClips[clipName] {
                skeleton.updatePose(at: animationTime, animationClip: clip)
            }
        }
        // Update mesh skins
        for (index, mesh) in model.meshes.enumerated() {
            if let skeletonPath = model.meshSkeletonMap[index],
               let skeleton = model.skeletons[skeletonPath] {
                mesh.skin?.updatePalette(skeleton: skeleton)
            }
        }
    }
}
```

#### F35 Usage

```swift
class F35: Aircraft {
    private var animator: AircraftAnimator?

    override init(scale: Float = 1.0, shouldUpdateOnPlayerInput: Bool = true) {
        super.init(name: Self.NAME,
                   modelType: .Sketchfab_F35,
                   scale: scale,
                   shouldUpdateOnPlayerInput: shouldUpdateOnPlayerInput)

        if let usdModel = model as? UsdModel {
            animator = AircraftAnimator(model: usdModel)
        }
    }

    override func doUpdate() {
        super.doUpdate()

        // Handle gear toggle input
        InputManager.HasDiscreteCommandDebounced(command: .ToggleGear) {
            switch animator?.gearState {
            case .down:
                animator?.retractGear()
            case .up:
                animator?.extendGear()
            default:
                break  // Animation in progress
            }
        }

        // Update animation
        animator?.update(deltaTime: Float(GameTime.DeltaTime))
    }
}
```

---

## Migration Plan

### Phase 1: Create Base Infrastructure

1. Create `AnimationController` protocol in `/Animation/AnimationController.swift`
2. Create `AircraftAnimator` class in `/Animation/AircraftAnimator.swift`
3. Define `GearState` enum and basic state machine

### Phase 2: Extract Playback Logic from UsdModel

1. Move `elapsedAnimationDuration`, `previousTime` to `AircraftAnimator`
2. Move `animateForwards(by:)`, `animateReverse(by:)` logic to `AircraftAnimator`
3. Keep `UsdModel.update()` minimal or remove it entirely
4. Ensure skeleton/skin data remains accessible for the animator

### Phase 3: Wire Up F35

1. Add `animator: AircraftAnimator?` property to F35
2. Initialize animator in F35's init with the UsdModel reference
3. Add input handling in `doUpdate()` to trigger gear extension/retraction
4. Call `animator?.update(deltaTime:)` each frame

### Phase 4: Generalize (Future)

1. Add flaps, airbrake, canopy animations to `AircraftAnimator`
2. Create aircraft-specific configuration (animation clip mappings)
3. Apply same pattern to F22 and other USDZ aircraft

---

## Comparison Matrix

| Criterion | Option A (F35.swift) | Option B (F35Model) | Option C (AnimationController) |
|-----------|---------------------|---------------------|-------------------------------|
| Industry Pattern Match | Low | Low | High |
| Separation of Concerns | Poor | Moderate | Excellent |
| Reusability | Low | Low | High |
| Testability | Moderate | Low | High |
| Maintenance Burden | High | High | Moderate |
| Coupling | High | High | Low |
| Scalability | Poor | Poor | Excellent |
| Refactoring Required | Low | Moderate | Moderate |

---

## Conclusion

**Recommendation**: Implement **Option C - AnimationController Component**

This approach:
- Follows established patterns from Unity and Unreal Engine
- Maintains clean separation between data (UsdModel) and behavior (AnimationController)
- Uses composition over inheritance
- Allows the same animator to work with different aircraft models
- Keeps F35.swift focused on aircraft-specific gameplay logic
- Enables independent testing of animation state machine logic

The additional upfront work of creating the AnimationController infrastructure pays off in maintainability, testability, and alignment with industry best practices.

---

## References

- [Unity Animator Controller Documentation](https://docs.unity3d.com/6000.1/Documentation/Manual/class-AnimatorController.html)
- [Unity Animation Layers](https://docs.unity3d.com/Manual/AnimationLayers.html)
- [Tips for Building Animator Controllers in Unity](https://unity.com/how-to/build-animator-controllers)
- [Unreal Engine State Machines](https://dev.epicgames.com/documentation/en-us/unreal-engine/state-machines-in-unreal-engine)
- [Unreal Animation State Machine Setup](https://docs.unrealengine.com/4.27/en-US/AnimatingObjects/Paper2D/HowTo/Animation/)
- [MVC Architecture in Games Research Paper](https://www.researchgate.net/publication/281279155_Evolution_and_Evaluation_of_the_Model-View-Controller_Architecture_in_Games)
- [Unity State Machine Best Practices](https://discussions.unity.com/t/ultimate-state-machine-character-controller-architecture/870803)
