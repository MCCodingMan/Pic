import Metal
import CoreVideo
import simd

nonisolated final class RealtimeCameraFilterPipeline: @unchecked Sendable {
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
    nonisolated(unsafe) private var textureCache: CVMetalTextureCache?
    nonisolated(unsafe) private var outputTexture: MTLTexture?
    nonisolated(unsafe) private var outputW = 0
    nonisolated(unsafe) private var outputH = 0

    init?() {
        let manager = MetalResourceManager.shared
        guard let state = manager.computePipeline(named: "realtimeCameraFilterKernel") else { return nil }
        device = manager.device
        queue = manager.commandQueue
        pipelineState = state
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    nonisolated func process(
        pixelBuffer: CVPixelBuffer,
        sourceTexture: MTLTexture?,
        adjustments: Adjustments,
        filter: FilterModel
    ) -> MTLTexture? {
        guard let inputTexture = sourceTexture ?? makeInputTexture(from: pixelBuffer),
              let outputTexture = makeOutputTexture(width: inputTexture.width, height: inputTexture.height),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        var adjustmentParams = makeAdjustmentParams(adjustments: adjustments, filter: filter)
        var matrixParams = makeMatrixParams(filter: filter)
        var intensity = Float(filter.intensity)

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBytes(&adjustmentParams, length: MemoryLayout<AdjustmentParamsCPU>.stride, index: 0)
        encoder.setBytes(&matrixParams, length: MemoryLayout<ColorMatrixParamsCPU>.stride, index: 1)
        encoder.setBytes(&intensity, length: MemoryLayout<Float>.stride, index: 2)

        let width = pipelineState.threadExecutionWidth
        let height = max(1, pipelineState.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreadgroups(
            MTLSize(
                width: (inputTexture.width + width - 1) / width,
                height: (inputTexture.height + height - 1) / height,
                depth: 1
            ),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()

        return outputTexture
    }

    private nonisolated func makeInputTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        return texture
    }

    private nonisolated func makeOutputTexture(width: Int, height: Int) -> MTLTexture? {
        if outputTexture == nil || outputW != width || outputH != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            outputTexture = device.makeTexture(descriptor: descriptor)
            outputW = width
            outputH = height
        }
        return outputTexture
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
            clarity: Float(combined.clarity)
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
