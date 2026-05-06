import Metal
import CoreVideo
import UIKit

/// 实时美颜 compute pipeline：吃 CVPixelBuffer，吐 MTLTexture，单 pass。
/// 替代 BeautyCameraProcessor 中基于 CIFilter 的实时路径，与编辑器侧的 compute kernel 范式统一。
nonisolated final class RealtimeBeautyPipeline: @unchecked Sendable {

    struct ParamsCPU {
        var smoothing: Float
        var whitening: Float
        var whiteningYUV: Float
        var faceCount: Int32
    }

    private struct FaceCircleCPU {
        var center: SIMD2<Float>
        var radius: Float
        var _pad: Float = 0
    }

    private struct AdjustmentParamsCPU {
        var exposure: Float
        var contrast: Float
        var brightness: Float
        var saturation: Float
        var highlights: Float
        var shadows: Float
        var temperature: Float
        var tint: Float
        var vignette: Float
        var sharpen: Float
        var clarity: Float
        var grain: Float
    }

    private struct ColorMatrixParamsCPU {
        var rVector: SIMD4<Float>
        var gVector: SIMD4<Float>
        var bVector: SIMD4<Float>
        var aVector: SIMD4<Float>
        var biasVector: SIMD4<Float>
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState
    private let fusedPipelineState: MTLComputePipelineState?
    nonisolated(unsafe) private var textureCache: CVMetalTextureCache?
    nonisolated(unsafe) private var outputTexture: MTLTexture?
    nonisolated(unsafe) private var outputW: Int = 0
    nonisolated(unsafe) private var outputH: Int = 0

    init?() {
        let mgr = MetalResourceManager.shared
        guard let pso = mgr.computePipeline(named: "realtimeBeautyKernel") else { return nil }
        self.device = mgr.device
        self.queue = mgr.commandQueue
        self.pipelineState = pso
        self.fusedPipelineState = mgr.computePipeline(named: "realtimeBeautyFilterKernel")
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    nonisolated var supportsFusedFilter: Bool {
        fusedPipelineState != nil
    }

    /// 处理一帧。`faceContext` 走的是 ImagePipeline 的统一契约（来自 LiveFaceDetector）。
    /// `pixelBufferDisplaySize` 是相机预览的展示尺寸（用于把 metadata bounds 映射到 0..1 uv）。
    /// 为简化起见，这里直接用 metadata 的归一化 bounds —— Apple 文档保证 .face metadata
    /// 的 bounds 已经是相对于视频帧的归一化坐标。
    nonisolated func process(pixelBuffer: CVPixelBuffer, params: ParamsCPU, faceContext: FaceContext) -> MTLTexture? {
        guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
        let output = process(
            pixelBuffer: pixelBuffer,
            params: params,
            faceContext: faceContext,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        return output
    }

    nonisolated func process(
        pixelBuffer: CVPixelBuffer,
        params: ParamsCPU,
        faceContext: FaceContext,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        processFrame(
            pixelBuffer: pixelBuffer,
            params: params,
            faceContext: faceContext,
            adjustments: nil,
            filter: nil,
            commandBuffer: commandBuffer
        )
    }

    nonisolated func process(
        pixelBuffer: CVPixelBuffer,
        params: ParamsCPU,
        faceContext: FaceContext,
        adjustments: Adjustments,
        filter: FilterModel
    ) -> MTLTexture? {
        guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
        let output = process(
            pixelBuffer: pixelBuffer,
            params: params,
            faceContext: faceContext,
            adjustments: adjustments,
            filter: filter,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        return output
    }

    nonisolated func process(
        pixelBuffer: CVPixelBuffer,
        params: ParamsCPU,
        faceContext: FaceContext,
        adjustments: Adjustments,
        filter: FilterModel,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        processFrame(
            pixelBuffer: pixelBuffer,
            params: params,
            faceContext: faceContext,
            adjustments: adjustments,
            filter: filter,
            commandBuffer: commandBuffer
        )
    }

    private nonisolated func processFrame(
        pixelBuffer: CVPixelBuffer,
        params: ParamsCPU,
        faceContext: FaceContext,
        adjustments: Adjustments?,
        filter: FilterModel?,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let textureCache else { return nil }

        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let shouldFuseFilter = adjustments != nil && filter != nil
        let activePipelineState = shouldFuseFilter ? (fusedPipelineState ?? pipelineState) : pipelineState

        // 1) CVPixelBuffer → MTLTexture (zero-copy via CVMetalTextureCache)
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, w, h, 0, &cvTex
        )
        guard status == kCVReturnSuccess,
              let cvTex,
              let inTex = CVMetalTextureGetTexture(cvTex) else { return nil }

        // 2) 准备/复用输出纹理
        if outputTexture == nil || outputW != w || outputH != h {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .private
            outputTexture = device.makeTexture(descriptor: desc)
            outputW = w
            outputH = h
        }
        guard let outTex = outputTexture else { return nil }

        var circles: [FaceCircleCPU] = []
        if params.smoothing > 0.001 {
            for face in faceContext.faces.prefix(4) {
                let box = face.boundingBox
                let cx: CGFloat
                let cy: CGFloat
                switch faceContext.source {
                case .vision:
                    cx = box.midX
                    cy = 1.0 - box.midY
                default:
                    cx = box.midX
                    cy = box.midY
                }
                let radius = max(box.width, box.height) * 0.7
                circles.append(FaceCircleCPU(
                    center: SIMD2<Float>(Float(cx), Float(cy)),
                    radius: Float(radius)
                ))
            }
        }
        while circles.count < 4 {
            circles.append(FaceCircleCPU(center: .zero, radius: 0))
        }

        var paramsBytes = params

        guard let enc = commandBuffer.makeComputeCommandEncoder() else { return nil }

        enc.setComputePipelineState(activePipelineState)
        enc.setTexture(inTex, index: 0)
        enc.setTexture(outTex, index: 1)
        enc.setBytes(&paramsBytes, length: MemoryLayout<ParamsCPU>.stride, index: 0)
        enc.setBytes(circles, length: MemoryLayout<FaceCircleCPU>.stride * 4, index: 1)
        if shouldFuseFilter, let adjustments, let filter, fusedPipelineState != nil {
            var adjustmentParams = makeAdjustmentParams(adjustments: adjustments, filter: filter)
            var matrixParams = makeMatrixParams(filter: filter)
            var intensity = Float(filter.intensity)
            enc.setBytes(&adjustmentParams, length: MemoryLayout<AdjustmentParamsCPU>.stride, index: 2)
            enc.setBytes(&matrixParams, length: MemoryLayout<ColorMatrixParamsCPU>.stride, index: 3)
            enc.setBytes(&intensity, length: MemoryLayout<Float>.stride, index: 4)
        }

        let tw = activePipelineState.threadExecutionWidth
        let th = activePipelineState.maxTotalThreadsPerThreadgroup / tw
        enc.dispatchThreadgroups(
            MTLSize(width: (w + tw - 1) / tw, height: (h + th - 1) / th, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1)
        )
        enc.endEncoding()
        return outTex
    }

    private nonisolated func makeAdjustmentParams(adjustments: Adjustments, filter: FilterModel) -> AdjustmentParamsCPU {
        let combined = combinedAdjustments(adjustments, filter.adjustments)
        return AdjustmentParamsCPU(
            exposure: Float(combined.exposure),
            contrast: Float(combined.contrast + combined.clarity * 0.2),
            brightness: Float(combined.brightness),
            saturation: Float(combined.saturation),
            highlights: Float(combined.highlights),
            shadows: Float(combined.shadows),
            temperature: Float(combined.warmth),
            tint: Float(combined.tint),
            vignette: Float(combined.vignette),
            sharpen: Float(combined.sharpen),
            clarity: Float(combined.clarity),
            grain: Float(combined.grain)
        )
    }

    private nonisolated func makeMatrixParams(filter: FilterModel) -> ColorMatrixParamsCPU {
        guard let matrix = filter.colorMatrix, matrix.count == 20 else {
            return ColorMatrixParamsCPU(
                rVector: SIMD4<Float>(1, 0, 0, 0),
                gVector: SIMD4<Float>(0, 1, 0, 0),
                bVector: SIMD4<Float>(0, 0, 1, 0),
                aVector: SIMD4<Float>(0, 0, 0, 1),
                biasVector: .zero
            )
        }

        let values = matrix.map(Float.init)
        return ColorMatrixParamsCPU(
            rVector: SIMD4<Float>(values[0], values[1], values[2], values[3]),
            gVector: SIMD4<Float>(values[4], values[5], values[6], values[7]),
            bVector: SIMD4<Float>(values[8], values[9], values[10], values[11]),
            aVector: SIMD4<Float>(values[12], values[13], values[14], values[15]),
            biasVector: SIMD4<Float>(values[16], values[17], values[18], values[19])
        )
    }

    private nonisolated func combinedAdjustments(_ base: Adjustments, _ preset: Adjustments?) -> Adjustments {
        guard let preset else { return base }
        var output = base
        output.exposure += preset.exposure
        output.contrast *= preset.contrast
        output.brightness += preset.brightness
        output.highlights = clamp(output.highlights + preset.highlights, -1, 1)
        output.shadows = clamp(output.shadows + preset.shadows, -1, 1)
        output.saturation *= preset.saturation
        output.warmth = clamp(output.warmth + preset.warmth, -1, 1)
        output.tint = clamp(output.tint + preset.tint, -1, 1)
        output.sharpen = clamp(output.sharpen + preset.sharpen, -1, 2)
        output.clarity = clamp(output.clarity + preset.clarity, -1, 1)
        output.vignette = clamp(output.vignette + preset.vignette, 0, 1)
        return output
    }

    private nonisolated func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
