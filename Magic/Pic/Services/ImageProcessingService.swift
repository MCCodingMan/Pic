import GPUImage
import Metal
import MetalKit
import CoreImage
import UIKit

// MARK: - Metal Parameters (kept for HSL, Curves, Grain, Masks)

struct AdjustmentParams {
    var exposure: Float
    var contrast: Float
    var brightness: Float
    var saturation: Float
    var highlights: Float
    var shadows: Float
    var temperature: Float
    var tint: Float
}

struct HSLParams {
    var hRed: Float; var sRed: Float; var lRed: Float
    var hOrange: Float; var sOrange: Float; var lOrange: Float
    var hYellow: Float; var sYellow: Float; var lYellow: Float
    var hGreen: Float; var sGreen: Float; var lGreen: Float
    var hCyan: Float; var sCyan: Float; var lCyan: Float
    var hBlue: Float; var sBlue: Float; var lBlue: Float
    var hPurple: Float; var sPurple: Float; var lPurple: Float
    var hMagenta: Float; var sMagenta: Float; var lMagenta: Float
}

struct GradientParams {
    var startPoint: SIMD2<Float>
    var endPoint: SIMD2<Float>
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
}

struct RadialGradientParams {
    var center: SIMD2<Float>
    var radius0: Float
    var radius1: Float
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
}

nonisolated class ImageProcessingService: @unchecked Sendable {
    static let shared = ImageProcessingService()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext

    // Metal pipelines - kept for operations GPUImage3 doesn't support natively
    private var basicAdjustmentsState: MTLComputePipelineState?
    private var hslState: MTLComputePipelineState?
    private var curveState: MTLComputePipelineState?
    private var grainState: MTLComputePipelineState?
    private var linearGradientState: MTLComputePipelineState?
    private var radialGradientState: MTLComputePipelineState?
    private var blendState: MTLComputePipelineState?

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal not supported")
        }
        self.device = device
        self.commandQueue = queue
        self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])

        setupMetalPipelines()
    }

    private func setupMetalPipelines() {
        let library: MTLLibrary
        do {
            if let url = Bundle.main.url(forResource: "default", withExtension: "metallib") {
                library = try device.makeLibrary(URL: url)
            } else {
                library = try device.makeDefaultLibrary(bundle: Bundle.main)
            }
        } catch {
            print("Failed to load Metal library: \(error)")
            return
        }

        func makeState(_ name: String) -> MTLComputePipelineState? {
            guard let function = library.makeFunction(name: name) else {
                print("Function \(name) not found")
                return nil
            }
            return try? device.makeComputePipelineState(function: function)
        }

        basicAdjustmentsState = makeState("basicAdjustmentsKernel")
        hslState = makeState("hslKernel")
        curveState = makeState("curveKernel")
        grainState = makeState("grainKernel")
        linearGradientState = makeState("linearGradientKernel")
        radialGradientState = makeState("radialGradientKernel")
        blendState = makeState("blendWithMaskKernel")
    }

    // MARK: - Auto Enhance Analysis (CIFilter - kept for image analysis only)

    func analyzeAutoEnhance(for image: CIImage) -> Adjustments {
        let filters = image.autoAdjustmentFilters(options: [
            .enhance: true,
            .redEye: false
        ])

        var autoAdjustments = Adjustments()

        for filter in filters {
            if filter.name == "CIExposureAdjust" {
                if let ev = filter.value(forKey: kCIInputEVKey) as? Double {
                    autoAdjustments.exposure = ev
                }
            } else if filter.name == "CIVibrance" {
                if let amount = filter.value(forKey: kCIInputAmountKey) as? Double {
                    autoAdjustments.saturation += amount * 0.5
                }
            } else if filter.name == "CIToneCurve" {
                autoAdjustments.contrast += 0.1
            } else if filter.name == "CIHighlightShadowAdjust" {
                if let highlight = filter.value(forKey: "inputHighlightAmount") as? Double {
                    autoAdjustments.highlights = (highlight - 1.0)
                }
                if let shadow = filter.value(forKey: "inputShadowAmount") as? Double {
                    autoAdjustments.shadows = shadow
                }
            }
        }

        autoAdjustments.exposure = min(max(autoAdjustments.exposure, -2.0), 2.0)
        autoAdjustments.saturation = min(max(autoAdjustments.saturation, 0.0), 2.0)
        autoAdjustments.contrast = min(max(autoAdjustments.contrast, 0.5), 1.5)
        autoAdjustments.highlights = min(max(autoAdjustments.highlights, -1.0), 1.0)
        autoAdjustments.shadows = min(max(autoAdjustments.shadows, -1.0), 1.0)

        return autoAdjustments
    }

    // MARK: - Main Processing

    func process(_ inputImage: CIImage, with edits: EditState) -> CIImage {
        // 1. Crop
        var processedInput = inputImage
        let extent = processedInput.extent

        if edits.cropRect.width > 0 && edits.cropRect.height > 0 && edits.cropRect != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let cropRect = CGRect(
                x: extent.origin.x + extent.width * edits.cropRect.origin.x,
                y: extent.origin.y + extent.height * edits.cropRect.origin.y,
                width: extent.width * edits.cropRect.width,
                height: extent.height * edits.cropRect.height
            )
            processedInput = processedInput.cropped(to: cropRect)
        }

        // 2. Convert CIImage → UIImage for GPUImage3
        guard let cgImage = ciContext.createCGImage(processedInput, from: processedInput.extent) else {
            return inputImage
        }
        var resultImage = UIImage(cgImage: cgImage)

        // 3. GPUImage3 pipeline: global adjustments + filter
        resultImage = applyGPUImagePipeline(input: resultImage, edits: edits)

        // 4. Metal post-processing: HSL, curves, grain, masks (if needed)
        let needsMetalPost = !edits.adjustments.hsl.isEmpty
            || edits.adjustments.curve != .identity
            || collectGrain(from: edits) > 0
            || !edits.masks.isEmpty

        if needsMetalPost {
            resultImage = applyMetalPostProcessing(input: resultImage, edits: edits)
        }

        // 5. Convert back to CIImage and apply geometry
        var outputImage = CIImage(image: resultImage) ?? inputImage

        if edits.rotation != 0 {
            outputImage = outputImage.transformed(by: CGAffineTransform(rotationAngle: edits.rotation))
        }
        if edits.flipHorizontal {
            outputImage = outputImage.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        }
        if edits.flipVertical {
            outputImage = outputImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
        }

        return outputImage
    }

    // MARK: - GPUImage3 Pipeline

    private func applyGPUImagePipeline(input: UIImage, edits: EditState) -> UIImage {
        let globalAdj = edits.adjustments
        let filter = edits.filter
        let hasFilter = filter != .original && filter.id != FilterModel.auto.id

        // Check if any GPUImage3 operations are needed
        let needsGPU = globalAdj.exposure != 0 || globalAdj.contrast != 1.0
            || globalAdj.brightness != 0 || globalAdj.saturation != 1.0
            || globalAdj.highlights != 0 || globalAdj.shadows != 0
            || globalAdj.warmth != 0 || globalAdj.tint != 0
            || globalAdj.sharpen != 0 || globalAdj.clarity != 0
            || globalAdj.vignette > 0 || hasFilter

        guard needsGPU else { return input }

        return input.filterWithPipeline { pictureInput, pictureOutput in
            var chain: ImageSource = pictureInput

            // 1. Global adjustments via GPUImage3
            chain = self.buildAdjustmentChain(from: chain, adjustments: globalAdj)

            // 2. Mask layers (processed through GPUImage3 for each mask's adjustments)
            // Note: Masks are handled in Metal post-processing for gradient generation and blending

            // 3. Filter
            if hasFilter {
                // Apply filter's color matrix
                if let m = filter.colorMatrix, m.count == 20 {
                    let cmFilter = ColorMatrixFilter()
                    cmFilter.colorMatrix = Matrix4x4(rowMajorValues: [
                        Float(m[0]),  Float(m[1]),  Float(m[2]),  Float(m[3]),
                        Float(m[4]),  Float(m[5]),  Float(m[6]),  Float(m[7]),
                        Float(m[8]),  Float(m[9]),  Float(m[10]), Float(m[11]),
                        Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15])
                    ])
                    cmFilter.intensity = Float(filter.intensity)
                    chain --> cmFilter
                    chain = cmFilter

                    // Apply bias as brightness offset (approximation for small bias values)
                    let biasR = m[16], biasG = m[17], biasB = m[18]
                    let avgBias = (biasR + biasG + biasB) / 3.0
                    if abs(avgBias) > 0.001 {
                        let brightnessOp = BrightnessAdjustment()
                        brightnessOp.brightness = Float(avgBias)
                        chain --> brightnessOp
                        chain = brightnessOp
                    }
                }

                // Apply filter's preset adjustments
                if let filterAdj = filter.adjustments {
                    chain = self.buildAdjustmentChain(from: chain, adjustments: filterAdj)
                }
            }

            chain --> pictureOutput
        }
    }

    /// Build a chain of GPUImage3 operations from Adjustments parameters
    private func buildAdjustmentChain(from source: ImageSource, adjustments: Adjustments) -> ImageSource {
        var chain = source

        // Exposure
        if adjustments.exposure != 0 {
            let op = ExposureAdjustment()
            op.exposure = Float(adjustments.exposure)
            chain --> op
            chain = op
        }

        // Contrast (clarity contributes to contrast)
        let effectiveContrast = adjustments.contrast + adjustments.clarity * 0.2
        if abs(effectiveContrast - 1.0) > 0.001 {
            let op = ContrastAdjustment()
            op.contrast = Float(effectiveContrast)
            chain --> op
            chain = op
        }

        // Brightness
        if abs(adjustments.brightness) > 0.001 {
            let op = BrightnessAdjustment()
            op.brightness = Float(adjustments.brightness)
            chain --> op
            chain = op
        }

        // Saturation
        if abs(adjustments.saturation - 1.0) > 0.001 {
            let op = SaturationAdjustment()
            op.saturation = Float(adjustments.saturation)
            chain --> op
            chain = op
        }

        // Highlights & Shadows
        if abs(adjustments.highlights) > 0.001 || abs(adjustments.shadows) > 0.001 {
            let op = HighlightsAndShadows()
            // Map: our highlights (-1...1, 0=neutral) → GPUImage3 (0...2, 1.0=neutral)
            op.highlights = Float(1.0 + adjustments.highlights)
            op.shadows = Float(adjustments.shadows)
            chain --> op
            chain = op
        }

        // White Balance (warmth → temperature, tint)
        if abs(adjustments.warmth) > 0.001 || abs(adjustments.tint) > 0.001 {
            let op = WhiteBalance()
            // Map: our warmth (-1...1) → GPUImage3 temperature (3000...7000K, 5000=neutral)
            op.temperature = Float(5000.0 + adjustments.warmth * 2000.0)
            // Map: our tint (-1...1) → GPUImage3 tint (internally divided by 100)
            op.tint = Float(adjustments.tint * 100.0)
            chain --> op
            chain = op
        }

        // Sharpen / Blur (clarity contributes to sharpness)
        let effectiveSharpen = adjustments.sharpen + adjustments.clarity * 0.2
        if effectiveSharpen > 0.01 {
            let op = Sharpen()
            op.sharpness = Float(min(effectiveSharpen * 2.0, 4.0))
            chain --> op
            chain = op
        } else if effectiveSharpen < -0.05 {
            // Negative sharpen → gaussian blur for softening effect
            let op = GaussianBlur()
            op.blurRadiusInPixels = Float(abs(effectiveSharpen) * 3.0)
            chain --> op
            chain = op
        }

        // Vignette
        if adjustments.vignette > 0.001 {
            let op = Vignette()
            op.start = Float(max(0.1, 0.5 - adjustments.vignette * 0.4))
            op.end = Float(max(0.4, 0.75 - adjustments.vignette * 0.45))
            chain --> op
            chain = op
        }

        return chain
    }

    // MARK: - Metal Post-Processing (HSL, Curves, Grain, Masks)

    private func applyMetalPostProcessing(input: UIImage, edits: EditState) -> UIImage {
        guard let cgImage = input.cgImage else { return input }
        let ciImage = CIImage(cgImage: cgImage)
        guard let inputTexture = createTexture(from: ciImage) else { return input }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return input }

        var current = inputTexture

        // Ping-pong buffers
        var bufferA: MTLTexture?
        var bufferB: MTLTexture?

        func dispatch(pipeline: MTLComputePipelineState, setup: (MTLComputeCommandEncoder) -> Void) -> MTLTexture? {
            let output: MTLTexture
            if let a = bufferA, a !== current, a.width == current.width && a.height == current.height {
                output = a
            } else if let b = bufferB, b !== current, b.width == current.width && b.height == current.height {
                output = b
            } else {
                guard let newTex = makeOutputTexture(matching: current) else { return nil }
                if bufferA == nil { bufferA = newTex }
                else { bufferB = newTex }
                output = newTex
            }

            guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(current, index: 0)
            encoder.setTexture(output, index: 1)
            setup(encoder)

            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            encoder.dispatchThreadgroups(
                MTLSizeMake((current.width + w - 1) / w, (current.height + h - 1) / h, 1),
                threadsPerThreadgroup: MTLSizeMake(w, h, 1)
            )
            encoder.endEncoding()
            return output
        }

        // 1. HSL per-channel adjustments
        if !edits.adjustments.hsl.isEmpty, let state = hslState {
            if let output = dispatch(pipeline: state, setup: { encoder in
                func getShift(_ c: HSLChannel) -> (Float, Float, Float) {
                    let s = edits.adjustments.hsl[c] ?? .identity
                    return (Float(s.hue), Float(s.saturation), Float(s.lightness))
                }
                let (hR, sR, lR) = getShift(.red)
                let (hO, sO, lO) = getShift(.orange)
                let (hY, sY, lY) = getShift(.yellow)
                let (hG, sG, lG) = getShift(.green)
                let (hC, sC, lC) = getShift(.cyan)
                let (hB, sB, lB) = getShift(.blue)
                let (hP, sP, lP) = getShift(.purple)
                let (hM, sM, lM) = getShift(.magenta)

                var params = HSLParams(
                    hRed: hR, sRed: sR, lRed: lR,
                    hOrange: hO, sOrange: sO, lOrange: lO,
                    hYellow: hY, sYellow: sY, lYellow: lY,
                    hGreen: hG, sGreen: sG, lGreen: lG,
                    hCyan: hC, sCyan: sC, lCyan: lC,
                    hBlue: hB, sBlue: sB, lBlue: lB,
                    hPurple: hP, sPurple: sP, lPurple: lP,
                    hMagenta: hM, sMagenta: sM, lMagenta: lM
                )
                encoder.setBytes(&params, length: MemoryLayout<HSLParams>.size, index: 0)
            }) {
                current = output
            }
        }

        // 2. Curves
        if edits.adjustments.curve != .identity, let state = curveState {
            if let lutTexture = generateCurveLUT(curve: edits.adjustments.curve) {
                if let output = dispatch(pipeline: state, setup: { encoder in
                    encoder.setTexture(lutTexture, index: 2)
                }) {
                    current = output
                }
            }
        }

        // 3. Grain (from global adjustments + filter adjustments)
        let grain = collectGrain(from: edits)
        if grain > 0, let state = grainState {
            if let output = dispatch(pipeline: state, setup: { encoder in
                var intensity = Float(grain)
                encoder.setBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)
            }) {
                current = output
            }
        }

        // 4. Mask layers
        for mask in edits.masks {
            let size = CGSize(width: Double(current.width), height: Double(current.height))
            if let maskTexture = generateMaskTexture(mask: mask, size: size, commandBuffer: commandBuffer) {
                // Apply mask adjustments to current texture
                if let layerAdjusted = applyMetalAdjustments(to: current, adjustments: mask.adjustments, commandBuffer: commandBuffer),
                   let blended = applyBlend(base: current, overlay: layerAdjusted, mask: maskTexture, commandBuffer: commandBuffer) {
                    current = blended
                }
            }
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Convert MTLTexture → UIImage
        if let outputCI = CIImage(mtlTexture: current, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]),
           let outputCG = ciContext.createCGImage(outputCI, from: outputCI.extent) {
            return UIImage(cgImage: outputCG)
        }
        return input
    }

    /// Collect total grain intensity from global and filter adjustments
    private func collectGrain(from edits: EditState) -> Double {
        var grain = edits.adjustments.grain
        if edits.filter != .original, let filterAdj = edits.filter.adjustments {
            grain = max(grain, filterAdj.grain)
        }
        return grain
    }

    // MARK: - Metal Mask Adjustments (for per-mask processing)

    private func applyMetalAdjustments(to input: MTLTexture, adjustments: Adjustments, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let state = basicAdjustmentsState,
              let output = makeOutputTexture(matching: input),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(state)
        encoder.setTexture(input, index: 0)
        encoder.setTexture(output, index: 1)

        var params = AdjustmentParams(
            exposure: Float(adjustments.exposure),
            contrast: Float(adjustments.contrast + adjustments.clarity * 0.2),
            brightness: Float(adjustments.brightness),
            saturation: Float(adjustments.saturation),
            highlights: Float(adjustments.highlights),
            shadows: Float(adjustments.shadows),
            temperature: Float(adjustments.warmth),
            tint: Float(adjustments.tint)
        )
        encoder.setBytes(&params, length: MemoryLayout<AdjustmentParams>.size, index: 0)

        let w = state.threadExecutionWidth
        let h = state.maxTotalThreadsPerThreadgroup / w
        encoder.dispatchThreadgroups(
            MTLSizeMake((input.width + w - 1) / w, (input.height + h - 1) / h, 1),
            threadsPerThreadgroup: MTLSizeMake(w, h, 1)
        )
        encoder.endEncoding()

        return output
    }

    // MARK: - Metal Mask Generation & Blending

    private func generateMaskTexture(mask: MaskLayer, size: CGSize, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let pipelineState: MTLComputePipelineState
        if mask.type == .linear {
            guard let state = linearGradientState else { return nil }
            pipelineState = state
        } else {
            guard let state = radialGradientState else { return nil }
            pipelineState = state
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        let color0 = mask.isInverted ? SIMD4<Float>(0,0,0,0) : SIMD4<Float>(1,1,1,1)
        let color1 = mask.isInverted ? SIMD4<Float>(1,1,1,1) : SIMD4<Float>(0,0,0,0)

        encoder.setComputePipelineState(pipelineState)

        if mask.type == .linear {
            var params = GradientParams(
                startPoint: SIMD2<Float>(Float(mask.startPoint.x), Float(mask.startPoint.y)),
                endPoint: SIMD2<Float>(Float(mask.endPoint.x), Float(mask.endPoint.y)),
                color0: color0,
                color1: color1
            )
            encoder.setBytes(&params, length: MemoryLayout<GradientParams>.size, index: 0)
        } else {
            let dx = mask.endPoint.x - mask.startPoint.x
            let dy = mask.endPoint.y - mask.startPoint.y
            let radius = sqrt(dx*dx + dy*dy)

            var params = RadialGradientParams(
                center: SIMD2<Float>(Float(mask.startPoint.x), Float(mask.startPoint.y)),
                radius0: 0.0,
                radius1: Float(radius),
                color0: color0,
                color1: color1
            )
            encoder.setBytes(&params, length: MemoryLayout<RadialGradientParams>.size, index: 0)
        }

        encoder.setTexture(texture, index: 0)

        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        encoder.dispatchThreadgroups(
            MTLSizeMake((texture.width + w - 1) / w, (texture.height + h - 1) / h, 1),
            threadsPerThreadgroup: MTLSizeMake(w, h, 1)
        )
        encoder.endEncoding()

        return texture
    }

    private func applyBlend(base: MTLTexture, overlay: MTLTexture, mask: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let state = blendState,
              let output = makeOutputTexture(matching: base),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        encoder.setComputePipelineState(state)
        encoder.setTexture(overlay, index: 0)
        encoder.setTexture(base, index: 1)
        encoder.setTexture(mask, index: 2)
        encoder.setTexture(output, index: 3)

        let w = state.threadExecutionWidth
        let h = state.maxTotalThreadsPerThreadgroup / w
        encoder.dispatchThreadgroups(
            MTLSizeMake((base.width + w - 1) / w, (base.height + h - 1) / h, 1),
            threadsPerThreadgroup: MTLSizeMake(w, h, 1)
        )
        encoder.endEncoding()

        return output
    }

    // MARK: - Texture Helpers

    private func createTexture(from image: CIImage) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(image.extent.width), height: Int(image.extent.height), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        ciContext.render(image, to: texture, commandBuffer: nil, bounds: image.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return texture
    }

    private func makeOutputTexture(matching texture: MTLTexture) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: descriptor)
    }

    private func generateCurveLUT(curve: Curve) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .r32Float
        descriptor.width = 256
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        var values = [Float](repeating: 0, count: 256)

        if curve == .identity {
            for i in 0..<256 {
                values[i] = Float(i) / 255.0
            }
        } else {
            let points = curve.points
            for i in 0..<256 {
                let x = CGFloat(i) / 255.0
                values[i] = Float(interpolate(x: x, points: points))
            }
        }

        let region = MTLRegionMake1D(0, 256)
        texture.replace(region: region, mipmapLevel: 0, withBytes: values, bytesPerRow: 256 * MemoryLayout<Float>.size)

        return texture
    }

    private func interpolate(x: CGFloat, points: [CGPoint]) -> CGFloat {
        if points.isEmpty { return x }
        if x <= points.first!.x { return points.first!.y }
        if x >= points.last!.x { return points.last!.y }

        for i in 0..<points.count-1 {
            let p0 = points[i]
            let p1 = points[i+1]
            if x >= p0.x && x <= p1.x {
                let t = (x - p0.x) / (p1.x - p0.x)
                return p0.y + (p1.y - p0.y) * t
            }
        }
        return x
    }

    // MARK: - Render & Preview

    func render(image: CIImage) -> CGImage? {
        return ciContext.createCGImage(image, from: image.extent)
    }

    func generatePreview(for image: CIImage, edits: EditState, targetSize: CGSize) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) {
            let processed = self.process(image, with: edits)
            guard let cgImage = self.render(image: processed) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
    }
}
