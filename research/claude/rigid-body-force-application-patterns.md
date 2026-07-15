# Rigid-Body Force Application Patterns

How do popular game engines and flight simulators structure the code that turns player input into forces on a rigid body? This doc surveys the canonical patterns and uses them to answer: should `applyForces` stay on `F22` (and its siblings), or should the aerodynamic-force computation be extracted into a separate component / FDM module / system?

## Question

Right now `F22.applyForces(rigidBody:)` lives on the `F22` class (a `GameObject` subclass). It reads input directly, owns all the aerodynamic constants (`mass`, `engineMaxThrust`, `liftPower`, `liftCoefficientCurve`, `inducedDragCurve`), and writes the resulting force into the attached `RigidBody`'s public `force` field. If we add an F-18, an F-35, and a Cessna later, each will duplicate this structure. The question is whether — and how — to break that up.

The decision space:

1. **Keep as-is.** Each aircraft subclass owns its own force computation and parameters.
2. **Move computation onto `RigidBody`.** Generic `applyForce(...)` API; physics state stays attached to the body.
3. **Extract a "flight model" sibling component.** Aircraft has-a `FlightModel`; the controller reads input, asks the FlightModel for forces, hands them to the RigidBody. This is the **MovementComponent / AircraftPhysics pattern.**
4. **Extract a full FDM module + system.** Pure data-in/forces-out function; called by a system that iterates over all aircraft. This is the **JSBSim / Bevy ECS pattern.**

Each of those has industry precedent. Below: where the precedent comes from, what the tradeoffs are, and what fits this codebase.

## Current code summary

`ToyFlightSimulator Shared/GameObjects/F22.swift` lines 117–210 define a single private method `applyForces(rigidBody:)`. It's called from `doUpdate()` (line 91) every frame, *not* on a fixed timestep — `doUpdate` runs on UpdateThread and uses `GameTime.DeltaTime`, which is wall-clock between successive update ticks.

Key shape of `applyForces`:

```swift
private func applyForces(rigidBody: RigidBody) {
    let fwd = getFwdVector()
    let engineForce = fwd * engineMaxThrust * InputManager.ContinuousCommand(.MoveFwd) * 10.0
    let worldVelocity = rigidBody.velocity
    let localVelo = getLocalVelocity(worldVelocity: worldVelocity)
    let (pitchAOA, _) = calculateAnglesOfAttack(localVelocity: localVelo)
    let liftData = calculateLiftData(angleOfAttack: pitchAOA, ...)
    let inducedDrag = calculateInducedDrag(liftData: liftData)
    let drag = getDragCoefficient() * liftData.liftVelocitySquared * -worldVelocity.normalize()
    rigidBody.force += engineForce + liftData.liftForceVector + inducedDrag + drag
}
```

Things `F22` currently mixes together in one class:

- **Aerodynamic constants** (mass, engineMaxThrust, liftPower, the two curves)
- **Pure aerodynamics math** (`calculateAnglesOfAttack`, `projectOnPlane`, `calculateLiftData`, `calculateInducedDrag`, `getLiftCoefficient`, `getInducedDragCoefficient`, `getDragCoefficient`)
- **Input → force translation** (the `InputManager.ContinuousCommand(.MoveFwd)` read inside `applyForces`)
- **Render/scene-graph concerns** (`getFwdVector`, `getRotationMatrix`, `getRightVector` inherited from `Node`)
- **Per-frame orchestration** (deciding when to run, ground-clamp, animator, afterburner toggle)
- **Game-object identity stuff** (mesh, model, camera offset, child afterburner nodes)

The `RigidBody` in `Physics/World/RigidBody.swift` is a pure data bag: 9 fields and 3 trivial helpers, no integration logic. Force accumulation happens by external code adding to `force`; integration happens in a separate solver (Euler/Verlet) inside `PhysicsWorld`.

## Findings by engine / system

### 1. Unity (MonoBehaviour + Rigidbody, classical)

Unity's documented pattern keeps physics state on a `Rigidbody` component and force-application code on a sibling `MonoBehaviour`. Both live on the same `GameObject`.

From the official `Rigidbody.AddForce` reference, the canonical example is literally:

```csharp
void FixedUpdate() {
    if (Keyboard.current.spaceKey.isPressed) {
        m_Rigidbody.AddForce(transform.up * m_Thrust);
    }
}
```

(`docs.unity3d.com/ScriptReference/Rigidbody.AddForce.html`). Forces are applied from a script attached to the same GameObject as the `Rigidbody`, in `FixedUpdate()` because `"The physics system applies the effects during the next simulation run."` Reading input and applying force happen in different methods: input in `Update`, the force application in `FixedUpdate`, with the input state cached on the controller in between.

The relevant best practice is that the *script* (e.g. `PlayerController`, `PlaneController`, `VehicleController`) is a separate class from the `Rigidbody` component but lives on the same entity. The `Rigidbody` is a thin physics-state proxy; *behavior* lives on script components. This is straightforward composition without inheritance.

**Real-world examples that map cleanly onto F22:**

#### gasgiant/Aircraft-Physics (Khan & Nahon 2015 implementation)

Three sibling MonoBehaviours on the same Aircraft GameObject. Source: `github.com/gasgiant/Aircraft-Physics`.

- `Rigidbody` — Unity built-in; drag set to zero so its own aerodynamics doesn't fight the FDM.
- `AircraftPhysics` — *"applies aerodynamic forces and thrust to the Rigidbody. It exposes a field for the thrust force in newtons and a list of AeroSurfaces."* This is the FDM.
- `AircraftController` — *"interacts with the AircraftPhysics and AeroSurfaces to apply control inputs to the plane... AircraftPhysics and AeroSurface are the core parts of the system and don't need to be changed most of the time. The AircraftController however is written as an example which you can expand upon."*

From the actual `AircraftPhysics.cs`:

```csharp
[RequireComponent(typeof(Rigidbody))]
public class AircraftPhysics : MonoBehaviour {
    [SerializeField] float thrust = 0;
    [SerializeField] List<AeroSurface> aerodynamicSurfaces = null;
    Rigidbody rb;
    float thrustPercent;

    public void SetThrustPercent(float percent) { thrustPercent = percent; }

    private void Awake() { rb = GetComponent<Rigidbody>(); }

    private void FixedUpdate() {
        BiVector3 forceAndTorqueThisFrame = CalculateAerodynamicForces(...);
        // ... predictor-corrector
        rb.AddForce(currentForceAndTorque.p);
        rb.AddTorque(currentForceAndTorque.q);
        rb.AddForce(transform.forward * thrust * thrustPercent);
    }
}
```

And `AirplaneController.cs`:

```csharp
public class AirplaneController : MonoBehaviour {
    AircraftPhysics aircraftPhysics;
    Rigidbody rb;

    private void Start() {
        aircraftPhysics = GetComponent<AircraftPhysics>();
        rb = GetComponent<Rigidbody>();
    }

    private void Update() {
        Pitch = Input.GetAxis("Vertical");
        Roll = Input.GetAxis("Horizontal");
        // ...
    }

    private void FixedUpdate() {
        SetControlSurfecesAngles(Pitch, Roll, Yaw, Flap);
        aircraftPhysics.SetThrustPercent(thrustPercent);
        // ...
    }
}
```

Notice the strict split: `AircraftController` reads input and sets *abstract intent* (pitch/roll/yaw -1..1, thrust percent, flap angle). `AircraftPhysics` knows nothing about input — it only knows wing geometry and how to compute forces given a Rigidbody state. `AeroSurface` is data-only (lift slope, drag, chord). This means **the FDM is unit-testable in isolation**, and **AI pilots reuse `AircraftPhysics` unchanged** by writing a different controller.

#### vazgriz tutorial #1 — monolithic `Plane.cs`

The earlier of vazgriz's two flight-sim tutorials (`vazgriz.com/346/flight-simulator-in-unity3d-part-1/`) puts everything on one class. Looking at `github.com/vazgriz/FlightSim/blob/main/Assets/Scripts/Plane.cs`, you find a 600+-line `Plane : MonoBehaviour` with `UpdateThrust()`, `UpdateDrag()`, `UpdateLift()`, `UpdateAngularDrag()`, `UpdateSteering()`, all calling `Rigidbody.AddRelativeForce(...)` directly:

```csharp
void UpdateThrust() {
    Rigidbody.AddRelativeForce(Throttle * maxThrust * Vector3.forward);
}

void UpdateLift() {
    // ...
    Rigidbody.AddRelativeForce(liftForce);
    Rigidbody.AddRelativeForce(yawForce);
}
```

This is structurally identical to current `F22.swift`. And vazgriz's own philosophy in that post is: *"the most important principle is to fake as much as possible. Physics forces are applied based on simple formulas and hand-tuned parameters, which is much more performant and keeps the code base simple and understandable."* For an arcade/Ace-Combat flight sim, one MonoBehaviour is fine.

#### vazgriz tutorial #2 — F-16 from Stevens/Lewis/Johnson

His second project (`vazgriz.com/762/f-16-flight-sim-in-unity-3d/`) — translating the Fortran F-16 simulator from *Aircraft Control and Simulation* (Stevens, Lewis, Johnson) — explicitly splits things up. He writes:

> *"Because the flight model is separate from Unity's physics engine, we can actually test it using normal unit testing techniques."*

The classes are:

- `Plane` — orchestrator; unit conversions; calls everything in `FixedUpdate`.
- `Aerodynamics` — translated Fortran; computes forces and angular accelerations from lookup tables.
- `AirDataComputer` — atmosphere (dynamic pressure, Mach).
- `Engine` — thrust as function of throttle and conditions.
- `SimpleTrimmer` — G/AOA limiter that predicts future state.

Crucially, `Aerodynamics` *returns* an `AerodynamicForces` struct (force + angular accel vectors). `Plane` is what calls `Rigidbody.AddRelativeForce(...)` and `Rigidbody.AddRelativeTorque(...)`. The FDM is a pure function.

This is the same split as gasgiant's project, just with more sub-systems. The reasons vazgriz states explicitly: **testability** and **separation between data-driven physics and engine integration glue**.

### 2. Unity DOTS / ECS (the modern path)

Unity has been building an ECS-native Vehicles package since ~2024 (`unity.com/roadmap/2699-ecs-vehicle-controller`, "Unity Vehicles experimental package now available"). The pattern is canonical ECS: an entity has data components (`Velocity`, `Mass`, `WheelData`, `ControlInput`), and *systems* run over those components to compute forces and apply them. There is no "Vehicle" class. Behavior lives in stateless systems that iterate.

The shift from MonoBehaviour-on-entity to system-over-components is a deliberate design choice for performance and parallelism, but the architectural lesson is identical: **the aerodynamic math is not part of the entity's identity. It's a transformation over state.**

### 3. Unreal Engine (UPawn + UMovementComponent)

Unreal's framework is the strongest example of "factor movement out of the entity, period." The class hierarchy is:

- `AActor` — base entity
- `APawn` — actor that can be possessed by a controller
- `ACharacter` — pawn with capsule + skeletal mesh
- `UMovementComponent` — abstract movement
- `UPawnMovementComponent` — movement attached to a pawn
- `UFloatingPawnMovement` — for non-gravity pawns (e.g. drones, spaceships, aircraft)
- `UCharacterMovementComponent` — humanoid walk/run/jump/swim
- `UChaosVehicleMovementComponent` — wheeled vehicle movement
- `UChaosWheeledVehicleMovementComponent` — etc.

The Pawn doesn't move itself. It owns (`has-a`) a MovementComponent and the MovementComponent does the work. From the discussion in the Epic forums (`forums.unrealengine.com/t/.../299128`): *"Movement components are often tightly coupled to the actor classes to which they're designed to attach, with UPawnMovementComponent required to be attached to an APawn."* And from the old UE4 wiki on creating a movement component: *"Components of this type are just like engines. Their function is moving the object forward and rotating it when necessary, without worrying about what kind of logic should the object rely on for movement or what state it is in. They are only responsible for the actual movement of the subject."*

That phrasing — *"engines... only responsible for the actual movement, no game logic"* — is the architectural argument verbatim. The Pawn handles input, possession, gameplay state. The MovementComponent handles physics. Different lifetimes, different reasons to change, different test fixtures.

For aircraft specifically, the Epic-recommended starting point is `UFloatingPawnMovement` (no gravity), and you either subclass it or build a custom component (often called `UAircraftMovementComponent` in tutorials). Either way it's *not* code that lives directly on the Pawn.

The `Chaos Vehicles` and `Chaos Modular Vehicles` systems extend this further: a `UChaosVehicleMovementComponent` aggregates sub-components (wheels, suspension, aerodynamics) that each compute partial forces. Same pattern, more decomposed.

### 4. Godot (RigidBody3D._integrate_forces)

Godot puts the customization hook *on the rigid body itself*, not on a sibling component. From the official docs (`docs.godotengine.org/en/stable/classes/class_rigidbody3d.html`):

> *"If you need to directly affect the body, prefer `_integrate_forces()` as it allows you to directly access the physics state."*

The signature is:

```gdscript
void _integrate_forces(state: PhysicsDirectBodyState3D)
```

`state` is a callback object that exposes `apply_central_force`, `apply_force`, `apply_torque`, `apply_central_impulse`, etc. The recommended pattern is to attach a script that extends `RigidBody3D`, override `_integrate_forces`, and call `state.apply_force(...)` from inside. If you want fully custom integration with no built-in gravity/damping, set `custom_integrator = true`.

So Godot's idiom is closer to *"put a method on the rigid body."* But — and this is important — Godot accomplishes this via *scene-tree composition + scripting*, not inheritance. The "aircraft" is a `RigidBody3D` Node with a script. The script can pull in helper modules, autoloads, or sub-Nodes for sub-systems. The Godot community pattern for flight: aerodynamic forces apply at center of lift (via `apply_impulse(offset, force)`), thrust at center of mass, control surfaces are children with their own scripts.

The relevant takeaway for our codebase: Godot's choice of placement (override-on-body vs. sibling-component) is a stylistic difference; the *separation between input handling and force computation* is still very much present (input typically read in `_process`, forces applied in `_integrate_forces`).

### 5. Bevy / bevy_rapier (pure ECS)

Bevy + Rapier is the cleanest "thin entity, fat system" example. From the official Rapier-Bevy docs (`rapier.rs/docs/user_guides/bevy_plugin/rigid_body_forces_and_impulses/`):

> *"Forces affect the rigid-body's acceleration whereas impulses affect the rigid-body's velocity."*

The Aircraft entity is constructed at spawn with components:

```rust
commands.spawn(RigidBody::Dynamic)
    .insert(Collider::cuboid(...))
    .insert(ExternalForce { force: Vec3::ZERO, torque: Vec3::ZERO })
    .insert(Velocity::default())
    .insert(AircraftConfig { lift_power: 50.0, max_thrust: 31_751.0, ... })
    .insert(PlayerControlled);
```

The flight-model logic lives in a **system function**, completely separate from the entity:

```rust
fn apply_aerodynamic_forces(
    mut q: Query<(&Transform, &Velocity, &mut ExternalForce, &AircraftConfig, &PlayerInput),
                 With<PlayerControlled>>,
) {
    for (transform, velocity, mut ext_force, config, input) in q.iter_mut() {
        let fwd = transform.forward();
        let engine_force = fwd * config.max_thrust * input.throttle;
        // ... lift, induced drag, drag ...
        ext_force.force = engine_force + lift + induced_drag + drag;
    }
}
```

Note the perfect separation:

- **Entity** is just an ID with a bag of plain-data components.
- **Components** are data only (no methods).
- **System** is a pure function `(world state) → (world state)`.
- **Input** is its own component, populated by an input system, read by the force system.
- **AircraftConfig** is its own component holding lift_power, max_thrust, curves — the parameters live with the entity but separately from the math.

A different `apply_aerodynamic_forces_for_helicopters` system can run on a different `With<>` filter. An AI controller writes the same `PlayerInput`-style component and the aerodynamic system never knows the difference.

The bevy_rapier issue tracker (issue #543, custom gravity integration) confirms: *"custom forces should be applied through ExternalForce components, with system ordering to ensure gravity calculations run before physics steps."* The mainline answer is always "write a system; mutate ExternalForce."

### 6. Real flight simulators

This is where the principle gets sharpest. **No serious flight simulator puts the FDM on the entity.** The FDM (Flight Dynamics Model) is *always* a separately-loaded, separately-tested module that takes aircraft state in and produces forces and moments out.

#### JSBSim

JSBSim (`github.com/JSBSim-Team/jsbsim`, used by FlightGear and many academic/UAV applications) is a multi-platform, object-oriented FDM written in C++. The class layout:

- `FGFDMExec` — the executive. Instantiates and initializes all model objects, coordinates execution order.
- `FGPropagate` — integrates equations of motion. Manages position (ECEF) and orientation (quaternions).
- `FGAerodynamics` — calculates aerodynamic forces and moments.
- `FGPropulsion` — engines and propulsion.
- `FGAccelerations` — sums forces and moments from all sources, divides by mass / inertia.
- `FGAircraft` — aggregates forces and moments from various sources.
- `FGGroundReactions` — landing gear, ground contact.
- `FGMassBalance`, `FGAtmosphere`, `FGWinds`, `FGFCS` — support subsystems.

From `jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGAerodynamics.html`: *"This class owns and contains the list of force/coefficients that define the aerodynamic properties of an aircraft."* Methods: `GetForces()`, `GetMoments()`, `GetForcesInStabilityAxes()`, `GetvFw()` (wind-axis forces), etc. It returns vectors. Something else (FGAccelerations) consumes them.

The whole FDM is **data-driven via XML** (JSBSim-ML format). No aircraft-specific compiled code; the aerodynamics, mass, control system, and propulsion are all described declaratively. *"It is designed to support simulation modeling of any aerospace craft without the need for specific compiled and linked program code, instead relying on a versatile and powerful specification written in an XML format."* (`jsbsim-team.github.io/jsbsim/`).

The clincher: FlightGear has *two* alternative FDMs (JSBSim and YASim) and they're swappable per aircraft. From the FlightGear wiki: *"The FDM system in FlightGear is one of the most modular abstractions using the property tree at the moment, so that the corresponding components (jsbsim and yasim) actually are distinct, and may even run standalone, even as a separate process."* (`wiki.flightgear.org/JSBSim_vs_YASim`). The FDM is so decoupled it can run *out of process*. This is the architectural North Star for "separate the flight model."

#### FlightGear / YASim

YASim is FlightGear's alternative FDM. Where JSBSim is table-driven (you supply Cl/Cd curves), YASim is **solver-based**: you specify physical layout (wings, fuselage, engines, control surfaces) and YASim solves for the coefficients. Different math, same architectural place — a module that the simulator calls per tick, outside of any "Aircraft" entity class.

#### Microsoft Flight Simulator

MSFS is fully data-driven. Each aircraft is two config files:

- `aircraft.cfg` — identity, role, presentation. *"Provides general information about the aircraft and its variations to the simulation."*
- `flight_model.cfg` — flight model parameters. *"An optional aircraft file for defining the flight model of the aircraft. The geometry section is for defining the geometry of an aircraft, and is a very important part of the Microsoft Flight Simulator 2020 flight model since the physics simulation will be based mainly on the actual physical geometry of the aircraft."*

(`docs.flightsimulator.com/msfs2024/html/5_Content_Configuration/CFG_Files/aircraft_cfg.htm`, `docs.flightsimulator.com/flighting/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model_cfg.htm`).

External code interacts via **SimConnect**, an out-of-process API that exposes SimVars (`AIRSPEED_INDICATED`, `ELEVATOR_DEFLECTION`, etc.). Add-on developers don't write a flight-model class; they write *config data* that drives the engine's generic FDM, or they intercept SimVars via SimConnect. Aircraft = data, flight model = engine code, controller = SimConnect client. Three layers, three lifetimes.

#### Falcon 4 BMS

Falcon BMS's Advanced Flight Model (AFM) is the canonical hardcore-sim case study. From `falcon-bms.com/articles/flight-model/the-development-of-the-physics-engine/`:

> *"The new FM code was developed to be completely autonomous from F4, with the new code fed values coming from F4 (atmosphere, terrain, weapons, fuel, etc) and exporting output values into the F4 code (world positions, speeds, angles, etc)."*

> *"Two different code modules coexist – the original MPS one (called 'OFM' for Old Flight Model) for aircraft that don't have the new advanced flight model, and the new Advanced Flight Model (AFM)."*

The AFM has six modules (Mechanical, Aero, Equations of Motion, Atmosphere, Pilot Inputs, Output). The equations of motion module integrates 13 coupled non-linear differential equations using Runge–Kutta RK4. The Aero module is built primarily from NASA Technical Paper 1538 wind-tunnel data.

Two important architectural facts:

1. **Two FDMs coexist** in the same simulator. AI aircraft use OFM; player-controlled high-fidelity aircraft use AFM. This is only possible because the flight model is not part of the aircraft entity.
2. **"Completely autonomous from F4."** The FDM is structurally isolated from the rest of the game. Forces in, state out.

#### Stevens / Lewis / Johnson, *Aircraft Control and Simulation*

The textbook that vazgriz's F-16 port is based on (Wiley, 3rd ed. 2015 with Eric N. Johnson, originally 1992). The pedagogical structure of every flight sim it describes is the same: an aerodynamic-coefficients block (lookup tables), an engine block, an atmosphere block, an inertia/mass block, an equations-of-motion block. Each is a separable function with inputs and outputs. The "aircraft" is just the combination — and you can swap one block out for a different aircraft model.

This pedagogical decomposition has propagated into virtually every serious flight-sim implementation. JSBSim's `FGAerodynamics`, MSFS's `flight_model.cfg`, BMS's AFM Aero module, vazgriz's `Aerodynamics` class — they're all the same idea.

### 7. General software-architecture references

#### Mick West — *Evolve Your Hierarchy* (2007)

West (Tony Hawk lead programmer) is the foundational reference for moving from inheritance to composition in game engines. The blog post (`cowboyprogramming.com/2007/01/05/evolve-your-heirachy/`) describes Neversoft's migration. The argument:

> *"Objects had unnecessary data and functionality. Sometimes the unnecessary functionality slowed down the game."*

> *"An object is now created as an aggregation (a collection) of independent components."*

And specifically about physics:

> *"Not every object needs to be able to [react under physics as a rigid body]... What happens when we want to apply this functionality to the vehicles? You have to move the CRigid class further up the hierarchy."*

The general point: deep inheritance ladders make physics functionality hard to share between disparate entity types. Components make it trivial.

#### Robert Nystrom — *Game Programming Patterns: Component*

Nystrom's online book (`gameprogrammingpatterns.com/component.html`) is the canonical modern reference. The "Bjorn the baker" example starts with a monolithic class `Bjorn::update()` that does input, physics, rendering, and audio in one method. Nystrom's complaint:

> *`if (collidingWithFloor() && (getRenderState() != INVISIBLE)) { playSound(HIT_FLOOR); }`* — code that forces any programmer to understand physics, graphics, and audio simultaneously.

The refactor splits into `InputComponent`, `PhysicsComponent`, `GraphicsComponent`. Bjorn becomes a thin container. *"The components are now decoupled. Even though Bjorn has a PhysicsComponent and a GraphicsComponent, the two don't know about each other."*

When to use components (Nystrom):

- A class touches multiple domains needing decoupling
- A class becomes massive and unmanageable
- Inheritance doesn't provide precise code reuse

Costs (Nystrom is honest about these too):

- More objects to wire up at construction
- Inter-component communication needs a protocol
- Pointer chasing can hurt cache locality

#### Jason Gregory — *Game Engine Architecture*

Chapter 13 covers Collision and Rigid-Body Dynamics; Chapter 16 covers the Gameplay Foundation System and runtime object models. Gregory presents three runtime-object archetypes — monolithic class hierarchy, properties-on-base-class, and component-based — and lays out the argument that AAA engines have converged on components-or-ECS for the same reasons West gives.

#### Thin entity / fat system (ECS literature)

The "thin entity, fat system" framing is the ECS axiom: *"An entity usually only consists of a unique ID... Systems are essentially a block of usually stateless behaviours to be executed over Entity Components."* Components hold state with zero logic; systems operate over components and contain all behavior. This is the natural endpoint of the "extract physics out of the entity" trajectory.

## Cross-cutting patterns

Stepping back from individual engines, four common themes emerge across all of the above:

1. **Every serious flight simulator separates the FDM from the entity.** JSBSim, YASim, MSFS, BMS, vazgriz's F-16, gasgiant's Khan-Nahon implementation — all of them. The FDM is a function/module that takes state and parameters and returns force + moment. The aircraft is the *combination* of {render representation, FDM, controller, RigidBody}.

2. **General-purpose game engines lean toward sibling-component composition.** Unity: scripts on the same GameObject as the Rigidbody. Unreal: MovementComponents on a Pawn. Godot: scripts overriding `_integrate_forces` on RigidBody3D. The exact placement varies — sibling, override-on-body, or system — but the *content* (input handling, parameter ownership, force math) is never collapsed onto a single inheritance-extended entity class. The Unreal documentation phrasing is the canonical justification: *"Components of this type are just like engines... only responsible for the actual movement of the subject."*

3. **Modern ECS engines push the math entirely into a system.** Bevy + Rapier is the strongest example. The Aircraft is just an ID + components. The aerodynamic-force code lives in a `fn apply_aerodynamic_forces(query: Query<...>)` function. Unity's DOTS Vehicles package is the same idea retrofitted into Unity. This gives the strongest decoupling but requires buying into ECS wholesale.

4. **Input and force application are always split into two phases, even within a frame.** Read intent (pitch, roll, yaw, throttle, normalized −1..1) → physics tick applies that intent through a model that converts intent to forces. Unity's `Update`/`FixedUpdate` split, Unreal's input-then-tick, Bevy's input-system-runs-before-physics-system. The intent layer is short, simple, dumb. The model layer is where all the lift coefficients and curves live. The current F22 code collapses these.

A more subtle theme: **the FDM never owns the input pipeline.** `AircraftPhysics` in gasgiant's project doesn't call `Input.GetAxis`. `Aerodynamics` in vazgriz's F-16 doesn't call `Input.GetAxis`. `FGAerodynamics` doesn't read joystick state. The controller component does that and feeds normalized values into the FDM. The current F22's `applyForces` calls `InputManager.ContinuousCommand(.MoveFwd)` directly inside the aerodynamic-force computation — that's the most "smelly" line of the function from this perspective.

## Pros / cons for this codebase

Now to the specific question: should the F22's aerodynamic-force code be refactored, and into what?

### Option A — Keep on F22 (status quo)

**Pros**
- Zero refactor risk. Code currently works after the recent flight-model fixes.
- Simple to reason about for one aircraft. The whole loop is in one file.
- Matches vazgriz's tutorial #1 (`Plane.cs`), which is the "starter" archetype.

**Cons**
- Duplicated when F-18, F-35, or other aircraft are added. Each gets its own `applyForces`, its own `calculateLiftData`, etc. (Aircraft.swift already has a hook; F35 is presumably next.)
- F22 already mixes six concerns (constants, math, input, scene-graph access, orchestration, identity). Adding more aircraft makes this worse, not better.
- Aerodynamic math is not unit-testable in isolation. To test `calculateLiftData`, you have to instantiate an `F22 : Aircraft : GameObject : Node` with a model, mesh, etc.
- AI pilots would need to call the same `applyForces` through some "fake input" injection because the input read is hardcoded inside the function.
- Diverges from the consensus pattern of every flight simulator surveyed.

### Option B — Move `applyForces` onto `RigidBody`

The user mentioned this as a possible refactor. It would look like `rigidBody.applyAerodynamicForces(...)` or even just `rigidBody.applyForce(...)` with the F22 still computing the value.

**Pros**
- If it's just a generic `applyForce(_:)` API, that's a useful API on `RigidBody` regardless. (`rigidBody.force += x` is currently bare field access; a small wrapper would be a marginal improvement.)

**Cons**
- If `RigidBody` knows about aerodynamics, that's wrong. `RigidBody` should be domain-neutral. A baseball, a missile, and an aircraft all have RigidBodies; only one of them has lift curves.
- Doesn't actually address the coupling problem. The aerodynamic math still has to live somewhere; if not on F22 and not on RigidBody, then where? Answer: a third class. Which is option C.

So option B as "fat RigidBody" is not the right move. Option B as "trivial `applyForce(_:)` helper on RigidBody for ergonomics" is fine and orthogonal.

### Option C — Extract `FlightModel` sibling component (recommended)

Mirror the Unreal MovementComponent / Unity AircraftPhysics pattern. Roughly:

```swift
protocol FlightModel {
    func computeForces(state: RigidBodyState,
                       intent: ControlIntent,
                       deltaTime: Float) -> ForceAndTorque
}

struct ControlIntent {
    var throttle: Float   // 0..1
    var pitch: Float      // -1..1
    var roll: Float       // -1..1
    var yaw: Float        // -1..1
}

struct ForceAndTorque {
    var force: float3
    var torque: float3
}

class F22FlightModel: FlightModel {
    let mass: Float = 30_000
    let engineMaxThrust: Float = 31_751
    let liftPower: Float = 50.0
    let liftCoefficientCurve = ValueCurve.smooth([...])
    let inducedDragCurve = SymmetricSigmoidCurve(...)

    func computeForces(state: RigidBodyState,
                       intent: ControlIntent,
                       deltaTime: Float) -> ForceAndTorque {
        // all the existing math from F22.applyForces, but pure
    }
}
```

Then `Aircraft` (or each aircraft subclass) has a `flightModel: FlightModel` property, and `Aircraft.doUpdate` does:

```swift
let intent = readIntent()              // from InputManager or AI
let state = rigidBody.state            // velocity, transform, etc.
let result = flightModel.computeForces(state: state, intent: intent, deltaTime: dt)
rigidBody.force += result.force
rigidBody.torque += result.torque      // when torque support lands
```

**Pros**
- Matches Unity's gasgiant pattern, Unreal's MovementComponent pattern, vazgriz's F-16 pattern.
- Each aircraft gets its own `F22FlightModel`, `F35FlightModel`, etc. with its own constants and curves.
- `F22FlightModel.computeForces(...)` is a *pure function* of state + intent. Unit-testable directly: `XCTAssertEqual(f22FM.computeForces(state: hover, intent: maxThrottle).force.z, ...)`.
- AI controllers reuse `F22FlightModel` by feeding it `ControlIntent` from autopilot logic instead of input.
- Stays inside the existing `GameObject` hierarchy. No ECS rewrite. Composable both ways: `Aircraft has-a FlightModel`, `Aircraft is-a GameObject`.
- `RigidBody` stays a thin data bag. No new concerns added to it.
- Lays the groundwork for moments/torques cleanly, which `applyForces` is already going to need for aileron-rolls / pitch-from-elevator. Right now F22 mixes torque application elsewhere (`applyPlayerAttitudeInput`), which is also worth eventually merging into the FDM.

**Cons**
- Refactor cost. Three new files (`FlightModel.swift`, `F22FlightModel.swift`, `ControlIntent.swift`) and substantive changes to `Aircraft` and `F22`.
- One more layer to read. For a reader who knows the codebase, it's no harder; for a first-time reader of F22 it's one extra hop.
- Need to decide where `_turnSpeed`, `_moveSpeed`, `applyPlayerAttitudeInput`, `applyPlayerSideMove`, `handleGearToggle` go. Most of those are control-intent translation and should logically move toward the input/controller side; landing gear is gameplay state, etc. This is more thinking than the FDM extract itself.
- Doesn't help if there's only ever going to be one aircraft. (But the project obviously isn't going there — Aircraft is already a base class, AircraftAnimator/F22Animator/F35Animator already exist, the renderer is built for many aircraft.)

### Option D — Full ECS / system extraction

Pull the aerodynamic-force code into a free-standing function that runs as a system iterating over all aircraft, à la Bevy.

**Pros**
- Maximum decoupling.
- Natural fit if the project ever moves to ECS (the project already has an investigation doc `ecs_and_dod_research_2026-05-13.md` exploring this).

**Cons**
- Currently mismatched with project architecture. ToyFlightSimulator is built around `Node`/`GameObject` scene-graph inheritance (the CLAUDE.md is explicit about this). Adding an ECS-style system on top of an OO scene graph creates a hybrid that is more confusing than either pure style.
- High refactor cost for marginal additional decoupling over option C.
- Should be revisited if and when the codebase moves to ECS; not now.

## Recommendation

**Refactor to option C: extract `FlightModel` as a sibling component on `Aircraft`.**

This is the right move because:

1. It matches the consensus pattern from every flight simulator surveyed, and from every general-purpose game engine that addressed this exact problem (Unity-classical, Unity-DOTS, Unreal, Godot). The variations across engines are about *placement* (sibling, MovementComponent, system) — not about *whether* to extract.

2. The cost is bounded: ~3 new files plus mechanical changes to `Aircraft.swift` and `F22.swift`. It does not require rewriting `RigidBody`, `PhysicsWorld`, scene graph, or anything else. It can land in one PR.

3. It unblocks several near-term goals that are currently expensive:
   - Adding F-18 / F-35 flight models cleanly (without copy-pasting `calculateLiftData` six times).
   - Unit-testing aerodynamic math without instantiating a full GameObject (the project already uses Swift Testing in `Math/`, `Utils/`, `AssetPipeline/` — `FlightModel/F22FlightModelTests` would slot in naturally).
   - Adding AI pilots that drive the same FDM with non-keyboard intent.
   - Eventually adding torque/moment support cleanly (the FDM owns "force + torque" as one struct).

4. It does *not* require buying into ECS or rewriting the scene graph. It's pure composition on top of the existing OO model.

### Shape of the refactor (sketch)

```
ToyFlightSimulator Shared/
  Physics/
    FlightModel/                                   ← new
      FlightModel.swift                            ← protocol
      ControlIntent.swift                          ← struct
      ForceAndTorque.swift                         ← struct
      RigidBodyState.swift                         ← struct (snapshot)
  GameObjects/
    Aircraft.swift                                 ← gains var flightModel: FlightModel?
    F22.swift                                      ← shrinks; no aero math
    F35.swift                                      ← gains F35FlightModel later
  Physics/FlightModel/Models/                      ← new
    F22FlightModel.swift                           ← all the curves + math
    F35FlightModel.swift                           ← later
```

Key boundaries:

- `FlightModel` knows about: `RigidBodyState` (read), `ControlIntent` (read), `ForceAndTorque` (write). Nothing else. **Crucially, does NOT read `InputManager` directly.**
- `Aircraft.doUpdate` reads input, builds a `ControlIntent`, snapshots `RigidBodyState`, calls `flightModel.computeForces(...)`, applies the result to `rigidBody.force` / `rigidBody.torque`. The input-reading code stays where it is now.
- `F22.swift` stays for the *identity / scene-graph / animation / afterburner* part. It just no longer contains lift/drag math.
- `RigidBody.swift` is untouched (or grows a trivial `applyForce(_:)` helper).
- Tests: `F22FlightModelTests` instantiates `F22FlightModel()` directly, builds a `RigidBodyState` literal, feeds in a `ControlIntent`, asserts on the returned vector.

### A note on coupling Aircraft to its flight model

The above sketch puts `flightModel` as a stored property on `Aircraft`. An alternative is to put it on `F22` specifically. I'd put it on `Aircraft` (with a default of `nil`) because it's the same kind of property as `animator: AircraftAnimator?` already on `Aircraft` — same lifetime, same "delegated specialist behavior" pattern. Aircraft already uses `setupAnimator<A: AircraftAnimator>(_ make: (UsdModel) -> A)` per the CLAUDE.md; an analogous `setupFlightModel<FM: FlightModel>(_ make: () -> FM)` is the natural mirror.

### Don't do this in this PR

- Don't try to also do torque/moment cleanup at the same time. Make the FDM struct return torque, but for now F22FlightModel can return `.zero` torque and let the existing `applyPlayerAttitudeInput` path keep working unchanged. Torque cleanup is a separate, larger task.
- Don't try to make this generic for non-aircraft (cars, missiles, etc). `FlightModel` can be the protocol name; the analogue for ground vehicles would be a `VehicleModel` protocol later, parallel structure.
- Don't move to ECS. That's a different refactor, well-explored in `ecs_and_dod_research_2026-05-13.md`, and shouldn't be coupled to this one.

## References

- [Unity — Rigidbody.AddForce Scripting Reference](https://docs.unity3d.com/ScriptReference/Rigidbody.AddForce.html) — canonical FixedUpdate + AddForce pattern; "physics system applies the effects during the next simulation run."
- [Unity — Rigidbody.AddTorque Scripting Reference](https://docs.unity3d.com/ScriptReference/Rigidbody.AddTorque.html) — companion API for torques.
- [VAZGRIZ — Creating a Flight Simulator in Unity3D Part 1: Flight](https://vazgriz.com/346/flight-simulator-in-unity3d-part-1/) — monolithic Plane.cs approach; "fake as much as possible."
- [VAZGRIZ — Translating a Fortran F-16 Simulator to Unity3D](https://vazgriz.com/762/f-16-flight-sim-in-unity-3d/) — separated Plane / Aerodynamics / Engine / AirDataComputer architecture; "the flight model is separate from Unity's physics engine, we can actually test it using normal unit testing techniques."
- [vazgriz/FlightSim — github.com](https://github.com/vazgriz/FlightSim) — repo for Part 1 tutorial; the monolithic Plane.cs is `Assets/Scripts/Plane.cs`.
- [gasgiant/Aircraft-Physics — github.com](https://github.com/gasgiant/Aircraft-Physics) — Khan & Nahon 2015 implementation; AircraftPhysics + AeroSurface + AircraftController split, all sibling MonoBehaviours.
- [Khan & Nahon 2015 — Real-time modeling of agile fixed-wing UAV aerodynamics](https://www.semanticscholar.org/paper/Real-time-modeling-of-agile-fixed-wing-UAV-Khan-Nahon/8291b982a4140da5549026060a676b27c2bd6116) — the paper the Aircraft-Physics project implements.
- [Unity — ECS Vehicle Controller roadmap entry](https://unity.com/roadmap/2699-ecs-vehicle-controller) — modern Unity push toward systems over components rather than scripts-on-GameObjects.
- [Unity — Unity Vehicles experimental package announcement](https://discussions.unity.com/t/unity-vehicles-experimental-package-now-available/1636923) — ECS-native vehicle controller package.
- [Unreal Engine 5.7 — UMovementComponent API reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/GameFramework/UMovementComponent) — base class for all movement components.
- [Unreal Engine 5.7 — Chaos Vehicles documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/chaos-vehicles) — modern wheeled-vehicle movement component.
- [Unreal Engine 5.7 — Chaos Modular Vehicles](https://dev.epicgames.com/documentation/unreal-engine/chaos-modular-vehicles) — modular variant; aerodynamics is its own sub-component.
- [Epic Forums — Using UNavMovementComponent or UMovementComponent](https://forums.unrealengine.com/t/using-unavmovementcomponent-or-umovementcomponent/299128) — class-hierarchy discussion of why movement is its own component.
- [Epic Forums — Differences between UPawnMovementComponent and UFloatingPawnMovement](https://forums.unrealengine.com/t/which-are-the-differents-between-upawnmovementcomponent-and-ufloatingpawnmovement/247411) — "UFloatingPawnMovement is designed for pawns that float or move freely without gravity constraints—think spaceships or aerial vehicles."
- [Old UE4 Wiki — Creating a movement component for pawn](https://nerivec.github.io/old-ue4-wiki/pages/creating-a-movement-component-for-pawn.html) — "Components of this type are just like engines. Their function is moving the object forward and rotating it when necessary, without worrying about what kind of logic should the object rely on for movement."
- [Old UE4 Wiki — Blueprint Six-DOF Flying Pawn Tutorial](https://nerivec.github.io/old-ue4-wiki/pages/blueprint-six-dof-flying-pawn-tutorial.html) — practical Pawn-with-MovementComponent flying example.
- [Godot — RigidBody3D class reference](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html) — `_integrate_forces` is the recommended override hook.
- [Godot — PhysicsDirectBodyState3D class reference](https://docs.godotengine.org/en/stable/classes/class_physicsdirectbodystate3d.html) — callback object exposing `apply_force`, `apply_central_force`, `apply_torque` etc.
- [Godot — Using RigidBody tutorial](https://docs.godotengine.org/en/stable/tutorials/physics/rigid_body.html) — recommended idioms.
- [Rapier — Rigid Body Forces and Impulses (Bevy plugin)](https://rapier.rs/docs/user_guides/bevy_plugin/rigid_body_forces_and_impulses/) — `ExternalForce` component pattern; system iterates and mutates.
- [Rapier — Rigid Bodies guide (Bevy plugin)](https://rapier.rs/docs/user_guides/bevy_plugin/rigid_bodies/) — broader Bevy + Rapier integration overview.
- [Tainted Coders — Bevy Physics: Rapier](https://taintedcoders.com/bevy/physics/rapier) — community-written walkthrough; `RigidBody::Dynamic` modified via `Velocity`, forces via `ExternalForce`.
- [dimforge/rapier issue #543 — custom gravity integration](https://github.com/dimforge/rapier/issues/543) — "custom forces should be applied through ExternalForce components" recommendation.
- [JSBSim — github.com](https://github.com/JSBSim-Team/jsbsim) — primary repository.
- [JSBSim — Project Site](https://jsbsim-team.github.io/jsbsim/index.html) — "an object-oriented Flight Dynamics Model (FDM) written in C++... designed to support simulation modeling of any aerospace craft without the need for specific compiled and linked program code, instead relying on a versatile and powerful specification written in an XML format."
- [JSBSim — FGAerodynamics class reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGAerodynamics.html) — "This class owns and contains the list of force/coefficients that define the aerodynamic properties of an aircraft." `GetForces()`, `GetMoments()`, etc.
- [JSBSim — DeepWiki overview](https://deepwiki.com/JSBSim-Team/jsbsim/1-jsbsim-overview) — third-party architectural summary; FGFDMExec orchestrator + FGPropagate / FGAerodynamics / FGPropulsion / FGAccelerations modules.
- [JSBSim — Reference Manual PDF](https://jsbsim.sourceforge.net/JSBSimReferenceManual.pdf) — full manual.
- [FlightGear wiki — JSBSim](https://wiki.flightgear.org/JSBSim) — integration into FlightGear.
- [FlightGear wiki — YASim](https://wiki.flightgear.org/YASim) — solver-based alternative FDM.
- [FlightGear wiki — JSBSim vs YASim](https://wiki.flightgear.org/JSBSim_vs_YASim) — "The FDM system in FlightGear is one of the most modular abstractions using the property tree at the moment, so that the corresponding components (jsbsim and yasim) actually are distinct, and may even run standalone, even as a separate process."
- [MSFS 2024 SDK — aircraft.cfg reference](https://docs.flightsimulator.com/msfs2024/html/5_Content_Configuration/CFG_Files/aircraft_cfg.htm) — "provides general information about the aircraft and its variations to the simulation."
- [MSFS 2020 SDK — flight_model.cfg reference](https://docs.flightsimulator.com/html/Content_Configuration/SimObjects/Aircraft_SimO/flight_model_cfg.htm) — "an optional aircraft file for defining the flight model of the aircraft."
- [MSFS 2024 SDK — SimConnect SDK](https://docs.flightsimulator.com/msfs2024/html/6_Programming_APIs/SimConnect/SimConnect_SDK.htm) — out-of-process client/server API for interacting with the simulator.
- [Falcon BMS — FM Part 2: The Development of the Physics Engine](https://www.falcon-bms.com/articles/flight-model/the-development-of-the-physics-engine/) — "The new FM code was developed to be completely autonomous from F4, with the new code fed values coming from F4 (atmosphere, terrain, weapons, fuel, etc) and exporting output values into the F4 code."
- [Falcon BMS — FM Part 3: The Aero Module](https://www.falcon-bms.com/articles/flight-model/the-aero-module/) — Aero module sourced from NASA Technical Paper 1538.
- [Falcon BMS — FM Part 6: The Mechanical Module](https://www.falcon-bms.com/articles/flight-model/the-mechanical-module/) — companion module describing mass/inertia.
- [Mick West — Evolve Your Hierarchy](https://cowboyprogramming.com/2007/01/05/evolve-your-heirachy/) — foundational essay on moving from inheritance to components in game engines, written from his Tony Hawk experience at Neversoft. Specifically addresses physics: "Not every object needs to be able to [react under physics as a rigid body]."
- [Robert Nystrom — Game Programming Patterns: Component](https://gameprogrammingpatterns.com/component.html) — the canonical book chapter; the Bjorn-the-baker example explicitly tackles the input/physics/graphics-tangled-together problem.
- [Game Engine Architecture (Jason Gregory) — book listing](https://www.routledge.com/Game-Engine-Architecture-Third-Edition/Gregory/p/book/9781138035454) — Chapter 13 (Collision and Rigid-Body Dynamics) and Chapter 16 (Gameplay Foundation System / runtime object models).
- [Game Developer (Megan Fox 2010) — Game Engines 101: The Entity/Component Model](https://www.gamedeveloper.com/programming/game-engines-101-the-entity-component-model) — practical introduction; "abolish the idea of an object."
- [Wikipedia — Entity component system](https://en.wikipedia.org/wiki/Entity_component_system) — thin-entity / fat-system definition.
- [SnapNet — Unreal SDK Create a character entity guide](https://www.snapnet.dev/docs/unreal-engine-sdk/guides/create-a-character-entity/) — networked-rollback example of simulation/presentation split with `UCharacterMovementComponent`.
- [Stevens, Lewis & Johnson — Aircraft Control and Simulation, 3rd ed.](https://www.amazon.com/Aircraft-Control-Simulation-Dynamics-Autonomous/dp/1118870980) — textbook whose Appendix F-16 model is the basis for vazgriz's Unity F-16 port.
- [Appendix A: F-16 Model — Wiley Online Library](https://onlinelibrary.wiley.com/doi/10.1002/9781119174882.app1) — appendix excerpt.
