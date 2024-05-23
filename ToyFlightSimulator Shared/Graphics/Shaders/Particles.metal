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

kernel void compute_particle(device Particle *particles [[ buffer(0) ]],
                             uint id [[ thread_position_in_grid ]]) {
    float xVelocity = particles[id].speed * cos(particles[id].direction);
    float yVelocity = particles[id].speed * sin(particles[id].direction);
    
    particles[id].position.x += xVelocity;
    particles[id].position.y += yVelocity;
    particles[id].position.z += xVelocity;  // TODO
    particles[id].age += 1.0;
    
    float age = particles[id].age / particles[id].life;
    particles[id].scale = mix(particles[id].startScale, particles[id].endScale, age);
    
    if (particles[id].age > particles[id].life) {
        particles[id].position = particles[id].startPosition;
        particles[id].age = 0;
        particles[id].scale = particles[id].startScale;
    }
}

vertex ParticleVertexOut vertex_particle(const device Particle *particles [[ buffer(0) ]],
                                         constant float3 &size [[ buffer(1) ]],
                                         constant float3 &emitterPosition [[ buffer(2) ]],
                                         constant SceneConstants &sceneConstants [[ buffer(TFSBufferIndexSceneConstants) ]],
                                         constant ModelConstants &modelConstants [[ buffer(TFSBufferModelConstants) ]],
                                         uint instance [[ instance_id ]]) {
//    float3 position = particles[instance].position + emitterPosition;
//    ParticleVertexOut out {
//        .position = float4(position.xyz / size * 2.0 - 1.0, 1),
//        .pointSize = particles[instance].size * particles[instance].scale,
//        .color = particles[instance].color
//    };
    
    float4 particlePosition = float4(particles[instance].position + emitterPosition, 1);
    float4 position = sceneConstants.projectionMatrix * sceneConstants.viewMatrix * modelConstants.modelMatrix * particlePosition;
    ParticleVertexOut out {
        .position = (position / float4(size, 1)) * 2.0 - 1.0,
        .pointSize = particles[instance].size * particles[instance].scale,
        .color = particles[instance].color
    };
    
    return out;
}

//fragment float4 fragment_particle(ParticleVertexOut in [[ stage_in ]],
//                                  texture2d<float> particleTexture [[ texture(0) ]],
//                                  float2 point [[ point_coord ]]) {
//    constexpr sampler defaultSampler;
//    float4 color = particleTexture.sample(defaultSampler, point);
//    
//    if (color.a < 0.1) {
//        discard_fragment();
//    }
//    
//    color = float4(color.xyz, 0.5);
//    color *= in.color;
//    return color;
//}

fragment float4 fragment_particle(ParticleVertexOut in [[ stage_in ]],
                                  texture2d<float> baseTexture [[ texture(TFSTextureIndexBaseColor) ]],
                                  texture2d<float> particleTexture [[ texture(TFSTextureIndexParticle) ]],
                                  float2 point [[ point_coord ]]) {
    constexpr sampler defaultSampler;
    float4 color = particleTexture.sample(defaultSampler, point);
    float4 baseColor = baseTexture.sample(defaultSampler, point);
    
    if (color.a < 0.1) {
        return baseColor;
    }
    
    color = float4(color.xyz, 0.5);
    color *= in.color;
    return color;
}
