#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float4 washBlobs[7] = {
    float4(0.20, 0.22, 0.9, 0.7), float4(0.78, 0.30, 0.7, 1.1),
    float4(0.45, 0.45, 1.0, 0.8), float4(0.15, 0.62, 0.8, 0.9),
    float4(0.85, 0.66, 1.1, 0.7), float4(0.40, 0.82, 0.7, 1.0),
    float4(0.70, 0.92, 0.9, 0.8),
};
constant float4 washPaths[7] = {
    float4(90, 70, 0.0, 1.3), float4(80, 90, 2.1, 0.4), float4(110, 80, 4.0, 2.2),
    float4(70, 100, 1.2, 3.5), float4(90, 80, 3.3, 5.0), float4(100, 70, 5.1, 0.9),
    float4(80, 90, 0.6, 2.8),
};
constant float3 washHues[7] = {
    float3(0.020, 0.050, 0.058), float3(0.050, 0.046, 0.030), float3(0.032, 0.058, 0.044),
    float3(0.050, 0.046, 0.030), float3(0.020, 0.050, 0.058), float3(0.032, 0.058, 0.044),
    float3(0.050, 0.046, 0.030),
};

static float3 washCast(float2 position, float2 size, float time, float3 tint) {
    float t = time * 1.2;
    float3 light = float3(0.0);
    for (int i = 0; i < 7; i++) {
        float4 b = washBlobs[i];
        float4 p = washPaths[i];
        float2 c = float2(b.x * size.x + p.x * sin(t * b.z + p.z),
                          b.y * size.y + p.y * sin(t * b.w + p.w));
        float2 v = position - c;
        light += washHues[i] * 0.5 * exp(-dot(v, v) / (2.0 * 120.0 * 120.0));
    }
    return light * tint;
}

static float3 generationWashBase(float time, float cycleOffset, float3 tint) {
    float3 rest = mix(float3(0.770, 0.766, 0.780), float3(0.762, 0.760, 0.776), smoothstep(1.0, 6.0, time));
    float cycle = fmod(time + cycleOffset, 14.0);
    float3 turn = float3(smoothstep(7.3, 9.6, cycle), smoothstep(6.8, 9.2, cycle),
                         smoothstep(7.3, 9.6, cycle)) * (1.0 - smoothstep(11.5, 14.0, cycle));
    return mix(rest, float3(0.798, 0.797, 0.804), turn) * tint;
}

static float3 generationWash(float2 position, float2 size, float time, float cycleOffset, float3 tint) {
    return clamp(generationWashBase(time, cycleOffset, tint) + washCast(position, size, time, tint), 0.0, 1.0);
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

static float2 domeWave(float x, float width, float time, float breathe) {
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

static float3 domeSurface(float2 screen, float3 circle, float width, float time, float breathe) {
    float2 v = screen - circle.xy;
    float2 wave = domeWave(screen.x, width, time, breathe) * clamp(circle.z / 220.0, 0.0, 1.0);
    float arc = clamp(v.x / max(-v.y, circle.z * 0.25), -1.6, 1.6);
    return float3(circle.z - length(v) - wave.x, arc + wave.y, max(circle.z, 1.0));
}

static float domeFrost(float depth) {
    return smoothstep(0.02, 0.16, depth);
}

static half4 domeGlass(half4 c, float2 screen, float2 size, float d, float depth, float amount,
                       float time, float breathe, float washLuma,
                       float tintTime, float tintOffset, float tintLevel, float3 tint) {
    if (washLuma > 0.5) {
        float3 wash = mix(generationWash(screen, size, tintTime, tintOffset, tint),
                          generationWashBase(tintTime, tintOffset, tint), domeFrost(depth));
        c.rgb *= half3(mix(float3(1.0), listeningWash(wash, tintTime), tintLevel));
    }
    float fog = mix(0.5, 0.74, smoothstep(0.15, 0.8, depth)) * smoothstep(0.01, 0.15, depth) * amount;
    c.rgb = mix(c.rgb, half3(washLuma) * c.a, half(fog));
    float rise = 0.5 + 0.5 * sin(d * 0.055 + time * 2.1);
    float glow = rise * rise * rise * exp(-d / 90.0) * (0.10 + 0.06 * breathe);
    float crest = (0.08 + 0.05 * breathe) * exp(-((d - 4.0) / 9.0) * ((d - 4.0) / 9.0));
    c.rgb += half3(mix(float3(1.0), tint * tint, 0.6) * (crest + glow) * amount) * c.a;
    return c;
}

[[ stitchable ]] half4 liquidLens(float2 position, SwiftUI::Layer layer, float2 size,
                                  float3 circle, float amount, float washLuma,
                                  float tintTime, float tintOffset, float tintLevel, float top,
                                  float time, float breathe, float3 tint) {
    if (amount <= 0.001) return half4(0.0);
    float2 screen = position + float2(0.0, top);
    float3 surface = domeSurface(screen, circle, size.x, time, breathe);
    float d = surface.x;
    if (d <= 0.0) return half4(0.0);
    float depth = clamp(d / surface.z, 0.0, 1.0);
    float frost = domeFrost(depth);
    if (frost <= 0.001) return half4(0.0);
    float2 sway = float2(sin(screen.y * 0.045 - time * 1.30) * 3.0,
                         -7.0 * smoothstep(0.0, 0.5, depth) * sin(time * 0.85 + screen.x * 0.010)) * amount;
    half4 c = layer.sample(clamp(position + sway, float2(0.5), float2(size.x, size.y - top) - float2(0.5)));
    c = domeGlass(c, screen, size, d, depth, amount, time, breathe, washLuma,
                  tintTime, tintOffset, tintLevel, tint);
    return c * half(frost * amount);
}

[[ stitchable ]] half4 liquidLensMeniscus(float2 position, SwiftUI::Layer layer, float2 size,
                                          float3 circle, float amount, float washLuma,
                                          float tintTime, float tintOffset, float tintLevel, float top,
                                          float time, float breathe, float3 tint) {
    if (amount <= 0.001) return half4(0.0);
    float2 screen = position + float2(0.0, top);
    float3 surface = domeSurface(screen, circle, size.x, time, breathe);
    float d = surface.x;
    if (d <= -1.0) return half4(0.0);
    float depth = clamp(d / surface.z, 0.0, 1.0);
    if (domeFrost(depth) >= 0.999) return half4(0.0);

    float bn = max(d, 0.0) / max(size.y * 0.040, 1.0);
    float band = bn * exp(1.0 - bn);
    float2 disp;
    disp.x = -surface.y * 42.0 * band
           + sin(screen.y * 0.045 - time * 1.30) * 3.0 * (1.0 - band);
    disp.y = -(26.0 + 20.0 * breathe) * band
           - 7.0 * (1.0 - band) * smoothstep(0.0, 0.5, depth) * sin(time * 0.85 + screen.x * 0.010);
    disp *= amount;

    float2 lo = float2(0.5);
    float2 hi = float2(size.x, size.y - top) - float2(0.5);
    half4 g = layer.sample(clamp(position + disp, lo, hi));
    half4 c = half4(layer.sample(clamp(position + disp * 1.045, lo, hi)).r, g.g,
                    layer.sample(clamp(position + disp * 0.955, lo, hi)).b, g.a);
    c = domeGlass(c, screen, size, d, depth, amount, time, breathe, washLuma,
                  tintTime, tintOffset, tintLevel, tint);
    return c * half(smoothstep(-1.0, 1.0, d) * amount);
}

[[ stitchable ]] half4 liquidLensTranscriptMask(float2 position, half4 color, float2 size,
                                                float3 circle, float time, float breathe, float amount) {
    if (amount <= 0.001) return half4(0.0);
    return color * half(smoothstep(0.0, 1.0, domeSurface(position, circle, size.x, time, breathe).x));
}

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
                                     float cycleOffset, float3 tint) {
    float lift = 0.0;
    float drift = smoothstep(0.5, 1.4, t);
    float2 glass = glassDrift(position, size, origin, max(t, 0.0)) * drift * 0.35;
    half4 c = tapRipple(clamp(position + glass, float2(0.5), size - float2(0.5)),
                        layer, size, origin, t, lift);
    float time = max(t, 0.0);
    if (light > 0.5) {
        c.rgb *= half3(mix(float3(1.0), generationWash(position, size, time, cycleOffset, tint), wash));
        c.rgb = min(c.rgb * half(1.0 + lift * wash), half3(c.a));
    } else {
        float3 cast = float3(0.022, 0.024, 0.030) * tint + washCast(position, size, time, tint) * 0.5;
        float3 shine = float3(0.80, 0.86, 1.0) * tint * lift;
        c.rgb = c.rgb * half(1.0 - 0.10 * wash) + half3(max(cast + shine, 0.0) * wash) * c.a;
        c.rgb = min(c.rgb, half3(c.a));
    }
    c.rgb = clamp(c.rgb + half3(washDither(position) * wash) * c.a, half3(0.0), half3(c.a));
    return c * half(smoothstep(front, front + band, position.y));
}

[[ stitchable ]] half4 listeningTint(float2 position, half4 color, float2 size,
                                     float time, float cycleOffset, float3 tint) {
    return half4(half3(listeningWash(generationWash(position, size, time, cycleOffset, tint), time)
                       + washDither(position)), 1.0);
}
