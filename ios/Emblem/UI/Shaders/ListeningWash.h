#include <metal_stdlib>
using namespace metal;

static inline int listeningStyle(float style) {
    return style > 0.5 ? 1 : 0;
}

static float3 washCast(float2 position, float2 size, float time, float3 tint, int style) {
    const float4 blobs[7] = {
        float4(0.20, 0.22, 0.9, 0.7), float4(0.78, 0.30, 0.7, 1.1),
        float4(0.45, 0.45, 1.0, 0.8), float4(0.15, 0.62, 0.8, 0.9),
        float4(0.85, 0.66, 1.1, 0.7), float4(0.40, 0.82, 0.7, 1.0),
        float4(0.70, 0.92, 0.9, 0.8),
    };
    const float4 paths[7] = {
        float4(90, 70, 0.0, 1.3), float4(80, 90, 2.1, 0.4), float4(110, 80, 4.0, 2.2),
        float4(70, 100, 1.2, 3.5), float4(90, 80, 3.3, 5.0), float4(100, 70, 5.1, 0.9),
        float4(80, 90, 0.6, 2.8),
    };
    const float3 hues[2][3] = {
        { float3(0.020, 0.050, 0.058), float3(0.050, 0.046, 0.030), float3(0.032, 0.058, 0.044) },
        { float3(0.015, 0.059, 0.056), float3(0.054, 0.053, 0.024), float3(0.029, 0.067, 0.036) },
    };
    const int order[7] = { 0, 1, 2, 1, 0, 2, 1 };
    float t = time * 1.2;
    float3 light = float3(0.0);
    for (int i = 0; i < 7; i++) {
        float4 b = blobs[i];
        float4 p = paths[i];
        float2 c = float2(b.x * size.x + p.x * sin(t * b.z + p.z),
                          b.y * size.y + p.y * sin(t * b.w + p.w));
        float2 v = position - c;
        light += hues[style][order[i]] * 0.5 * exp(-dot(v, v) / (2.0 * 120.0 * 120.0));
    }
    return light * tint;
}

static float3 generationWashBase(float time, float cycleOffset, float3 tint, int style) {
    const float3 rest[2] = { float3(0.770, 0.766, 0.780), float3(0.765, 0.749, 0.799) };
    const float3 settled[2] = { float3(0.762, 0.760, 0.776), float3(0.748, 0.744, 0.796) };
    const float3 turnTo[2] = { float3(0.798, 0.797, 0.804), float3(0.795, 0.793, 0.810) };
    float3 base = mix(rest[style], settled[style], smoothstep(1.0, 6.0, time));
    float cycle = fmod(time + cycleOffset, 14.0);
    float3 turn = float3(smoothstep(7.3, 9.6, cycle), smoothstep(6.8, 9.2, cycle),
                         smoothstep(7.3, 9.6, cycle)) * (1.0 - smoothstep(11.5, 14.0, cycle));
    return mix(base, turnTo[style], turn) * tint;
}

static float3 generationWash(float2 position, float2 size, float time, float cycleOffset, float3 tint, int style) {
    return clamp(generationWashBase(time, cycleOffset, tint, style)
                 + washCast(position, size, time, tint, style), 0.0, 1.0);
}

static float3 listeningWash(float3 wash, float time) {
    return mix(float3(1.0), wash, smoothstep(0.0, 0.12, time));
}

static float washDither(float2 position) {
    float2 cell = floor(position * 3.0);
    float n = fract(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453)
            + fract(sin(dot(cell, float2(93.989, 67.345))) * 24634.6345) - 1.0;
    return n * (2.5 / 255.0);
}
