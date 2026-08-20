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
    p.position += pVelocity * deltaTime;
    p.age += deltaTime;

    // Scale-then-reset order is load-bearing, don't swap: the reset overwrites
    // scale with startScale, so the expiry frame renders the respawn (never the
    // extrapolated mix) — and the dispatch covers ALL particleCount slots, so
    // never-emitted slots (zero-filled at buffer creation → life == 0) hit
    // inf/NaN in the mix, which this order overwrites before store-back.
    // Resetting first would store NaN (0/0) into those slots' scale.
    float age = p.age / p.life;
    p.scale = mix(p.startScale, p.endScale, age);
    
    if (p.age > p.life) {
        p.position = p.startPosition;
        p.age = 0;
        p.scale = p.startScale;
    }

    // Write back only the mutated fields, not the whole struct: emit() (update
    // thread) writes fresh spawns into this same shared buffer while earlier
    // frames' dispatches are still in flight, and this dispatch covers all
    // particleCount slots, born or not. A whole-struct store losing that race
    // would stomp the spawn's CPU-only fields (direction/speed/life/color/...)
    // with stale pre-spawn data, permanently deadening the slot; racing on
    // {position, age, scale} matches the old per-field write set and self-heals
    // on the next pass.
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
