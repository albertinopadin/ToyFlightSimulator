// Faithful CPU model of the afterburner particle recycle dynamics
// (ParticleEmitter.emit + compute_particle at d2c14a9), 1-D along the plume axis.
//
// Cadence model (FlightboxWithPhysics, macOS defaults):
//   - 120 fps (MacGameUIView default .FPS_120), dt jitter + occasional hitches
//   - TWO Afterburner instances share the static emitter:
//       * emit() runs twice per update tick (2 x birthRate 20 = 40 spawns/tick)
//       * compute_particle dispatches twice per frame with the SAME dt
//         (shared simulation advances 2*dt per frame)
//   - pool 10_000, speed 100 m/s, life 0.1 s, spawn z0 in ±0.1,
//     direction z-lane in 0.95...1.05 (per-lane spread, unnormalized)
//
// Variants:
//   A baseline           expiry: age = 0, pos = z0          (current kernel)
//   B F1                 expiry: age = fmod(age, life), pos = z0 + v*age
//   C F1+F2              + life spread ±0.02 s at spawn
//   D F1+F2+F3           + spawn age ~ U[0, life), pos pre-integrated
//   E F2 only            life spread, but expiry age = 0
//   F F3 only            spawn phase, but expiry age = 0
//   G baseline @60fps    variant A with dt base 1/60
//   H F1+F2+F3 @60fps    variant D with dt base 1/60
//
// Metrics on born particles at wall-clock snapshots:
//   phases   = count of distinct ages (rounded to 0.1 ms)
//   coverage = % of 0.25 m bins occupied in [0, 10] m (40 bins)
//   maxClump = % of particles in the single densest 0.25 m bin

import Foundation

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct Config {
    var name: String
    var baseFPS: Double
    var carryRemainder: Bool   // F1
    var lifeSpread: Float      // F2: life = 0.1 + U[-s, s]
    var spawnPhase: Bool       // F3
}

let POOL = 10_000
let BIRTH = 20
let INSTANCES = 2            // two Afterburners sharing the static emitter
let SPEED: Float = 100
let LIFE: Float = 0.1
let SIM_SECONDS = 30.0
let SNAPSHOTS: [Double] = [1, 2, 3, 5, 10, 20, 30]

struct Particle {
    var z: Float = 0
    var z0: Float = 0
    var v: Float = 0          // speed * direction.z (direction unnormalized)
    var age: Float = 0
    var life: Float = 0
}

func gaussian(_ rng: inout SplitMix64, sigma: Double) -> Double {
    let u1 = Double.random(in: 1e-12..<1, using: &rng)
    let u2 = Double.random(in: 0..<1, using: &rng)
    return sigma * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
}

func run(_ cfg: Config) {
    var rng = SplitMix64(state: 0xF22_AB)
    var pool = [Particle](repeating: Particle(), count: POOL)
    var born = 0
    var wall = 0.0
    var nextSnap = 0
    print("\n=== \(cfg.name) ===")
    print("   t(s)  born   phases  coverage  maxClump")

    while wall < SIM_SECONDS {
        // --- frame dt (both dispatches of the frame share it) ---
        var dt = 1.0 / cfg.baseFPS + gaussian(&rng, sigma: 0.0004)
        if Double.random(in: 0..<1, using: &rng) < 0.003 { dt = 0.025 }  // hitch
        dt = min(max(dt, 0.004), 0.030)
        let fdt = Float(dt)
        wall += dt

        // --- update tick: emit() per instance ---
        for _ in 0..<INSTANCES {
            guard born < POOL else { break }
            let batch = min(BIRTH, POOL - born)
            for i in born..<(born + batch) {
                var p = Particle()
                p.z0 = Float.random(in: -0.1...0.1, using: &rng)
                p.v = SPEED * Float.random(in: 0.95...1.05, using: &rng)
                p.life = LIFE + (cfg.lifeSpread > 0
                                 ? Float.random(in: -cfg.lifeSpread...cfg.lifeSpread, using: &rng)
                                 : 0)
                if cfg.spawnPhase {
                    p.age = Float.random(in: 0..<max(p.life, .ulpOfOne), using: &rng)
                    p.z = p.z0 + p.v * p.age
                } else {
                    p.age = 0
                    p.z = p.z0
                }
                pool[i] = p
            }
            born += batch
        }

        // --- render frame: one dispatch per instance, same dt ---
        for _ in 0..<INSTANCES {
            for i in 0..<born {
                var p = pool[i]
                if cfg.carryRemainder {
                    p.age += fdt
                    if p.age > p.life && p.life > 0 {
                        p.age = fmodf(p.age, p.life)
                        p.z = p.z0 + p.v * p.age
                    } else {
                        p.z += p.v * fdt
                    }
                } else {
                    // current kernel order: integrate, then reset-to-zero
                    p.z += p.v * fdt
                    p.age += fdt
                    if p.age > p.life {
                        p.z = p.z0
                        p.age = 0
                    }
                }
                pool[i] = p
            }
        }

        // --- snapshot metrics ---
        if nextSnap < SNAPSHOTS.count && wall >= SNAPSHOTS[nextSnap] {
            nextSnap += 1
            var phases = Set<Int>()
            var bins = [Int](repeating: 0, count: 48)
            for i in 0..<born {
                phases.insert(Int((pool[i].age * 10_000).rounded()))
                let b = Int(pool[i].z / 0.25)
                if b >= 0 && b < 48 { bins[b] += 1 }
            }
            let covered = bins[0..<40].filter { $0 > 0 }.count
            let maxClump = born > 0 ? Double(bins.max() ?? 0) / Double(born) : 0
            print(String(format: "  %5.1f  %5d  %6d  %6.0f%%  %7.1f%%",
                         wall, born, phases.count,
                         100.0 * Double(covered) / 40.0, 100.0 * maxClump))
        }
    }
}

let variants: [Config] = [
    Config(name: "A baseline (age=0, fixed life) @120fps", baseFPS: 120, carryRemainder: false, lifeSpread: 0,    spawnPhase: false),
    Config(name: "B F1 fmod remainder @120fps",            baseFPS: 120, carryRemainder: true,  lifeSpread: 0,    spawnPhase: false),
    Config(name: "C F1+F2 life ±0.02 @120fps",             baseFPS: 120, carryRemainder: true,  lifeSpread: 0.02, spawnPhase: false),
    Config(name: "D F1+F2+F3 spawn phase @120fps",         baseFPS: 120, carryRemainder: true,  lifeSpread: 0.02, spawnPhase: true),
    Config(name: "E F2 only (age=0 reset) @120fps",        baseFPS: 120, carryRemainder: false, lifeSpread: 0.02, spawnPhase: false),
    Config(name: "F F3 only (age=0 reset) @120fps",        baseFPS: 120, carryRemainder: false, lifeSpread: 0,    spawnPhase: true),
    Config(name: "G baseline @60fps",                      baseFPS: 60,  carryRemainder: false, lifeSpread: 0,    spawnPhase: false),
    Config(name: "H F1+F2+F3 @60fps",                      baseFPS: 60,  carryRemainder: true,  lifeSpread: 0.02, spawnPhase: true),
]

for v in variants { run(v) }
