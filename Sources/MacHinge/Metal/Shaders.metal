#include <metal_stdlib>
using namespace metal;

constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);

// =========================================================================
// DUOHINGE PHYSICAL OPTICAL GLASS SHADER (DuoHinge/Shaders/HingeGlass.metal)
// =========================================================================

struct HingeUniforms {
    float4 geometry; // point width, point height, progress, blur
    float4 optics;   // darkness, chromatic strength, unused, unused
    float4 eye;      // eye.x, eye.y, eye.z, unused
};

struct HingeVertex {
    float4 position [[position]];
    float2 uv;
};

vertex HingeVertex hingeVertex(uint index [[vertex_id]]) {
    float2 uv = float2((index << 1) & 2, index & 2);
    return {float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1), uv};
}

half4 hingeGlass(float2 position, texture2d<half> layer, float4 bounds, float progress, float blurStrength, float darknessStrength, float3 viewpoint) {
    float2 size = bounds.zw;
    float2 p = position - bounds.xy;
    float fullAngle = clamp(progress, 0.0f, 1.0f) * M_PI_F * 0.5f;
    // An exact passthrough at the reference angle avoids a color/geometry jump.
    if (fullAngle < 1e-5f) return half4(layer.sample(linearSampler, (position) / bounds.zw).rgb, 1.0h);
    // Delayed, wider curtain: never extinguish the desktop. At full closure
    // the top retains 40% transmission and the bottom retains even more.
    float curtainProgress = smoothstep(0.02f, 1.0f, clamp(progress, 0.0f, 1.0f));
    float feather = 0.22f;
    float edge = mix(-feather, 0.90f, curtainProgress);
    float curtain = 1.0f - smoothstep(edge - feather, edge + feather, p.y / size.y);
    float visibility = 1.0f - min(0.60f * darknessStrength, 0.80f) * curtain;
    // Ease optical scattering smoothly near the reference pose.
    float opticalStrength = smoothstep(0.0f, 0.03f, progress);
    float distance = size.y - p.y;
    // World coordinates: the desktop remains on z=0 at the 90-degree position.
    // Only the physical glass rotates about (y=height, z=0). For each glass
    // pixel, continue the stationary eye's ray to the fixed desktop plane.
    // Screen compression is capped at 0.28 (~25 deg) to match the reference limit,
    // preventing excessive squeezing/collapsing as the lid continues closing.
    float compressionCap = 0.28f;
    float projectionProgress = min(progress, compressionCap);
    float angle = clamp(projectionProgress, 0.0f, 1.0f) * M_PI_F * 0.5f;
    float eyeDistance = size.y * max(viewpoint.z, 1.1f);
    float sine = sin(angle);
    float cosine = cos(angle);
    float3 eye = float3(size.x * viewpoint.x, size.y * viewpoint.y, eyeDistance);
    float3 glass = float3(p.x, size.y - distance * cosine, distance * sine);
    float depth = eye.z - glass.z;
    if (depth <= 1e-5f) return half4(0, 0, 0, 1);
    float rayScale = eye.z / depth;
    float2 hit = eye.xy + (glass.xy - eye.xy) * rayScale;
    float separation = distance * sin(fullAngle);
    // A narrow contact band remains optically clear; scattering increases smoothly
    // with glass separation. Cap the footprint to avoid sparse, ghosted large kernels.
    float contact = smoothstep(size.y * 0.02f, size.y * 0.15f, distance);
    float scatter = separation * 0.080f * contact * opticalStrength * blurStrength;
    // Smooth saturation retains a changing slope instead of abruptly hitting a cap.
    float radius = scatter / sqrt(1.0f + (scatter / 36.0f) * (scatter / 36.0f));
    // Projection is sampled once. The following two passes supply the blur.
    bool inside = all(hit >= 0.0f) && all(hit < size);
    half3 color = inside ? layer.sample(linearSampler, (bounds.xy + hit) / bounds.zw).rgb : half3(0);
    float transmission = 1.0f - min(radius * 0.0004f, 0.015f);
    return half4(color * half(transmission * visibility), 1.0h);
}

// Separable Gaussian in display coordinates. Two dense 1D passes avoid sparse
// disk replicas of fine text. Adjacent weights share a bilinear texture read.
half4 hingeGaussian(float2 position, texture2d<half> layer,
                    float4 bounds, float progress, float2 direction, float blurStrength) {
    float2 size = bounds.zw;
    float2 p = position - bounds.xy;
    float distance = size.y - p.y;
    float contact = smoothstep(size.y * 0.02f, size.y * 0.15f, distance);
    float optical = smoothstep(0.0f, 0.03f, progress);
    float scatter = distance * sin(clamp(progress, 0.0f, 1.0f) * M_PI_F * 0.5f)
                  * 0.080f * contact * optical * blurStrength;
    float radius = scatter / sqrt(1.0f + (scatter / 36.0f) * (scatter / 36.0f));
    if (radius < 0.10f) return half4(layer.sample(linearSampler, (position) / bounds.zw).rgb, 1);
    float sigma = max(radius / 2.44948974f, 0.15f);
    float inverseVariance = 0.5f / (sigma * sigma);
    float3 sum = float3(layer.sample(linearSampler, (position) / bounds.zw).rgb);
    float total = 1.0f;
    for (int i = 1; i <= 35; i += 2) {
        float a = float(i), b = a + 1.0f;
        float wa = exp(-a * a * inverseVariance);
        float wb = exp(-b * b * inverseVariance);
        float weight = wa + wb;
        if (weight < 1e-7f) continue;
        float offset = (a * wa + b * wb) / weight;
        for (int side = -1; side <= 1; side += 2) {
            // Extend the edge rather than introducing a dark sampling border.
            float2 q = clamp(p + direction * (float(side) * offset),
                             float2(0.0f), max(size - 0.5f, float2(0.0f)));
            sum += float3(layer.sample(linearSampler, (bounds.xy + q) / bounds.zw).rgb) * weight;
        }
        total += 2.0f * weight;
    }
    return half4(half3(sum / total), 1);
}

// NameDrop-inspired dispersion, not a reproduction of Apple's implementation.
// Applied after blur in display coordinates; the fixed-plane projection is unchanged.
half4 hingeChromatic(float2 position, texture2d<half> layer,
                     float4 bounds, float progress, float strength) {
    half4 center = layer.sample(linearSampler, (position) / bounds.zw);
    float closing = clamp(progress, 0.0f, 1.0f);
    if (strength <= 0.0f || closing <= 0.0f) return center;

    float2 size = max(bounds.zw, float2(1.0f));
    float2 p = position - bounds.xy;
    float heightFromHinge = clamp((size.y - p.y) / size.y, 0.0f, 1.0f);
    float contact = smoothstep(0.02f, 0.15f, heightFromHinge);
    float onset = smoothstep(0.0f, 0.04f, closing);
    float amount = min(size.y * 0.009f, 10.0f) * clamp(strength, 0.0f, 1.0f)
                 * sin(closing * M_PI_F * 0.5f) * onset * contact
                 * pow(heightFromHinge, 1.35f);
    if (amount < 0.001f) return center;

    // Radial dispersion around the bottom-center hinge. The narrow contact band
    // stays neutral; separation grows toward the top and outer edges.
    float2 radial = float2((p.x / size.x - 0.5f) * 0.65f, -heightFromHinge);
    float2 offset = radial / max(length(radial), 0.0001f) * amount;
    float2 upper = max(size - 0.5f, float2(0.0f));
    float2 redPosition = bounds.xy + clamp(p + offset, float2(0.0f), upper);
    float2 bluePosition = bounds.xy + clamp(p - offset, float2(0.0f), upper);
    // Extend the edge instead of introducing colored transparency fringes.
    return half4(layer.sample(linearSampler, (redPosition) / bounds.zw).r, center.g, layer.sample(linearSampler, (bluePosition) / bounds.zw).b, center.a);
}

fragment half4 hingeProject(HingeVertex in [[stage_in]], texture2d<half> source [[texture(0)]],
                            constant HingeUniforms &u [[buffer(0)]]) {
    return hingeGlass(in.uv * u.geometry.xy, source, float4(0, 0, u.geometry.xy),
                      u.geometry.z, u.geometry.w, u.optics.x, u.eye.xyz);
}

fragment half4 hingeBlurX(HingeVertex in [[stage_in]], texture2d<half> source [[texture(0)]],
                          constant HingeUniforms &u [[buffer(0)]]) {
    return hingeGaussian(in.uv * u.geometry.xy, source, float4(0, 0, u.geometry.xy),
                         u.geometry.z, float2(1, 0), u.geometry.w);
}

fragment half4 hingeBlurY(HingeVertex in [[stage_in]], texture2d<half> source [[texture(0)]],
                          constant HingeUniforms &u [[buffer(0)]]) {
    return hingeGaussian(in.uv * u.geometry.xy, source, float4(0, 0, u.geometry.xy),
                         u.geometry.z, float2(0, 1), u.geometry.w);
}

fragment half4 hingeDispersion(HingeVertex in [[stage_in]], texture2d<half> source [[texture(0)]],
                               constant HingeUniforms &u [[buffer(0)]]) {
    return hingeChromatic(in.uv * u.geometry.xy, source, float4(0, 0, u.geometry.xy),
                          u.geometry.z, u.optics.y);
}

// =========================================================================
// LUMINOUS WAKE & MAGNETIC LENS SHADERS
// =========================================================================

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct FoldUniforms {
    float progress;         // 0.0 (preferred viewing angle = 100% normal) -> 1.0 (fully folded)
    float angleDegrees;     // Physical lid angle in degrees
    float angularVelocity;  // Deg/s
    float time;             // Running time in seconds
    float2 resolution;      // Viewport resolution in pixels
    float hingePosition;    // Normalized vertical position of hinge (1.0 = bottom)
    float curvature;        // Curvature strength
    float perspective;      // Perspective foreshortening strength
    float blurIntensity;    // Blur intensity
    float glowIntensity;    // Wake/fold glow radiance
    float effectStyle;      // 0.0 = DuoHinge Optical Glass, 1.0 = Luminous Wake Glow, 2.0 = Magnetic Lens
};

vertex VertexOut duoVertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 duoFoldFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant FoldUniforms &uniforms [[buffer(0)]]
) {
    float p = clamp(uniforms.progress, 0.0, 1.0);
    float2 uv = in.uv;

    if (p <= 0.0001) {
        return inputTexture.sample(textureSampler, uv);
    }

    float v = uv.y;
    float u = uv.x;
    float distFromHinge = 1.0 - v;

    float perspectiveStrength = min(uniforms.perspective, 0.12);
    float perspectiveFactor = pow(p, 1.1) * perspectiveStrength;
    float taperFactor = 1.0 - (perspectiveFactor * distFromHinge);
    float centeredU = (u - 0.5) / max(0.001, taperFactor) + 0.5;

    float3 backdropRGB = float3(0.02, 0.02, 0.025);

    if (centeredU < 0.0 || centeredU > 1.0) {
        return float4(backdropRGB, 1.0);
    }

    float curvatureStrength = min(uniforms.curvature, 0.35);
    float curveFactor = pow(p, 1.05) * curvatureStrength;
    float compressionExponent = 1.0 + (0.25 * curveFactor);
    float sourceV = 1.0 - pow(distFromHinge, 1.0 / max(0.05, compressionExponent));

    float hingeRollover = smoothstep(0.72, 1.0, v) * (0.015 * p * sin(v * 3.14159));
    sourceV = clamp(sourceV + hingeRollover, 0.0, 1.0);

    float2 sourceUV = float2(centeredU, sourceV);
    float velocity = uniforms.angularVelocity;
    float speed = abs(velocity);

    float4 color = float4(0.0);

    if (uniforms.effectStyle > 1.5) {
        // MAGNETIC LENS DISTORTION & CHROMATIC GRAVITATIONAL WARP
        float lensProg = clamp(p, 0.0, 1.0);
        float lensTiming = pow(lensProg, 0.95);

        float2 pole = float2(0.5, 1.05);
        float2 toPole = sourceUV - pole;
        float distToPole = length(toPole);

        float fieldStrength = lensTiming * 0.38;
        float deflection = fieldStrength / (distToPole * 2.0 + 0.30);
        float2 warpedUV = sourceUV - normalize(toPole) * (deflection * 0.25);

        float angle = atan2(toPole.y, toPole.x) + (velocity * 0.020 * lensTiming / (distToPole + 0.20));
        float2 swirl = float2(cos(angle), sin(angle)) * distToPole - toPole;
        warpedUV += swirl * 0.35;

        float dispersion = 0.012 * lensTiming;
        float2 redUV = clamp(warpedUV + normalize(toPole) * dispersion, float2(0.0005), float2(0.9995));
        float2 greenUV = clamp(warpedUV, float2(0.0005), float2(0.9995));
        float2 blueUV = clamp(warpedUV - normalize(toPole) * dispersion, float2(0.0005), float2(0.9995));

        float r = inputTexture.sample(textureSampler, redUV).r;
        float g = inputTexture.sample(textureSampler, greenUV).g;
        float b = inputTexture.sample(textureSampler, blueUV).b;
        color = float4(r, g, b, 1.0);

        float ringPhase = sin(distToPole * 42.0 - uniforms.time * 2.0);
        float fluxCaustic = pow(max(0.0, ringPhase), 8.0) * 0.12 * lensTiming;
        color.rgb += float3(0.35, 0.65, 1.0) * fluxCaustic;
    } else {
        color = inputTexture.sample(textureSampler, sourceUV);
    }

    float3 frostedRGB = color.rgb * (1.0 + (0.04 * p));
    float ambientOcclusion = 1.0 - (0.20 * pow(p, 1.2) * exp(-distFromHinge * 4.0));
    float highlightDist = abs(v - (1.0 - (0.025 * (1.0 - p))));
    float specular = (0.08 * (p * p)) * exp(-highlightDist * 90.0);

    float edgeDist = min(centeredU, 1.0 - centeredU);
    float edgeAlpha = smoothstep(0.0, 0.012, edgeDist);

    // LUMINOUS WAKE & FOLD GLOW
    float3 glowLayer = float3(0.0);
    if (uniforms.effectStyle > 0.5 && uniforms.effectStyle < 1.5) {
        float glowProg = clamp(p, 0.0, 1.0);
        float glowTiming = pow(glowProg, 0.95);

        float floodBloom = glowTiming * 1.6;
        float flowPosition = 1.0 - (0.55 * p);
        float lightFlow = exp(-pow((v - flowPosition), 2.0) * 8.0) * glowTiming * 1.5;

        float creaseGlow = exp(-abs(v - (1.0 - 0.20 * p)) * 5.0) * glowTiming * 1.7;
        float edgeHalo = pow(max(0.0, 1.0 - edgeDist * 2.5), 2.0) * glowTiming * 1.3;
        float motionSurge = min(speed * 0.15, 0.30) * glowTiming;

        float totalWhiteRadiance = (floodBloom * 0.70 + lightFlow * 0.95 + creaseGlow * 0.85 + edgeHalo * 0.55 + motionSurge * 0.20) * uniforms.glowIntensity;
        float3 pureWhite = float3(1.0, 1.0, 1.0);
        glowLayer = pureWhite * totalWhiteRadiance;
    } else if (uniforms.effectStyle > 1.5) {
        float lensProg = clamp(p, 0.0, 1.0);
        float lensTiming = pow(lensProg, 0.95);
        float magneticHalo = pow(max(0.0, 1.0 - edgeDist * 3.0), 2.0) * lensTiming * 0.55;
        glowLayer = float3(0.25, 0.55, 1.0) * magneticHalo * uniforms.glowIntensity;
    }

    float3 screenRGB = (frostedRGB * ambientOcclusion + specular) + glowLayer;
    float3 finalRGB = mix(backdropRGB, screenRGB, edgeAlpha);

    return float4(finalRGB, 1.0);
}
