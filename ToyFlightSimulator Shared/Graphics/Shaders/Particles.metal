//
//  Particles.metal
//  ToyFlightSimulator
//
//  Created by Albertino Padin on 4/13/24.
//

#include <metal_stdlib>
using namespace metal;

#import "TFSCommon.h"

struct ParticleVertexOut {
    float4 position [[ position ]];
    float pointSize [[ point_size ]];
    float4 color;
};

// deltaTime is the update tick's frame delta in seconds (C11): descriptor
// speed/life are physical units (m/s, seconds), so the simulation advances at
// the same rate regardless of frame rate.
kernel void compute_particle(device Particle *particles [[ buffer(0) ]],
                             constant float &deltaTime [[ buffer(1) ]],
                             uint id [[ thread_position_in_grid ]]) {
    // One coalesced device→thread load instead of ~14 per-field reads (P5).
    Particle p = particles[id];
    float3 pVelocity = p.speed * p.direction;
    p.age += deltaTime;

    if (p.age > p.life && p.life > 0.0f) {
        // Expiry: carry the phase remainder — NEVER reset age to exactly 0.
        // age = 0 merges every particle that expires in the same frame onto
        // one shared phase forever (identical steps + identical lives never
        // re-separate), which collapses the whole pool into a few strobing
        // clumps within seconds of pool saturation — see
        // debugging/claude/afterburner_plume_strobing_collapse.md. fmod keeps
        // each particle's fractional phase and also absorbs a multi-life
        // hitch (deltaTime > life) in one step. Re-enter at the phase-correct
        // offset, not at the nozzle: position stays exactly on
        // position == startPosition + velocity·age (spawns start on it at
        // age = 0), so integration drift also self-corrects once per cycle.
        p.age = fmod(p.age, p.life);
        p.position = p.startPosition + pVelocity * p.age;
    } else {
        p.position += pVelocity * deltaTime;
    }

    // life == 0 (never-emitted slot) short-circuits to t = 0 instead of
    // inf/NaN. Such slots aren't dispatched since the live-prefix fix
    // (ParticleEmitterObject.computeUpdate); the guard keeps them harmless if
    // the dispatch width ever regresses to the whole pool — it replaces the
    // old order-dependent scale-then-reset containment.
    float t = (p.life > 0.0f) ? (p.age / p.life) : 0.0f;
    p.scale = mix(p.startScale, p.endScale, t);

    // Write back only the mutated fields, not the whole struct: emit() (update
    // thread) writes fresh spawns into this same shared buffer while earlier
    // frames' dispatches are still in flight. Live-prefix dispatch shrinks that
    // window (an in-flight grid encoded with an older, smaller count never
    // covers the slots emit() is filling) but doesn't close it: off() → reset()
    // → on() within the ≤3 frames-in-flight window respawns into LOW indices
    // that still-executing grids DO cover. A whole-struct store losing that
    // race would stomp the spawn's CPU-only fields (direction/speed/life/
    // color/...) with stale pre-spawn data, permanently deadening the slot;
    // racing on {position, age, scale} matches the old per-field write set and
    // self-heals on the next pass.
    particles[id].position = p.position;
    particles[id].age = p.age;
    particles[id].scale = p.scale;
}

vertex ParticleVertexOut vertex_particle(const device Particle *particles [[ buffer(0) ]],
                                         constant float3 &emitterPosition [[ buffer(2) ]],
                                         constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                         constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                         uint instance [[ instance_id ]]) {
    float4 particlePosition = float4(particles[instance].position + emitterPosition, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * modelConstants.modelMatrix * particlePosition;
    ParticleVertexOut out {
        .position = position,
        .pointSize = particles[instance].size * particles[instance].scale,
        .color = particles[instance].color
    };

    return out;
}

fragment float4 fragment_particle(ParticleVertexOut in [[ stage_in ]],
                                  texture2d<float> particleTexture [[ texture(TFSTextureIndexParticle) ]],
                                  float2 point [[ point_coord ]]) {
    constexpr sampler defaultSampler;
    float4 color = particleTexture.sample(defaultSampler, point);

    if (color.a < 0.5) {
        discard_fragment();
    }

    color *= in.color;
    color = float4(color.xyz * 0.9, 1);

    return color;
}

fragment float4 fragment_particle_msaa(ParticleVertexOut    in              [[ stage_in ]],
                                       texture2d_ms<float>  particleTexture [[ texture(TFSTextureIndexParticle) ]],
                                       float2               point           [[ point_coord ]]) {
    float4 color = 0;

    int xCoord = floor(point.x * particleTexture.get_width());
    int yCoord = floor(point.y * particleTexture.get_height());
    uint2 coords = uint2(xCoord, yCoord);

    uint numSamples = particleTexture.get_num_samples();

    for (uint i = 0; i < numSamples; ++i) {
        color += particleTexture.read(coords, i);
    }

    color /= numSamples;

    if (color.a < 0.5) {
        discard_fragment();
    }

    color *= in.color;
    color = float4(color.xyz * 0.9, 1);

    return color;
}
