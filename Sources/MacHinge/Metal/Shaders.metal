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
    float effectStyle;      // 0.0 = Pure Frosted Glass, 1.0 = Luminous Wake Glow
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

// MacBook physical lid folding transition fragment shader
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

    float u = uv.x; // 0.0 = left edge, 1.0 = right edge
    float v = uv.y; // 0.0 = top of screen, 1.0 = bottom hinge

    // Deep dark chassis backdrop behind the physical folding display
    float3 backdropRGB = float3(0.02, 0.02, 0.025);

    // =========================================================================
    // 1. PHYSICAL 3D SCREEN TILT & PERSPECTIVE PROJECTION
    // =========================================================================
    // As the lid closes (p: 0 -> 1), the screen panel rotates forward around the
    // physical bottom hinge axis (y = 1.0) by forward tilt angle theta.
    float maxTiltAngle = 1.15; // ~66 degrees forward rotation at full fold
    float theta = p * maxTiltAngle;
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);

    // Camera perspective distance parameter (standard MacBook eye-distance ratio)
    float eyeDist = 1.85;

    // Projected top edge of the physical screen in screen space (v_top descends as lid folds forward)
    float zTop = -sinTheta; // moves closer/forward in depth
    float yTop = 1.0 - (cosTheta * eyeDist) / (eyeDist + zTop);
    float vTop = clamp(yTop, 0.0, 0.98);

    // Pixels above the physical top edge of the tilted lid show the clean chassis backdrop
    if (v < vTop) {
        // Soft antialiasing transition along the physical top bezel
        float topEdgeDist = vTop - v;
        float topBezelAlpha = smoothstep(0.0, 0.008, topEdgeDist);
        return float4(backdropRGB, 1.0);
    }

    // Map screen vertical coordinate v in [vTop, 1.0] back to physical panel coordinate s in [0.0, 1.0]
    // (0.0 = top of physical display, 1.0 = bottom hinge)
    float screenFrac = (v - vTop) / max(0.001, (1.0 - vTop));
    
    // Physical cylindrical hinge bend curvature near bottom (v -> 1.0)
    // Curvature roll radius R contracts subtly as fold tightens
    float bendZone = 0.35 * (1.0 + 0.5 * p); // bottom 35-50% enters the hinge curve
    float sourceV = 0.0;
    float surfaceNormalZ = cosTheta;
    float surfaceNormalY = sinTheta;

    if (screenFrac < (1.0 - bendZone)) {
        // Upper flat section: smooth linear foreshortened mapping
        float flatFrac = screenFrac / (1.0 - bendZone);
        float sUpper = flatFrac * (1.0 - bendZone);
        // Subtle depth-corrected easing
        sourceV = sUpper * (1.0 + 0.08 * p * (1.0 - sUpper));
    } else {
        // Lower cylindrical bend section: smooth arc-length roll into hinge
        float curveFrac = (screenFrac - (1.0 - bendZone)) / bendZone;
        // Circular arc mapping parameterization (guarantees bounded derivative, zero barcode stretching)
        float arcAngle = curveFrac * (3.14159265 * 0.5);
        float sCurve = (1.0 - bendZone) + (sin(arcAngle) * bendZone);
        sourceV = sCurve;

        // Update physical surface normal along the curve for realistic lighting
        surfaceNormalZ = cos(theta + (curveFrac * (1.57 - theta)));
        surfaceNormalY = sin(theta + (curveFrac * (1.57 - theta)));
    }

    sourceV = clamp(sourceV, 0.0, 1.0);

    // =========================================================================
    // 2. HORIZONTAL 3D TRAPEZOIDAL PERSPECTIVE TAPERING
    // =========================================================================
    // Width at height v narrows authentically as the top of the lid tilts toward/away in 3D
    float distFromHinge = 1.0 - sourceV; // 1.0 at top of display, 0.0 at hinge
    float perspectiveStrength = min(uniforms.perspective, 0.22);
    float widthAtV = 1.0 - (p * perspectiveStrength * distFromHinge * (1.0 + 0.25 * sinTheta));
    widthAtV = max(0.05, widthAtV);

    float centeredU = (u - 0.5) / widthAtV + 0.5;

    // Pixels outside the physical side bezels show the clean backdrop
    if (centeredU < 0.0 || centeredU > 1.0) {
        return float4(backdropRGB, 1.0);
    }

    // =========================================================================
    // 3. CRISP PHYSICAL SCREEN SAMPLING (NO FROSTED GLASS BLUR)
    // =========================================================================
    float2 sourceUV = float2(centeredU, sourceV);
    float4 screenColor = inputTexture.sample(textureSampler, sourceUV);

    // =========================================================================
    // 4. PHYSICAL SURFACE SHADING & NATURAL LIGHTING
    // =========================================================================
    // Diffuse directional illumination from top-front lighting
    float lightDot = max(0.0, surfaceNormalZ * 0.75 + surfaceNormalY * 0.66);
    float diffuseShading = 0.82 + (0.18 * lightDot);

    // Ambient crease shadow in the hinge valley (contact shadow where screen meets base)
    float hingeCreaseAO = 1.0 - (0.24 * pow(p, 0.9) * exp(-distFromHinge * 5.0));

    // Specular cylindrical highlight reflecting light along the curvature roll
    float specularRoll = pow(max(0.0, surfaceNormalZ), 12.0) * (0.08 * p);

    // Top bezel edge shadow (physical bezel depth casting subtle inner shadow on screen)
    float topBezelShadow = smoothstep(0.0, 0.025, sourceV);
    float topInnerShadow = 0.94 + 0.06 * topBezelShadow;

    // Combine physical surface lighting
    float3 litScreenRGB = screenColor.rgb * diffuseShading * hingeCreaseAO * topInnerShadow + specularRoll;

    // =========================================================================
    // 5. SUB-PIXEL BEZEL SILHOUETTE ANTIALIASING
    // =========================================================================
    float horizontalEdgeDist = min(centeredU, 1.0 - centeredU) * widthAtV;
    float verticalEdgeDist = min(v - vTop, 1.0 - v);
    float minEdgeDist = min(horizontalEdgeDist, verticalEdgeDist);
    float edgeAlpha = smoothstep(0.0, 0.006, minEdgeDist);

    // Clean composite over dark chassis backdrop
    float3 finalRGB = mix(backdropRGB, litScreenRGB, edgeAlpha);

    return float4(finalRGB, 1.0);
}
