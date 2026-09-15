#include <metal_stdlib>
using namespace metal;

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
    float effectStyle;      // 0.0 = Duo Effect, 1.0 = Luminous Wake Glow
};

// Fullscreen quad vertex shader
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

// MacBook physical lid optical glass transition fragment shader
fragment float4 duoFoldFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]],
    constant FoldUniforms &uniforms [[buffer(0)]]
) {
    float p = clamp(uniforms.progress, 0.0, 1.0);
    float2 uv = in.uv;

    // AT PREFERRED VIEWING ANGLE: STRICT 100% NORMAL, SHARP, BIT-EXACT PASSTHROUGH
    if (p <= 0.0001) {
        return inputTexture.sample(textureSampler, uv);
    }

    float angle = p * (3.14159265f * 0.5f);
    float distFromHinge = 1.0f - uv.y; // 0.0 at bottom hinge, 1.0 at top menu bar

    // =========================================================================
    // 1. STATIONARY DESKTOP PLANE RAYCAST PROJECTION
    // =========================================================================
    // The desktop remains stationary on the z=0 plane. The physical glass panel
    // rotates about the bottom hinge axis (y = 1.0, z = 0.0) by angle.
    // The viewer's stationary eye ray continues through the glass to the fixed desktop.
    float eyeDistance = 1.85f;
    float3 eye = float3(0.5f, 0.5f, eyeDistance);
    float sine = sin(angle);
    float cosine = cos(angle);

    float3 glass = float3(uv.x, 1.0f - distFromHinge * cosine, distFromHinge * sine);
    float depth = eye.z - glass.z;
    if (depth <= 1e-5f) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float rayScale = eye.z / depth;
    float2 hit = eye.xy + (glass.xy - eye.xy) * rayScale;
    hit = clamp(hit, float2(0.0005f), float2(0.9995f));

    // =========================================================================
    // 2. HINGE CONTACT CLEAR ZONE & PROGRESSIVE OPTICAL DEFOCUS
    // =========================================================================
    // Contact zone near bottom hinge remains 100% optically clear and crisp (Dock protected)
    float contact = smoothstep(0.035f, 0.20f, distFromHinge);
    float opticalStrength = smoothstep(0.0f, 0.025f, p);
    float separation = distFromHinge * sine;
    float blurStrength = max(0.5f, uniforms.blurIntensity);

    // Smooth saturation retains changing slope without abrupt cap
    float scatter = separation * 0.070f * contact * opticalStrength * blurStrength;
    float radius = scatter / sqrt(1.0f + (scatter / 0.040f) * (scatter / 0.040f));

    // Delayed, smooth transmission curtain (desktop visibility preserved)
    float curtainProgress = smoothstep(0.20f, 1.0f, p);
    float feather = 0.22f;
    float edge = mix(-feather, 0.90f, curtainProgress);
    float curtain = 1.0f - smoothstep(edge - feather, edge + feather, uv.y);
    float visibility = 1.0f - 0.40f * curtain;
    float transmission = 1.0f - min(radius * 0.015f, 0.025f);

    // =========================================================================
    // 3. RADIAL CHROMATIC DISPERSION & MULTI-TAP BOKEH SAMPLING
    // =========================================================================
    float chromaticOnset = smoothstep(0.0f, 0.03f, p);
    float chromaAmount = radius * 0.35f * chromaticOnset * contact;
    float2 radialDir = float2((hit.x - 0.5f) * 0.65f, -distFromHinge);
    float2 chromaOffset = radialDir / max(length(radialDir), 0.0001f) * chromaAmount;

    // 17-tap Golden-Angle Poisson Disk Bokeh kernel
    const int SAMPLES = 17;
    const float2 offsets[17] = {
        float2( 0.0000,  0.0000),
        float2( 0.4472,  0.2236),
        float2(-0.3578,  0.5186),
        float2(-0.5590, -0.3245),
        float2( 0.1160, -0.6757),
        float2( 0.7000, -0.0821),
        float2( 0.3123,  0.8488),
        float2(-0.7203,  0.5915),
        float2(-0.9248, -0.3111),
        float2(-0.2351, -1.0234),
        float2( 0.8944, -0.6974),
        float2( 1.0768,  0.3640),
        float2( 0.0000,  1.2500),
        float2(-1.0825,  0.6250),
        float2(-1.0825, -0.6250),
        float2( 0.0000, -1.2500),
        float2( 1.0825, -0.6250)
    };
    const float weights[17] = {
        0.14, 0.08, 0.08, 0.08, 0.07,
        0.07, 0.06, 0.06, 0.06, 0.05,
        0.05, 0.05, 0.04, 0.04, 0.04, 0.04, 0.03
    };

    float3 accumColor = float3(0.0);

    if (radius > 0.0002f) {
        for (int i = 0; i < SAMPLES; i++) {
            float2 tapOffset = offsets[i] * radius;
            float2 sampleUV = clamp(hit + tapOffset, float2(0.0005f), float2(0.9995f));
            if (chromaAmount > 0.0001f) {
                float2 redUV = clamp(sampleUV + chromaOffset, float2(0.0005f), float2(0.9995f));
                float2 blueUV = clamp(sampleUV - chromaOffset, float2(0.0005f), float2(0.9995f));
                float r = inputTexture.sample(textureSampler, redUV).r;
                float g = inputTexture.sample(textureSampler, sampleUV).g;
                float b = inputTexture.sample(textureSampler, blueUV).b;
                accumColor += float3(r, g, b) * weights[i];
            } else {
                accumColor += inputTexture.sample(textureSampler, sampleUV).rgb * weights[i];
            }
        }
    } else {
        accumColor = inputTexture.sample(textureSampler, hit).rgb;
    }

    float3 finalRGB = accumColor * (transmission * visibility);
    return float4(finalRGB, 1.0f);
}
