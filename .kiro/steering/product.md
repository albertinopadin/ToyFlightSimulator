# ToyFlightSimulator - Product Overview

A flight simulator game built with Swift, SwiftUI, and Metal for Apple platforms (macOS, iOS, tvOS).

## Core Features

- Multiple fighter jet aircraft (F-16, F-18, F-22, F-35)
- Weapons systems (missiles: AIM-120, Sidewinder; bombs: GBU-16)
- Terrain rendering with tessellation
- Particle effects (afterburner, fire)
- Physics simulation (Euler and Verlet integration with collision response)
- Multiple advanced rendering pipelines (deferred lighting, OIT, forward+)
- HOTAS/joystick support on macOS, touch controls on iOS

## Target Platforms

- macOS (primary development target)
- iOS (touch controls with virtual joystick/throttle)
- tvOS

## Current State

Active development with Swift 6 and multithreaded architecture (main/update/audio threads).
