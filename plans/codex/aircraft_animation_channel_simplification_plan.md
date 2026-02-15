# Aircraft Animation Channel Simplification Plan

**Date:** 2026-02-15  
**Goal:** Keep current F-35 channel-set functionality, but reduce code and remove architectural duplication.

## Plan Summary
Simplify to a single runtime abstraction in `AnimationLayerSystem` (channels only), and move landing-gear grouping logic to `AircraftAnimator` using typed binary channels.

## Phase 1: Collapse to One Runtime Model (Channels Only)

1. Remove `channelSets` storage/evaluation paths from `AnimationLayerSystem`.
2. Keep one registration/update path based on `AnimationChannel`.
3. Reconcile APIs so `channelCount`, `hasDirtyChannels`, debug, and `setChannelValue` all reflect the active runtime path.

**Files**
- `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift`

**Acceptance Criteria**
- Only one dictionary/ordering model remains in the layer system.
- No stale APIs that point to unused data structures.

## Phase 2: Replace `AnimationChannelSet` With Typed Gear Channel Grouping

1. Delete set-level hack wrapper usage for landing gear control.
2. Store landing-gear channels in `AircraftAnimator` as `[BinaryAnimationChannel]` (or equivalent typed helper).
3. Implement group operations (`activate/deactivate/toggle`) as loops over typed channels.
4. Aggregate group state deterministically:
   - `down` only if all channels active.
   - `up` only if all channels inactive.
   - otherwise transitional (`extending`/`retracting`) based on active transitions.
5. Define aggregate progress/duration explicitly (e.g., average progress + max duration, or whichever semantic you prefer and document).

**Files**
- `ToyFlightSimulator Shared/Animation/Channels/AnimationChannelSet.swift` (delete)
- `ToyFlightSimulator Shared/Animation/Aircraft/AircraftAnimator.swift`
- `ToyFlightSimulator Shared/Animation/Aircraft/F35Animator.swift`

**Acceptance Criteria**
- No `as? BinaryAnimationChannel` casts needed for gear orchestration.
- No first-channel state/progress hacks.
- Gear toggling behavior remains unchanged in-game.

## Phase 3: Simplify F-35 Animation Config

1. Replace `createLandingGearChannelSet` with `createLandingGearChannels` returning `[BinaryAnimationChannel]`.
2. Remove obsolete single-channel and commented migration code.
3. Replace `fatalError` mapping failures with recoverable handling (warn + skip invalid clip mapping).

**Files**
- `ToyFlightSimulator Shared/Animation/Aircraft/F35AnimationConfig.swift`

**Acceptance Criteria**
- Config file is data-mapping focused and free of migration leftovers.
- Runtime no longer hard-crashes on partial asset mismatches.

## Phase 4: Clean Up Legacy Playback Surface (Optional but Recommended)

1. In `AircraftAnimator`, either:
   - remove unused legacy playback fields (`currentTime`, `playbackSpeed`, `shouldLoop`, `currentClipName`) if truly unused, or
   - clearly mark and minimize them.
2. Keep only interfaces that are consumed by current aircraft paths.

**Files**
- `ToyFlightSimulator Shared/Animation/Aircraft/AircraftAnimator.swift`
- `ToyFlightSimulator Shared/Animation/AnimationController.swift` (only if needed)

**Acceptance Criteria**
- No dead state kept only for historical reasons.
- Public API surface matches actual behavior.

## Phase 5: Fix Masking/Update Correctness While Touching the Area

1. Correct mesh-affect logic in `updatePoses` to avoid effectively unconditional mesh updates for skinned meshes.
2. Keep current behavior for meshes that truly should always update, but make it intentional and explicit.

**Files**
- `ToyFlightSimulator Shared/Animation/AnimationLayerSystem.swift`

**Acceptance Criteria**
- Masking behavior is intentional and readable.
- No obviously always-true mesh matching expression remains.

## Validation Checklist

1. Build macOS target:
   - `xcodebuild build -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
2. Run macOS tests:
   - `xcodebuild test -project ToyFlightSimulator.xcodeproj -scheme "ToyFlightSimulator macOS" -sdk macosx -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
3. Manual runtime checks:
   - Spawn F-35 in current starting scene.
   - Toggle gear repeatedly; verify transitions, final up/down states, and no regressions.
   - Confirm startup pose remains gear-down as before.

## Suggested Implementation Order

1. Phase 1 (single runtime model).
2. Phase 2 (typed gear grouping).
3. Phase 3 (config cleanup).
4. Phase 5 (mask correctness fix).
5. Phase 4 (legacy API cleanup, if safe after above).
