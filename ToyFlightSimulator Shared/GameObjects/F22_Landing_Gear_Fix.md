# F22 Landing Gear Fix

## Issue
When pressing 'G' key, nothing happened - the landing gear animation didn't trigger.

## Root Cause
The F22 aircraft's `hasFocus` property was never set to true in the scene files, preventing input handling in the F22's doUpdate() method.

## Solution
Added `jet.hasFocus = true` after creating the CollidableF22 instance in both FlightboxScene.swift and FlightboxWithTerrain.swift:

```swift
let jet = CollidableF22(scale: 0.25)
// Set focus on jet to enable input handling
jet.hasFocus = true
```

## Fixed Files
- `ToyFlightSimulator Shared/Scenes/FlightboxScene.swift`
- `ToyFlightSimulator Shared/Scenes/FlightboxWithTerrain.swift`

## How It Works
- F22's doUpdate() only processes input when `hasFocus` is true
- Now pressing 'G' toggles the landing gear animation
- Animation runs for 3 seconds with smooth easing
- Uses rotation-based animation instead of simple alpha fading

## Testing
1. Build and run the application
2. Select either Flightbox or FlightboxWithTerrain scene
3. Press 'G' key to toggle landing gear
4. Observe smooth 3-second animation