import AppKit
import MetalKit
import QuartzCore
import SwiftUI

struct CadenceModeBackground: NSViewRepresentable {
    let palette: RhythmAccentPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cadenceModeVisualQABackgroundReduceMotionOverride)
    private var visualQAReduceMotionOverride
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeNSView(context _: Context) -> CadenceModeBackgroundView {
        CadenceModeBackgroundView(
            frame: .zero,
            device: MTLCreateSystemDefaultDevice()
        )
    }

    func updateNSView(
        _ view: CadenceModeBackgroundView,
        context _: Context
    ) {
        view.update(
            palette: palette,
            appearance: .resolve(
                reduceMotion: visualQAReduceMotionOverride ?? reduceMotion,
                reduceTransparency: reduceTransparency,
                increasedContrast: colorSchemeContrast == .increased
            )
        )
    }
}

@MainActor
final class CadenceModeBackgroundView: MTKView {
    private var gradientRenderer: CadenceModeGradientRenderer?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        configureRenderer()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()
        configureRenderer()
    }

    override var isOpaque: Bool {
        true
    }

    func update(
        palette: RhythmAccentPalette,
        appearance: CadenceModeBackgroundAppearance
    ) {
        gradientRenderer?.update(
            palette: palette,
            appearance: appearance
        )
        preferredFramesPerSecond = max(
            appearance.maximumAnimationFramesPerSecond,
            1
        )
        isPaused = !appearance.isAnimated
        enableSetNeedsDisplay = !appearance.isAnimated
        if isPaused {
            setNeedsDisplay(bounds)
        }
    }

    private func configureRenderer() {
        guard let device else {
            isPaused = true
            return
        }

        framebufferOnly = true
        autoResizeDrawable = true
        colorPixelFormat = .bgra8Unorm_srgb
        depthStencilPixelFormat = .depth32Float
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = false

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }

        guard let renderer = CadenceModeGradientRenderer(
            device: device,
            colorPixelFormat: colorPixelFormat,
            depthStencilPixelFormat: depthStencilPixelFormat,
            sampleCount: sampleCount
        ) else {
            isPaused = true
            return
        }
        gradientRenderer = renderer
        delegate = renderer
    }

    func makeSnapshot(size: CGSize, time: Float) -> CGImage? {
        gradientRenderer?.makeSnapshot(size: size, time: time)
    }
}

final class CadenceModeGradientRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    let snapshotPipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private let indexCount: Int

    private var colors: [SIMD4<Float>]
    private var paletteTransition: CadenceModeGradientPaletteTransition
    private var hasReceivedPalette = false
    private var isAnimated = true
    private var startedAt = CACurrentMediaTime()

    init?(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        sampleCount: Int
    ) {
        guard
            let commandQueue = device.makeCommandQueue(),
            let pipelineStates = CadenceModeGradientResources.pipelineStates(
                device: device,
                colorPixelFormat: colorPixelFormat,
                depthStencilPixelFormat: depthStencilPixelFormat,
                sampleCount: sampleCount
            ),
            let depthStencilState = CadenceModeGradientResources
            .depthStencilState(device: device),
            let buffers = CadenceModeGradientResources.buffers(device: device)
        else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        pipelineState = pipelineStates.onscreen
        snapshotPipelineState = pipelineStates.snapshot
        self.depthStencilState = depthStencilState
        vertexBuffer = buffers.vertices
        indexBuffer = buffers.indices
        indexCount = buffers.indexCount
        colors = Self.metalColors(
            for: RhythmAccentPalette.cadenceFallback
        )
        paletteTransition = CadenceModeGradientPaletteTransition(
            palette: .cadenceFallback
        )
        super.init()
    }

    func update(
        palette: RhythmAccentPalette,
        appearance: CadenceModeBackgroundAppearance
    ) {
        let currentTime = CACurrentMediaTime()
        paletteTransition.retarget(
            to: palette,
            at: currentTime,
            reduceMotion: !hasReceivedPalette || !appearance.isAnimated
        )
        colors = Self.metalColors(
            paletteTransition.colors(at: currentTime)
        )
        hasReceivedPalette = true
        if appearance.isAnimated, !isAnimated {
            startedAt = currentTime
        }
        isAnimated = appearance.isAnimated
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        guard
            view.drawableSize.width > 0,
            view.drawableSize.height > 0,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            )
        else {
            return
        }

        colors = Self.metalColors(
            paletteTransition.colors(at: currentTime)
        )

        let aspectRatio = Float(
            view.drawableSize.width / view.drawableSize.height
        )
        encode(
            encoder: encoder,
            pipelineState: pipelineState,
            aspectRatio: aspectRatio,
            time: CadenceModeGradientTimeline.elapsedTime(
                startedAt: startedAt,
                currentTime: currentTime,
                isAnimated: isAnimated
            )
        )

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func encode(
        encoder: MTLRenderCommandEncoder,
        pipelineState: MTLRenderPipelineState,
        aspectRatio: Float,
        time: Float
    ) {
        var uniforms = CadenceModeGradientUniforms(
            modelMatrix: CadenceModeGradientReference.modelMatrix,
            viewProjectionMatrix: CadenceModeGradientReference
                .viewProjectionMatrix(aspectRatio: aspectRatio),
            noiseFrequency: CadenceModeGradientReference.noiseFrequency,
            time: time,
            noiseAmount: CadenceModeGradientReference.noiseAmount,
            noiseSpeed: CadenceModeGradientReference.noiseSpeed
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<CadenceModeGradientUniforms>.stride,
            index: 1
        )
        colors.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            encoder.setVertexBytes(
                baseAddress,
                length: bytes.count,
                index: 2
            )
        }
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
    }

    private static func metalColors(
        for palette: RhythmAccentPalette
    ) -> [SIMD4<Float>] {
        metalColors(CadenceModeGradientReference.shaderColors(for: palette))
    }

    private static func metalColors(
        _ colors: [SIMD3<Float>]
    ) -> [SIMD4<Float>] {
        colors.map {
            SIMD4($0.x, $0.y, $0.z, 1)
        }
    }
}
