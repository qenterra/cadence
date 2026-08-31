import Metal
import simd

struct CadenceModeGradientUniforms {
    var modelMatrix: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var noiseFrequency: SIMD2<Float>
    var time: Float
    var noiseAmount: Float
    var noiseSpeed: Float
    var padding0: Float = 0
    var padding1: Float = 0
    var padding2: Float = 0
}

struct CadenceModeGradientPipelineStates {
    let onscreen: MTLRenderPipelineState
    let snapshot: MTLRenderPipelineState
}

struct CadenceModeGradientBuffers {
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let indexCount: Int
}

enum CadenceModeGradientPrewarmer {
    static func prepare() {
        Task.detached(priority: .utility) {
            CadenceModeGradientResources.prewarm()
        }
    }
}

enum CadenceModeGradientResources {
    static func pipelineStates(
        device: MTLDevice,
        colorPixelFormat: MTLPixelFormat,
        depthStencilPixelFormat: MTLPixelFormat,
        sampleCount: Int
    ) -> CadenceModeGradientPipelineStates? {
        guard
            let library = library(device: device),
            let vertexFunction = library.makeFunction(
                name: "cadenceGradientVertex"
            ),
            let fragmentFunction = library.makeFunction(
                name: "cadenceGradientFragment"
            )
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.depthAttachmentPixelFormat = depthStencilPixelFormat
        descriptor.rasterSampleCount = sampleCount
        guard let onscreen = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else {
            return nil
        }
        descriptor.rasterSampleCount = 1
        guard let snapshot = try? device.makeRenderPipelineState(
            descriptor: descriptor
        ) else {
            return nil
        }
        return CadenceModeGradientPipelineStates(
            onscreen: onscreen,
            snapshot: snapshot
        )
    }

    static func prewarm() {
        _ = preparedDefaultLibrary
    }

    static func depthStencilState(
        device: MTLDevice
    ) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    static func buffers(device: MTLDevice) -> CadenceModeGradientBuffers? {
        let mesh = CadenceModeGradientReference.makeMesh()
        let vertices: MTLBuffer? = mesh.vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return nil
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
        let indices: MTLBuffer? = mesh.indices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return nil
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
        guard let vertices, let indices else {
            return nil
        }
        return CadenceModeGradientBuffers(
            vertices: vertices,
            indices: indices,
            indexCount: mesh.indices.count
        )
    }

    private static func library(device: MTLDevice) -> MTLLibrary? {
        if let preparedDefaultLibrary,
           preparedDefaultLibrary.registryID == device.registryID {
            return preparedDefaultLibrary.library
        }
        guard let source = CadenceModeGradientShader.source else {
            return nil
        }
        return try? device.makeLibrary(source: source, options: nil)
    }

    private static let preparedDefaultLibrary:
        CadenceModePreparedGradientLibrary? = {
            guard
                let device = MTLCreateSystemDefaultDevice(),
                let source = CadenceModeGradientShader.source,
                let library = try? device.makeLibrary(
                    source: source,
                    options: nil
                )
            else {
                return nil
            }
            return CadenceModePreparedGradientLibrary(
                registryID: device.registryID,
                library: library
            )
        }()
}

private final class CadenceModePreparedGradientLibrary: @unchecked Sendable {
    let registryID: UInt64
    let library: MTLLibrary

    init(registryID: UInt64, library: MTLLibrary) {
        self.registryID = registryID
        self.library = library
    }
}
