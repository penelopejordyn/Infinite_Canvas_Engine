#include <metal_stdlib>
using namespace metal;

struct LabyrinthQuadIn {
    float2 corner [[attribute(0)]];
};

struct LabyrinthBatchedStrokeTransform {
    float2 cameraCenterWorld;
    float zoomScale;
    float screenWidth;
    float screenHeight;
    float rotationAngle;
    float featherPx;
    float depthBias;
    float depthScale;
};

struct LabyrinthBatchedSegmentInstance {
    float2 p0World;
    float2 p1World;
    float4 color;
    float4 params;
};

struct LabyrinthBatchedSegmentOut {
    float4 position [[position]];
    float2 fragScreen;
    float2 p0Screen;
    float2 p1Screen;
    float4 color;
    float baseHalfPixelWidth;
    float2 pressure;
};

inline float labyrinth_normalized_pressure(float pressure) {
    return clamp(pressure, 0.0, 1.0);
}

inline float labyrinth_pressure_width_multiplier(float pressure) {
    if (pressure < 0.0) {
        return 1.0;
    }
    float curved = pow(labyrinth_normalized_pressure(pressure), 1.5);
    return 0.6 + curved * (1.8 - 0.6);
}

inline float labyrinth_interpolate_pressure(float2 pressures, float h) {
    bool hasStart = pressures.x >= 0.0;
    bool hasEnd = pressures.y >= 0.0;
    if (hasStart && hasEnd) {
        return mix(labyrinth_normalized_pressure(pressures.x),
                   labyrinth_normalized_pressure(pressures.y),
                   h);
    }
    if (hasStart) {
        return labyrinth_normalized_pressure(pressures.x);
    }
    if (hasEnd) {
        return labyrinth_normalized_pressure(pressures.y);
    }
    return -1.0;
}

vertex LabyrinthBatchedSegmentOut labyrinth_vertex_segment_sdf_batched(
    LabyrinthQuadIn vin [[stage_in]],
    constant LabyrinthBatchedStrokeTransform *t [[buffer(1)]],
    const device LabyrinthBatchedSegmentInstance *instances [[buffer(2)]],
    uint iid [[instance_id]]
) {
    LabyrinthBatchedSegmentInstance seg = instances[iid];

    float2 rel0 = seg.p0World - t->cameraCenterWorld;
    float2 rel1 = seg.p1World - t->cameraCenterWorld;

    float c = cos(t->rotationAngle);
    float s = sin(t->rotationAngle);

    float2 r0 = float2(rel0.x * c - rel0.y * s, rel0.x * s + rel0.y * c);
    float2 r1 = float2(rel1.x * c - rel1.y * s, rel1.x * s + rel1.y * c);

    float2 p0 = r0 * t->zoomScale;
    float2 p1 = r1 * t->zoomScale;

    float2 d = p1 - p0;
    float len = length(d);
    float2 dir = (len > 0.0) ? (d / len) : float2(1.0, 0.0);
    float2 nrm = float2(-dir.y, dir.x);

    float worldWidth = seg.params.x;
    float basePixelWidth = worldWidth * t->zoomScale;
    float baseHalfPixelWidth = basePixelWidth * 0.5;
    float pressureMultiplier = max(labyrinth_pressure_width_multiplier(seg.params.z),
                                   labyrinth_pressure_width_multiplier(seg.params.w));
    float radius = max(baseHalfPixelWidth * pressureMultiplier, 0.0025);

    float x = mix(-radius, len + radius, vin.corner.x);
    float y = mix(-radius, radius, vin.corner.y);
    float2 screenPos = p0 + dir * x + nrm * y;

    float ndcX = (screenPos.x / max(t->screenWidth, 1.0)) * 2.0;
    float ndcY = -(screenPos.y / max(t->screenHeight, 1.0)) * 2.0;
    float depth = t->depthBias + seg.params.y * t->depthScale;

    LabyrinthBatchedSegmentOut out;
    out.position = float4(ndcX, ndcY, depth, 1.0);
    out.fragScreen = screenPos;
    out.p0Screen = p0;
    out.p1Screen = p1;
    out.color = seg.color;
    out.baseHalfPixelWidth = baseHalfPixelWidth;
    out.pressure = seg.params.zw;
    return out;
}

fragment float4 labyrinth_fragment_segment_sdf_batched(
    LabyrinthBatchedSegmentOut in [[stage_in]]
) {
    float2 p = in.fragScreen;
    float2 a = in.p0Screen;
    float2 b = in.p1Screen;

    float2 ab = b - a;
    float denominator = dot(ab, ab);

    float h = 0.0;
    if (denominator > 0.0) {
        h = dot(p - a, ab) / denominator;
        h = clamp(h, 0.0, 1.0);
    }

    float2 closest = a + h * ab;
    float distanceToCenter = length(p - closest);
    float pressure = labyrinth_interpolate_pressure(in.pressure, h);
    float radius = max(in.baseHalfPixelWidth * labyrinth_pressure_width_multiplier(pressure), 0.0025);

    if (distanceToCenter > radius) {
        discard_fragment();
    }

    return in.color;
}

struct LabyrinthPostProcessOut {
    float4 position [[position]];
    float2 uv;
};

struct LabyrinthHoverPostProcessUniforms {
    float4 centerRadius;
    float4 outlineParams;
    float4 handleLight;
    float4 handleDark;
};

inline float4 labyrinth_apply_hover_ring_overlay(float4 baseColor,
                                                 float2 uv,
                                                 constant LabyrinthHoverPostProcessUniforms &hover,
                                                 float2 invResolution) {
    if (hover.outlineParams.z <= 0.0) {
        return baseColor;
    }
    float radius = hover.centerRadius.z;
    if (radius <= 0.0) {
        return baseColor;
    }
    float2 centerPx = hover.centerRadius.xy;
    float2 posPx = uv / invResolution;
    float dist = length(posPx - centerPx);
    float thickness = max(hover.centerRadius.w, 1.0);
    float halfThickness = thickness * 0.5;
    float edge = fabs(dist - radius);
    float ringMask = 1.0 - smoothstep(halfThickness, halfThickness + 1.0, edge);
    if (ringMask <= 0.0) {
        return baseColor;
    }
    constexpr float3 lumaWeights = float3(0.299, 0.587, 0.114);
    float luminance = dot(baseColor.rgb, lumaWeights);
    float3 outlineRGB = (luminance > hover.outlineParams.y) ? hover.handleLight.rgb : hover.handleDark.rgb;
    float alpha = clamp(hover.outlineParams.x, 0.0, 1.0) * ringMask;
    float3 rgb = mix(baseColor.rgb, outlineRGB, alpha);
    return float4(rgb, max(baseColor.a, alpha));
}

vertex LabyrinthPostProcessOut labyrinth_vertex_fullscreen_triangle(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 uv[3] = { float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0) };

    LabyrinthPostProcessOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    out.uv = uv[vid];
    return out;
}

fragment float4 labyrinth_fragment_fxaa(
    LabyrinthPostProcessOut in [[stage_in]],
    texture2d<float> colorTex [[texture(0)]],
    sampler colorSampler [[sampler(0)]],
    constant float2 &invResolution [[buffer(0)]],
    constant LabyrinthHoverPostProcessUniforms &hover [[buffer(1)]]
) {
    float2 uv = in.uv;

    float3 rgbNW = colorTex.sample(colorSampler, uv + float2(-1.0, -1.0) * invResolution).rgb;
    float3 rgbNE = colorTex.sample(colorSampler, uv + float2(1.0, -1.0) * invResolution).rgb;
    float3 rgbSW = colorTex.sample(colorSampler, uv + float2(-1.0, 1.0) * invResolution).rgb;
    float3 rgbSE = colorTex.sample(colorSampler, uv + float2(1.0, 1.0) * invResolution).rgb;
    float4 rgbaM = colorTex.sample(colorSampler, uv);
    float3 rgbM = rgbaM.rgb;

    constexpr float3 lumaWeights = float3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, lumaWeights);
    float lumaNE = dot(rgbNE, lumaWeights);
    float lumaSW = dot(rgbSW, lumaWeights);
    float lumaSE = dot(rgbSE, lumaWeights);
    float lumaM = dot(rgbM, lumaWeights);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    float lumaRange = lumaMax - lumaMin;

    constexpr float edgeThreshold = 0.125;
    constexpr float edgeThresholdMin = 0.0312;
    constexpr float subpixQuality = 0.75;
    constexpr float spanMax = 8.0;
    constexpr float subpixReduceMin = 1.0 / 128.0;
    constexpr float subpixReduceMul = 1.0 / 8.0;

    if (lumaRange < max(edgeThresholdMin, lumaMax * edgeThreshold)) {
        return labyrinth_apply_hover_ring_overlay(rgbaM, uv, hover, invResolution);
    }

    float2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y = ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * subpixReduceMul), subpixReduceMin);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = clamp(dir * rcpDirMin, float2(-spanMax), float2(spanMax)) * invResolution;

    float3 rgbA = 0.5 * (
        colorTex.sample(colorSampler, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
        colorTex.sample(colorSampler, uv + dir * (2.0 / 3.0 - 0.5)).rgb
    );

    float3 rgbB = rgbA * 0.5 + 0.25 * (
        colorTex.sample(colorSampler, uv + dir * -0.5).rgb +
        colorTex.sample(colorSampler, uv + dir * 0.5).rgb
    );

    float lumaB = dot(rgbB, lumaWeights);
    float3 rgbOut = (lumaB < lumaMin || lumaB > lumaMax) ? rgbA : rgbB;

    float lumaAvg = (lumaNW + lumaNE + lumaSW + lumaSE) * 0.25;
    float subpix = clamp(abs(lumaAvg - lumaM) / max(lumaRange, 1e-5), 0.0, 1.0);
    float subpixBlend = subpix * subpixQuality;
    rgbOut = mix(rgbM, rgbOut, subpixBlend);

    return labyrinth_apply_hover_ring_overlay(float4(rgbOut, rgbaM.a), uv, hover, invResolution);
}
