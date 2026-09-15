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
"""
