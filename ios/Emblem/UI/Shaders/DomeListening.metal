#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "ListeningWash.h"
using namespace metal;

static float softStep(float x) {
    return 0.5 + 0.5 * tanh(clamp(x, -8.0, 8.0));
}

static float domeDistance(float2 position, float3 circle, thread float2 &n) {
    float2 v = position - circle.xy;
    float dist = max(length(v), 0.001);
    n = v / dist;
    return circle.z - dist;
}

[[ stitchable ]] half4 domeLens(float2 position, SwiftUI::Layer layer, float2 size,
                                float3 circle, float amount, float washLuma,
                                float tintTime, float tintOffset, float tintLevel, float top,
                                float time, float breathe, float3 tint) {
    if (amount <= 0.001) return half4(0.0);
    float2 screen = position + float2(0.0, top);
    float2 bounds = float2(size.x, size.y - top) - float2(0.5);
    float2 n;
    float d = domeDistance(screen, circle, n);
    if (d <= -24.0) return half4(0.0);

    float2 disp = -n * 6.0 * exp(-max(d, 0.0) / 90.0) * smoothstep(-4.0, 20.0, d);
    half4 c = layer.sample(clamp(position + disp, float2(0.5), bounds));
    float frost = softStep((d - 1.0) / 10.0);
    if (washLuma > 0.5) {
        float3 wash = mix(generationWash(screen, size, tintTime, tintOffset, tint, 1),
                          generationWashBase(tintTime, tintOffset, tint, 1), frost);
        c.rgb *= half3(mix(float3(1.0), listeningWash(wash, tintTime), tintLevel));
    }
    c.rgb = mix(c.rgb, half3(washLuma) * c.a, half(0.62 * frost * amount));
    return c * half(softStep((d + 3.0) / 5.0) * amount);
}

[[ stitchable ]] half4 domeRim(float2 position, SwiftUI::Layer layer, float2 size,
                               float3 circle, float amount, float washLuma,
                               float tintTime, float tintOffset, float tintLevel, float top,
                               float time, float breathe, float3 tint) {
    if (amount <= 0.001) return half4(0.0);
    float2 screen = position + float2(0.0, top);
    float2 n;
    float d = domeDistance(screen, circle, n);
    if (d <= -42.0 || d >= 6.0) return half4(0.0);
    float bend = exp(-(d / 18.0) * (d / 18.0)) * amount;
    half4 c = layer.sample(clamp(position - n * 14.0 * bend, float2(0.5),
                                 float2(size.x, size.y - top) - float2(0.5)));
    if (washLuma > 0.5) {
        float3 wash = listeningWash(generationWash(screen, size, tintTime, tintOffset, tint, 1), tintTime);
        c.rgb *= half3(mix(float3(1.0), wash, tintLevel));
    }
    return c * half(smoothstep(-42.0, -28.0, d));
}
