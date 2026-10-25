#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "ListeningWash.h"
using namespace metal;

static float2 waveOffset(float x, float width, float time, float breathe) {
    float w = max(width, 1.0);
    float a1 = 11.0 + 9.0 * breathe;
    float k1 = 6.2831853 / (w * 0.90);
    float p1 = k1 * x + time * 1.55;
    float a2 = 6.0 + 4.0 * breathe;
    float k2 = 6.2831853 / (w * 0.45);
    float p2 = k2 * x - time * 1.05;
    float a3 = 15.0;
    float k3 = 6.2831853 / (w * 1.70);
    float p3 = k3 * x + time * 0.50;
    return float2(a1 * sin(p1) + a2 * sin(p2) + a3 * sin(p3),
                  a1 * k1 * cos(p1) + a2 * k2 * cos(p2) + a3 * k3 * cos(p3));
}

static float3 waveSurface(float2 screen, float3 circle, float width, float time, float breathe, float calm) {
    float2 v = screen - circle.xy;
    float2 wave = waveOffset(screen.x, width, time, breathe) * clamp(circle.z / 220.0, 0.0, 1.0) * (1.0 - 0.85 * calm);
    float arc = clamp(v.x / max(-v.y, circle.z * 0.25), -1.6, 1.6);
    return float3(circle.z - length(v) - wave.x, arc + wave.y, max(circle.z, 1.0));
}

static float waveFrost(float depth) {
    return smoothstep(0.02, 0.16, depth);
}

static half4 waveGlass(half4 c, float2 screen, float2 size, float d, float depth, float amount,
                       float time, float breathe, float washLuma,
                       float tintTime, float tintOffset, float tintLevel, float3 tint) {
    if (washLuma > 0.5) {
        float3 wash = mix(generationWash(screen, size, tintTime, tintOffset, tint, 0),
                          generationWashBase(tintTime, tintOffset, tint, 0), waveFrost(depth));
        c.rgb *= half3(mix(float3(1.0), listeningWash(wash, tintTime), tintLevel));
    }
    float fog = mix(0.16, 0.26, smoothstep(0.15, 0.8, depth)) * smoothstep(0.01, 0.15, depth) * amount;
    c.rgb = mix(c.rgb, half3(washLuma) * c.a, half(fog));
    float glow = exp(-d / 70.0) * (0.03 + 0.12 * breathe);
    float crest = (0.08 + 0.05 * breathe) * exp(-((d - 4.0) / 9.0) * ((d - 4.0) / 9.0));
    c.rgb += half3(mix(float3(1.0), tint * tint, 0.6) * (crest + glow) * amount) * c.a;
    return c;
}

[[ stitchable ]] half4 waveLens(float2 position, SwiftUI::Layer layer, float2 size,
                                  float3 circle, float amount, float washLuma,
                                  float tintTime, float tintOffset, float tintLevel, float top,
                                  float time, float breathe, float calm, float3 tint) {
    if (amount <= 0.001) return half4(0.0);
    float2 screen = position + float2(0.0, top);
    float3 surface = waveSurface(screen, circle, size.x, time, breathe, calm);
    float d = surface.x;
    if (d <= 0.0) return half4(0.0);
    float depth = clamp(d / surface.z, 0.0, 1.0);
    float frost = waveFrost(depth);
    if (frost <= 0.001) return half4(0.0);
    float2 sway = float2(sin(screen.y * 0.045 - time * 1.30) * 3.0,
                         -7.0 * smoothstep(0.0, 0.5, depth) * sin(time * 0.85 + screen.x * 0.010)) * amount;
    half4 c = layer.sample(clamp(position + sway, float2(0.5), float2(size.x, size.y - top) - float2(0.5)));
    c = waveGlass(c, screen, size, d, depth, amount, time, breathe, washLuma,
                  tintTime, tintOffset, tintLevel, tint);
    return c * half(frost * amount);
}

[[ stitchable ]] half4 waveMeniscus(float2 position, SwiftUI::Layer layer, float2 size,
                                          float3 circle, float amount, float washLuma,
                                          float tintTime, float tintOffset, float tintLevel, float top,
                                          float time, float breathe, float calm, float3 tint) {
    if (amount <= 0.001) return half4(0.0);
    float2 screen = position + float2(0.0, top);
    float3 surface = waveSurface(screen, circle, size.x, time, breathe, calm);
    float d = surface.x;
    if (d <= -1.0) return half4(0.0);
    float depth = clamp(d / surface.z, 0.0, 1.0);
    if (waveFrost(depth) >= 0.999) return half4(0.0);

    float bn = max(d, 0.0) / max(size.y * 0.040, 1.0);
    float band = bn * exp(1.0 - bn) * (1.0 - 0.6 * calm);
    float2 disp;
    disp.x = -surface.y * 24.0 * band
           + sin(screen.y * 0.045 - time * 1.30) * 3.0 * (1.0 - band);
    disp.y = -(14.0 + 11.0 * breathe) * band
           - 7.0 * (1.0 - band) * smoothstep(0.0, 0.5, depth) * sin(time * 0.85 + screen.x * 0.010);
    disp *= amount;

    float2 lo = float2(0.5);
    float2 hi = float2(size.x, size.y - top) - float2(0.5);
    half4 g = layer.sample(clamp(position + disp, lo, hi));
    half4 c = half4(layer.sample(clamp(position + disp * 1.045, lo, hi)).r, g.g,
                    layer.sample(clamp(position + disp * 0.955, lo, hi)).b, g.a);
    c = waveGlass(c, screen, size, d, depth, amount, time, breathe, washLuma,
                  tintTime, tintOffset, tintLevel, tint);
    return c * half(smoothstep(-1.0, 1.0, d) * amount);
}

[[ stitchable ]] half4 waveTranscript(float2 position, SwiftUI::Layer layer, float2 size,
                                     float3 circle, float time, float breathe, float calm, float amount) {
    if (amount <= 0.001) return half4(0.0);
    float3 surface = waveSurface(position, circle, size.x, time, breathe, calm);
    float d = surface.x;
    if (d <= 0.0) return half4(0.0);
    float bn = d / max(size.y * 0.040, 1.0);
    float band = bn * exp(1.0 - bn) * (1.0 - 0.6 * calm);
    float2 disp = float2(-surface.y * 24.0 * band, -(14.0 + 11.0 * breathe) * band) * amount;
    half4 c = layer.sample(clamp(position + disp, float2(0.5), size - float2(0.5)));
    return c * half(smoothstep(0.0, 34.0, d) * amount);
}
