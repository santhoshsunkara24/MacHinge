import Foundation
import Metal
import MetalKit
import AppKit

public struct HingeUniforms {
    public var geometry: SIMD4<Float> // point width, point height, progress, blur
    public var optics: SIMD4<Float>   // darkness, chromatic strength, unused, unused
    public var eye: SIMD4<Float>      // eye.x, eye.y, eye.z, unused

    public init(geometry: SIMD4<Float> = .zero, optics: SIMD4<Float> = .zero, eye: SIMD4<Float> = .zero) {
        self.geometry = geometry
        self.optics = optics
        self.eye = eye
    }
}

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
    public var effectStyle: Float = 1.0 // 0.0 = DuoHinge Optical Glass, 1.0 = Luminous Wake Glow, 2.0 = Magnetic Lens
}

@MainActor
public final class DuoFoldRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var duoPipelineState: MTLRenderPipelineState?
    private var hingePipelines: [MTLRenderPipelineState] = []
    private var targets: [MTLTexture] = []
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

        // Duo Pipeline for Luminous Glow & Magnetic Lens
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
            duoPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create duo pipeline state: \(error)")
        }

        // DuoHinge 4-Pass Pipelines for Frosted Glass Physical Folding
        let passNames = ["hingeProject", "hingeBlurX", "hingeBlurY", "hingeDispersion"]
        var loadedHingePipelines: [MTLRenderPipelineState] = []
        if let hingeVert = lib.makeFunction(name: "hingeVertex") {
            for name in passNames {
                guard let frag = lib.makeFunction(name: name) else {
                    print("Failed to make function \(name)")
                    continue
                }
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = hingeVert
                desc.fragmentFunction = frag
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                if let ps = try? device.makeRenderPipelineState(descriptor: desc) {
                    loadedHingePipelines.append(ps)
                }
            }
        }
        if loadedHingePipelines.count == 4 {
            self.hingePipelines = loadedHingePipelines
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
        targets.removeAll()
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        guard let texture = customTexture else {
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                encoder.endEncoding()
            }
            commandBuffer.commit()
            return
        }

        let anim = animationController
        let style = anim?.settings.visualEffectStyle ?? .frostedGlass
        let progress = Float(anim?.progress ?? 0.0)

        // If Frosted Glass is selected, execute the 4-pass DuoHinge physical optical glass pipeline
        if style == .frostedGlass && hingePipelines.count == 4 {
            let width = drawable.texture.width
            let height = drawable.texture.height
            if targets.first?.width != width || targets.first?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = .private
                targets = (0..<3).compactMap { _ in device.makeTexture(descriptor: descriptor) }
            }

            guard targets.count == 3, view.bounds.width > 0, view.bounds.height > 0 else {
                if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                    encoder.endEncoding()
                }
                commandBuffer.commit()
                return
            }

            let intensity = Float(anim?.settings.animationIntensity ?? 1.0)
            let blur = Float(anim?.baseBlur ?? 1.0) * intensity
            var hingeUniforms = HingeUniforms(
                geometry: SIMD4<Float>(Float(view.bounds.width), Float(view.bounds.height), progress, blur),
                optics: SIMD4<Float>(0.5, 0.5, 0.0, 0.0),
                eye: SIMD4<Float>(0.5, 0.35, 2.8, 0.0)
            )

            var source = texture
            for index in 0..<4 {
                let isLast = (index == 3)
                let destination = isLast ? drawable.texture : targets[index]
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = destination
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store

                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { break }
                encoder.setRenderPipelineState(hingePipelines[index])
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentBytes(&hingeUniforms, length: MemoryLayout<HingeUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
                source = destination
            }

            renderCount += 1
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }

        // Otherwise (Luminous Wake Glow & Magnetic Lens), execute single-pass duoPipeline
        guard let duoPipelineState = duoPipelineState,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            return
        }

        let time = Float(ProcessInfo.processInfo.systemUptime - startTime)
        var uniforms = FoldUniforms()

        if let anim = animationController {
            let intensity = Float(anim.settings.animationIntensity)
            uniforms.progress = progress
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

        encoder.setRenderPipelineState(duoPipelineState)
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

constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);

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
    if (fullAngle < 1e-5f) return half4(layer.sample(linearSampler, (position) / bounds.zw).rgb, 1.0h);
    float curtainProgress = smoothstep(0.02f, 1.0f, clamp(progress, 0.0f, 1.0f));
    float feather = 0.22f;
    float edge = mix(-feather, 0.90f, curtainProgress);
    float curtain = 1.0f - smoothstep(edge - feather, edge + feather, p.y / size.y);
    float visibility = 1.0f - min(0.60f * darknessStrength, 0.80f) * curtain;
    float opticalStrength = smoothstep(0.0f, 0.03f, progress);
    float distance = size.y - p.y;
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
    float contact = smoothstep(size.y * 0.02f, size.y * 0.15f, distance);
    float scatter = separation * 0.080f * contact * opticalStrength * blurStrength;
    float radius = scatter / sqrt(1.0f + (scatter / 36.0f) * (scatter / 36.0f));
    bool inside = all(hit >= 0.0f) && all(hit < size);
    half3 color = inside ? layer.sample(linearSampler, (bounds.xy + hit) / bounds.zw).rgb : half3(0);
    float transmission = 1.0f - min(radius * 0.0004f, 0.015f);
    return half4(color * half(transmission * visibility), 1.0h);
}

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
            float2 q = clamp(p + direction * (float(side) * offset),
                             float2(0.0f), max(size - 0.5f, float2(0.0f)));
            sum += float3(layer.sample(linearSampler, (bounds.xy + q) / bounds.zw).rgb) * weight;
        }
        total += 2.0f * weight;
    }
    return half4(half3(sum / total), 1);
}

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

    float2 radial = float2((p.x / size.x - 0.5f) * 0.65f, -heightFromHinge);
    float2 offset = radial / max(length(radial), 0.0001f) * amount;
    float2 upper = max(size - 0.5f, float2(0.0f));
    float2 redPosition = bounds.xy + clamp(p + offset, float2(0.0f), upper);
    float2 bluePosition = bounds.xy + clamp(p - offset, float2(0.0f), upper);
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

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct FoldUniforms {
    float progress;
    float angleDegrees;
    float angularVelocity;
    float time;
    float2 resolution;
    float hingePosition;
    float curvature;
    float perspective;
    float blurIntensity;
    float glowIntensity;
    float effectStyle;
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
"""
