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
    float2 ab = in.p1Screen - in.p0Screen;
    float denominator = dot(ab, ab);

    float h = 0.0;
    if (denominator > 0.0) {
        h = clamp(dot(in.fragScreen - in.p0Screen, ab) / denominator, 0.0, 1.0);
    }

    float2 closest = in.p0Screen + h * ab;
    float distanceToCenter = length(in.fragScreen - closest);
    float pressure = labyrinth_interpolate_pressure(in.pressure, h);
    float radius = max(in.baseHalfPixelWidth * labyrinth_pressure_width_multiplier(pressure), 0.0025);

    float edge = max(1.0, radius * 0.08);
    float alpha = 1.0 - smoothstep(radius - edge, radius + edge, distanceToCenter);
    if (alpha <= 0.001) {
        discard_fragment();
    }

    float4 color = in.color;
    color.a *= alpha;
    return color;
}
