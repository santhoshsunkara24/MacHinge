import Foundation
import Metal
import MetalKit
import AppKit

public struct FoldUniforms {
    public var progress: Float = 0.0
    public var angleDegrees: Float = 105.0
    public var angularVelocity: Float = 0.0
    public var time: Float = 0.0
    public var resolution: SIMD2<Float> = SIMD2<Float>(1920, 1080)
    public var hingePosition: Float = 1.0
    public var curvature: Float = 0.65
    public var perspective: Float = 0.20
    public var blurIntensity: Float = 1.0
    public var glowIntensity: Float = 1.0
    public var effectStyle: Float = 1.0 // 0.0 = Pure Frosted Glass, 1.0 = Luminous Wake Glow
}

@MainActor
public final class DuoFoldRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var customTexture: MTLTexture?
    private var currentFrame: CapturedFrame?
    private weak var metalKitView: MTKView?

    public var animationController: AnimationController?
    public private(set) var renderCount: Int = 0
    public private(set) var lastTextureWidth: Int = 0
    public private(set) var lastTextureHeight: Int = 0
    private var startTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    public init?(metalKitView: MTKView) {
        guard let defaultDevice = MTLCreateSystemDefaultDevice(),
              let queue = defaultDevice.makeCommandQueue() else {
            return nil
        }

        self.device = defaultDevice
        self.commandQueue = queue
        self.metalKitView = metalKitView
        super.init()

        metalKitView.device = defaultDevice
        metalKitView.delegate = self
        metalKitView.colorPixelFormat = .bgra8Unorm
        metalKitView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalKitView.framebufferOnly = false
        metalKitView.isPaused = false
        metalKitView.enableSetNeedsDisplay = false

        setupPipeline()
        setupSampler()
    }

    public func setTexture(_ frame: CapturedFrame) {
        self.currentFrame = frame
        self.customTexture = frame.texture
        self.lastTextureWidth = frame.width
        self.lastHeight = frame.height
    }

    public func setTexture(_ texture: MTLTexture) {
        self.customTexture = texture
        self.lastTextureWidth = texture.width
        self.lastTextureHeight = texture.height
    }

    public func clearTexture() {
        self.currentFrame = nil
        self.customTexture = nil
    }

    private var lastHeight: Int {
        get { lastTextureHeight }
        set { lastTextureHeight = newValue }
    }

    public var isPaused: Bool {
        return metalKitView?.isPaused ?? false
    }

    public func setPaused(_ paused: Bool) {
        guard metalKitView?.isPaused != paused else { return }
        metalKitView?.isPaused = paused
        metalKitView?.enableSetNeedsDisplay = paused
        if !paused {
            metalKitView?.preferredFramesPerSecond = 60
            metalKitView?.setNeedsDisplay(metalKitView?.bounds ?? .zero)
        }
    }

    private func setupPipeline() {
        var library: MTLLibrary?
        if let defaultLib = try? device.makeDefaultLibrary(bundle: Bundle.main) {
            library = defaultLib
        } else if let sourceLib = try? device.makeLibrary(source: shadersSource, options: nil) {
            library = sourceLib
        }

        guard let lib = library else {
            print("Failed to compile Metal library")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = lib.makeFunction(name: "duoVertexShader")
        pipelineDescriptor.fragmentFunction = lib.makeFunction(name: "duoFoldFragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

    private func setupSampler() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: descriptor)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pipelineState = pipelineState,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        guard let texture = customTexture else {
            encoder.endEncoding()
            commandBuffer.commit()
            return
        }

        let time = Float(ProcessInfo.processInfo.systemUptime - startTime)
        var uniforms = FoldUniforms()

        if let anim = animationController {
            let intensity = Float(anim.settings.animationIntensity)
            uniforms.progress = Float(anim.progress)
            uniforms.angleDegrees = Float(anim.smoothedAngle)
            uniforms.angularVelocity = Float(anim.progressVelocity)
            uniforms.curvature = Float(anim.baseCurvature) * intensity
            uniforms.perspective = Float(anim.basePerspective) * intensity
            uniforms.blurIntensity = Float(anim.baseBlur) * intensity
            uniforms.glowIntensity = Float(anim.settings.glowIntensity) * intensity
            switch anim.settings.visualEffectStyle {
            case .frostedGlass:
                uniforms.effectStyle = 0.0
            case .luminousGlow:
                uniforms.effectStyle = 1.0
            case .magneticLens:
                uniforms.effectStyle = 2.0
            }
        }

        uniforms.time = time
        uniforms.resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderCount += 1

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private let shadersSource = """
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

    float v = uv.y; // 0.0 = top of screen, 1.0 = bottom hinge
    float u = uv.x; // 0.0 = left edge, 1.0 = right edge
    float distFromHinge = 1.0 - v; // 0.0 at hinge, 1.0 at top

    // 1. Subtle 3D Perspective Foreshortening (Gentle, non-aggressive taper)
    float perspectiveStrength = min(uniforms.perspective, 0.14);
    float perspectiveFactor = pow(p, 0.92) * perspectiveStrength;
    float taperFactor = 1.0 - (perspectiveFactor * distFromHinge);
    float centeredU = (u - 0.5) / max(0.001, taperFactor) + 0.5;

    // Deep dark chassis backdrop behind the display
    float3 backdropRGB = float3(0.02, 0.02, 0.025);

    // Outside perspective bounds -> clean backdrop
    if (centeredU < 0.0 || centeredU > 1.0) {
        return float4(backdropRGB, 1.0);
    }

    // 2. Gentle 3D Cylindrical Fold (Subtle compression, keeping content expansive)
    float curvatureStrength = min(uniforms.curvature, 0.38);
    float curveFactor = pow(p, 0.90) * curvatureStrength;
    float compressionExponent = 1.0 + (0.28 * curveFactor);
    float sourceV = 1.0 - pow(distFromHinge, 1.0 / max(0.05, compressionExponent));

    // Subtle hinge rollover
    float hingeRollover = smoothstep(0.65, 1.0, v) * (0.018 * p * sin(v * 3.14159));
    sourceV = clamp(sourceV + hingeRollover, 0.0, 1.0);

    float2 sourceUV = float2(centeredU, sourceV);

    // =========================================================================
    // 3. SILKY FROSTED GLASS & DIRECTIONAL MOTION DIFFUSION
    // =========================================================================
    float velocity = uniforms.angularVelocity;
    float speed = abs(velocity);
    float dir = velocity > 0.0 ? 1.0 : -1.0;

    // Blur radius grows smoothly with fold progress p + dynamic velocity
    float pGlass = pow(p, 0.85);
    float baseRadius = 0.0080 * pGlass * min(uniforms.blurIntensity, 1.8);
    float motionBoost = 0.0030 * min(pow(speed, 0.85), 2.5);
    float glassRadius = clamp(baseRadius + motionBoost, 0.0, 0.0160);

    // Directional bias when moving
    float2 motionBias = float2(0.0, dir * min(speed, 2.0) * 0.35);

    // 13-tap 2D Golden-Angle Poisson distribution for silky isotropic glass diffusion
    const int SAMPLES = 13;
    const float2 offsets[13] = {
        float2( 0.000,  0.000),
        float2( 0.528,  0.283),
        float2(-0.472,  0.684),
        float2(-0.738, -0.428),
        float2( 0.153, -0.892),
        float2( 0.923, -0.108),
        float2( 0.412,  1.120),
        float2(-0.950,  0.780),
        float2(-1.220, -0.410),
        float2(-0.310, -1.350),
        float2( 1.180, -0.920),
        float2( 1.420,  0.480),
        float2( 0.000,  1.650)
    };
    const float weights[13] = {
        0.16, 0.11, 0.10, 0.10, 0.09, 0.08, 0.07, 0.06, 0.06, 0.05, 0.04, 0.04, 0.04
    };

    float4 color = float4(0.0);

    if (uniforms.effectStyle > 1.5) {
        // =========================================================================
        // MAGNETIC LENS DISTORTION & CHROMATIC GRAVITATIONAL WARP
        // =========================================================================
        float lensTiming = pow(p, 0.90);

        float2 pole = float2(0.5, 1.05);
        float2 toPole = sourceUV - pole;
        float distToPole = length(toPole);

        // Gravitational deflection field toward the hinge pole
        float fieldStrength = lensTiming * 0.45;
        float deflection = fieldStrength / (distToPole * 2.0 + 0.28);
        float2 warpedUV = sourceUV - normalize(toPole) * (deflection * 0.25);

        // Frame-dragging spacetime swirl tied to lid angular velocity
        float angle = atan2(toPole.y, toPole.x) + (velocity * 0.025 * lensTiming / (distToPole + 0.20));
        float2 swirl = float2(cos(angle), sin(angle)) * distToPole - toPole;
        warpedUV += swirl * 0.35;

        // Chromatic dispersion (differential RGB bending)
        float dispersion = 0.015 * lensTiming;
        float2 redUV = clamp(warpedUV + normalize(toPole) * dispersion, float2(0.0005), float2(0.9995));
        float2 greenUV = clamp(warpedUV, float2(0.0005), float2(0.9995));
        float2 blueUV = clamp(warpedUV - normalize(toPole) * dispersion, float2(0.0005), float2(0.9995));

        float r = inputTexture.sample(textureSampler, redUV).r;
        float g = inputTexture.sample(textureSampler, greenUV).g;
        float b = inputTexture.sample(textureSampler, blueUV).b;
        color = float4(r, g, b, 1.0);

        // Subtle Einstein ring caustic shimmer along magnetic flux lines
        float ringPhase = sin(distToPole * 42.0 - uniforms.time * 2.0);
        float fluxCaustic = pow(max(0.0, ringPhase), 8.0) * 0.15 * lensTiming;
        color.rgb += float3(0.35, 0.65, 1.0) * fluxCaustic;
    } else if (glassRadius > 0.0002) {
        for (int i = 0; i < SAMPLES; i++) {
            float2 sampleOffset = (offsets[i] + motionBias) * glassRadius;
            sampleOffset.x *= 0.65;
            float2 sampleUV = clamp(sourceUV + sampleOffset, float2(0.0005), float2(0.9995));
            color += inputTexture.sample(textureSampler, sampleUV) * weights[i];
        }
    } else {
        color = inputTexture.sample(textureSampler, sourceUV);
    }

    // =========================================================================
    // 4. NATURAL OPTICAL LIGHTING
    // =========================================================================
    // Subtle frosted material exposure boost
    float3 frostedRGB = color.rgb * (1.0 + (0.05 * p));

    // Ambient crease shading & subtle glass specular sheen
    float ambientOcclusion = 1.0 - (0.22 * pow(p, 1.0) * exp(-distFromHinge * 4.0));
    float highlightDist = abs(v - (1.0 - (0.025 * (1.0 - p))));
    float specular = (0.10 * p) * exp(-highlightDist * 80.0);

    // Sub-pixel edge antialiasing
    float edgeDist = min(centeredU, 1.0 - centeredU);
    float edgeAlpha = smoothstep(0.0, 0.012, edgeDist);

    // =========================================================================
    // 5. LUMINOUS WAKE & FOLD GLOW (PROGRESSIVE SMOOTH WHITE FLOW)
    // =========================================================================
    float3 glowLayer = float3(0.0);
    if (uniforms.effectStyle > 0.5 && uniforms.effectStyle < 1.5) {
        float glowTiming = pow(p, 0.88);

        // Volumetric flood bloom peaking near closed
        float floodBloom = glowTiming * 1.5;

        // Cascading light sweep flowing smoothly across the fold
        float flowPosition = 1.0 - (0.55 * p);
        float lightFlow = exp(-pow((v - flowPosition), 2.0) * 8.0) * glowTiming * 1.6;

        // Ethereal crease radiance and silhouette halo
        float creaseGlow = exp(-abs(v - (1.0 - 0.20 * p)) * 5.0) * glowTiming * 1.8;
        float edgeHalo = pow(max(0.0, 1.0 - edgeDist * 2.5), 2.0) * glowTiming * 1.4;

        // Smooth physical motion presence
        float motionSurge = min(speed * 0.15, 0.30) * glowTiming;

        // High-intensity dazzling pure white radiance
        float totalWhiteRadiance = (floodBloom * 0.70 + lightFlow * 0.95 + creaseGlow * 0.85 + edgeHalo * 0.55 + motionSurge * 0.20) * uniforms.glowIntensity;
        float3 pureWhite = float3(1.0, 1.0, 1.0);
        glowLayer = pureWhite * totalWhiteRadiance;
    } else if (uniforms.effectStyle > 1.5) {
        float lensTiming = pow(p, 0.90);
        // Magnetic halo flux along outer edge
        float magneticHalo = pow(max(0.0, 1.0 - edgeDist * 3.0), 2.0) * lensTiming * 0.60;
        glowLayer = float3(0.25, 0.55, 1.0) * magneticHalo * uniforms.glowIntensity;
    }

    float3 screenRGB = (frostedRGB * ambientOcclusion + specular) + glowLayer;
    float3 finalRGB = mix(backdropRGB, screenRGB, edgeAlpha);

    return float4(finalRGB, 1.0);
}
"""
