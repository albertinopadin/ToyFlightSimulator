# Repository Guidelines

## Project Structure & Module Organization
- `ToyFlightSimulator Shared/` holds cross-platform engine code: `Core/`, `Graphics/`, `Physics/`, `Scenes/`, `GameObjects/`, `Animation/`, and shared `Assets/`.
- Platform targets live in `ToyFlightSimulator macOS/`, `ToyFlightSimulator iOS/`, and `ToyFlightSimulator tvOS/` (app delegates, view wrappers, menus).
- Metal shaders are under `ToyFlightSimulator Shared/Graphics/Shaders/` (`*.metal`).
- Tests are in `ToyFlightSimulatorTests/`.
- Project media lives in `images/` and exploratory notes under `plans/` and `investigations/`.

## Build, Test, and Development Commands
```bash
# macOS Debug build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# macOS tests
xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS Simulator build
xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator iOS" -sdk iphonesimulator -configuration Debug
```
Run via Xcode, or launch the built app directly (macOS) from `./build/Debug/` after a build.

## Coding Style & Naming Conventions
- Swift uses 4-space indentation; follow the existing file formatting (no SwiftLint/SwiftFormat config is present).
- Types use PascalCase (`RendererType`), members use camelCase (`updateThread`).
- Keep file names aligned with primary types (e.g., `Renderer.swift`, `Node.swift`).
- Place new shader functions in the appropriate `.metal` file under `Graphics/Shaders/`.

## Testing Guidelines
- Tests use XCTest in `ToyFlightSimulatorTests/`.
- File naming: `*Tests.swift`; test methods start with `test` (e.g., `testAddRemoveChild`).
- Prefer unit-level coverage for math, node graph, and renderer setup where feasible.

## Commit & Pull Request Guidelines
- Recent commits use short, imperative, sentence-case messages (e.g., “Add…”, “Implement…”) without prefixes or issue IDs; keep that style.
- PRs should include a concise summary, test command results, and screenshots or captures for rendering or UI changes.

## Additional Notes
- See `CLAUDE.md` for architecture details (renderer types, scene graph, threading model) and extra build tips.
