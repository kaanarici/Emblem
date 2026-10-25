#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "ListeningWash.h"
using namespace metal;

constant float rippleEnd = 0.9;

static half4 tapRipple(float2 position, SwiftUI::Layer layer, float2 size,
                       float2 origin, float t, thread float &light) {
    light = 0.0;
    if (t <= 0.0 || t >= rippleEnd) return layer.sample(position);
    float age = t + 0.07;
    float2 v = position - origin;
    float d = length(v);
    float2 outward = d > 1.0 ? v / d : float2(0.0, -1.0);

    float wavelength = 220.0;
    float behind = 65.0 + 700.0 * (1.0 - exp(-age / 0.6)) - d;
    float window = smoothstep(0.0, 24.0, behind) * (1.0 - smoothstep(wavelength - 40.0, wavelength, behind));
    float settle = 1.0 - smoothstep(0.6, rippleEnd, t);
    float amplitude = 17.0 * smoothstep(0.0, 0.05, t) * exp(-age / 0.9) * settle;
    float wave = sin(6.2831853 * behind / wavelength);
    float gate = smoothstep(44.0, 104.0, position.y);
    float2 disp = -outward * amplitude * wave * window * gate;
    light = 0.13 * smoothstep(0.0, 90.0, behind) * exp(-max(behind, 0.0) / 520.0)
          * exp(-age / 0.45) * settle * gate;
    return layer.sample(clamp(position + disp, float2(0.5), size - float2(0.5)));
}

static float2 glassDrift(float2 position, float2 size, float2 origin, float time) {
    float2 c1 = float2(size.x * (0.50 + 0.30 * sin(time * 0.33)),
                       size.y * (0.38 + 0.17 * sin(time * 0.21 + 2.0)));
    float2 c2 = float2(size.x * (0.50 + 0.34 * sin(time * 0.27 + 4.2)),
                       size.y * (0.62 + 0.19 * sin(time * 0.40 + 1.1)));
    float r1 = size.x * 0.34;
    float r2 = size.x * 0.42;
    float2 v1 = position - c1;
    float2 v2 = position - c2;
    float g1 = exp(-dot(v1, v1) / (2.0 * r1 * r1));
    float g2 = exp(-dot(v2, v2) / (2.0 * r2 * r2));

    float2 disp = -v1 * g1 * 0.050 - v2 * g2 * 0.042;
    float ky = 6.2831853 / (size.y * 0.62);
    disp.x += 3.5 * sin(position.y * ky - time * 1.6);
    disp.y += 2.5 * cos(position.y * ky * 0.63 + position.x * 0.004 + time * 1.1);
    float fromOrigin = distance(position, origin) / max(length(size), 1.0);
    return disp * (1.0 - smoothstep(0.0, 1.2, fromOrigin) * 0.35)
                * smoothstep(64.0, 176.0, position.y);
}

[[ stitchable ]] half4 generationHold(float2 position, SwiftUI::Layer layer, float2 size,
                                     float2 origin, float t, float light, float wash, float front, float band,
                                     float cycleOffset, float3 tint, float style) {
    int look = listeningStyle(style);
    float lift = 0.0;
    float drift = smoothstep(0.5, 1.4, t);
    float2 glass = glassDrift(position, size, origin, max(t, 0.0)) * drift * 0.35;
    half4 c = tapRipple(clamp(position + glass, float2(0.5), size - float2(0.5)),
                        layer, size, origin, t, lift);
    float time = max(t, 0.0);
    if (light > 0.5) {
        c.rgb *= half3(mix(float3(1.0), generationWash(position, size, time, cycleOffset, tint, look), wash));
        c.rgb = min(c.rgb * half(1.0 + lift * wash), half3(c.a));
    } else {
        const float3 darkCast[2] = { float3(0.022, 0.024, 0.030), float3(0.018, 0.022, 0.034) };
        float3 cast = darkCast[look] * tint + washCast(position, size, time, tint, look) * 0.5;
        float3 shine = float3(0.80, 0.86, 1.0) * tint * lift;
        c.rgb = c.rgb * half(1.0 - 0.10 * wash) + half3(max(cast + shine, 0.0) * wash) * c.a;
        c.rgb = min(c.rgb, half3(c.a));
    }
    c.rgb = clamp(c.rgb + half3(washDither(position) * wash) * c.a, half3(0.0), half3(c.a));
    return c * half(smoothstep(front, front + band, position.y));
}

[[ stitchable ]] half4 listeningTint(float2 position, half4 color, float2 size,
                                     float time, float cycleOffset, float3 tint, float style) {
    return half4(half3(listeningWash(generationWash(position, size, time, cycleOffset, tint, listeningStyle(style)), time)
                       + washDither(position)), 1.0);
}

[[ stitchable ]] half4 listeningSnapshot(float2 position, half4 color, float2 size,
                                         float time, float cycleOffset, float3 tint, float style) {
    float3 wash = listeningWash(generationWash(position, size, time, cycleOffset, tint, listeningStyle(style)), time)
                + washDither(position);
    return half4(color.rgb * half3(wash), color.a);
}
