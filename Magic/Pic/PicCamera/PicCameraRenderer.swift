import Foundation
internal import AVFoundation
import Metal
import MetalKit
import CoreImage
import ImageIO

struct PicCameraRenderState: @unchecked Sendable, Equatable {
    var mode: PicCameraMode = .photo
    var beautyParams = BeautyParams()
    var adjustments = Adjustments()
    var filter: FilterModel = .original
    var portraitAperture: Double = 8

    nonisolated static func == (lhs: PicCameraRenderState, rhs: PicCameraRenderState) -> Bool {
        lhs.mode.rawValue == rhs.mode.rawValue &&
        lhs.beautyParams.smoothing == rhs.beautyParams.smoothing &&
        lhs.beautyParams.whitening == rhs.beautyParams.whitening &&
        lhs.beautyParams.whiteningYUV == rhs.beautyParams.whiteningYUV &&
        lhs.beautyParams.slimming == rhs.beautyParams.slimming &&
        lhs.adjustments.exposure == rhs.adjustments.exposure &&
        lhs.adjustments.contrast == rhs.adjustments.contrast &&
        lhs.adjustments.brightness == rhs.adjustments.brightness &&
        lhs.adjustments.highlights == rhs.adjustments.highlights &&
        lhs.adjustments.shadows == rhs.adjustments.shadows &&
        lhs.adjustments.saturation == rhs.adjustments.saturation &&
        lhs.adjustments.warmth == rhs.adjustments.warmth &&
        lhs.adjustments.tint == rhs.adjustments.tint &&
        lhs.adjustments.sharpen == rhs.adjustments.sharpen &&
        lhs.adjustments.clarity == rhs.adjustments.clarity &&
        lhs.adjustments.vignette == rhs.adjustments.vignette &&
        lhs.adjustments.grain == rhs.adjustments.grain &&
        lhs.filter.id == rhs.filter.id &&
        lhs.filter.intensity == rhs.filter.intensity &&
        lhs.portraitAperture == rhs.portraitAperture
    }
}

final class PicCameraRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private struct CameraDisplayParamsCPU {
        var scale: Float
        var offset: SIMD2<Float>
    }

    let device: MTLDevice
    
    nonisolated(unsafe) var canRender: Bool = true

    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let displayPipelineState: MTLComputePipelineState?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()
    private let inFlightSemaphore = DispatchSemaphore(value: 2)
    private weak var renderDestination: MTKView?
    nonisolated(unsafe) private var currentPixelBuffer: CVPixelBuffer?
    nonisolated(unsafe) private var currentDepthData: AVDepthData?
    nonisolated(unsafe) private var lastDepthData: AVDepthData?
    nonisolated(unsafe) private var liveFaceContext: FaceContext = .empty
    nonisolated(unsafe) private var renderState = PicCameraRenderState()
    nonisolated(unsafe) private var requiresDepthForWarmup = false
    nonisolated(unsafe) private var frameSequence: UInt64 = 0
    nonisolated(unsafe) private var stateSequence: UInt64 = 0
    nonisolated(unsafe) private var lastRenderedFrameSequence: UInt64 = 0
    nonisolated(unsafe) private var lastRenderedStateSequence: UInt64 = 0

    static func make() -> PicCameraRenderer? {
        let manager = MetalResourceManager.shared
        return PicCameraRenderer(device: manager.device, commandQueue: manager.commandQueue)
    }

    private init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        let manager = MetalResourceManager.shared
        self.device = device
        self.commandQueue = commandQueue
        self.displayPipelineState = manager.computePipeline(named: "cameraDisplayKernel")
        self.ciContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: [
                .cacheIntermediates: false,
                .workingColorSpace: NSNull(),
                .outputColorSpace: NSNull()
            ]
        )
        super.init()
    }

    func configure(for view: MTKView) {
        renderDestination = view
        view.colorPixelFormat = .bgra8Unorm
        view.sampleCount = 1
        view.framebufferOnly = false
    }

    nonisolated func prepareForModeSwitch(targetMode: PicCameraMode) {
        lock.lock()
        currentPixelBuffer = nil
        currentDepthData = nil
        lastDepthData = nil
        liveFaceContext = .empty
        frameSequence &+= 1
        stateSequence &+= 1
        if targetMode == .portrait {
            requiresDepthForWarmup = true
        } else {
            requiresDepthForWarmup = false
        }
        lock.unlock()
    }

    nonisolated func enqueue(pixelBuffer: CVPixelBuffer, depthData: AVDepthData?) {
        guard canRender else { return }
        lock.lock()
        if requiresDepthForWarmup, depthData == nil {
            currentPixelBuffer = pixelBuffer
            lock.unlock()
            return
        }
        
        currentPixelBuffer = pixelBuffer
        currentDepthData = depthData
        frameSequence &+= 1
        if let depthData {
            lastDepthData = depthData
        }
        lock.unlock()
    }

    nonisolated func updateLiveFaceContext(_ context: FaceContext) {
        lock.lock()
        liveFaceContext = context
        lock.unlock()
    }

    nonisolated func updateRenderState(_ state: PicCameraRenderState) {
        lock.lock()
        guard renderState != state else {
            lock.unlock()
            return
        }
        renderState = state
        stateSequence &+= 1
        lock.unlock()
    }

    nonisolated func currentFaceContextSnapshot() -> FaceContext {
        lock.lock()
        let context = liveFaceContext
        lock.unlock()
        return context
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        autoreleasepool {
            drawFrame()
        }
    }

    private func drawFrame() {
        lock.lock()
        let pixelBuffer = currentPixelBuffer
        let depthData = currentDepthData ?? lastDepthData
        let faceContext = liveFaceContext
        let state = renderState
        let currentFrameSequence = frameSequence
        let currentStateSequence = stateSequence
        lock.unlock()

        guard currentFrameSequence != lastRenderedFrameSequence ||
                currentStateSequence != lastRenderedStateSequence else {
            return
        }

        guard let pixelBuffer,
              let renderDestination else {
            return
        }

        let drawSize = renderDestination.drawableSize
        guard drawSize.width > 0, drawSize.height > 0 else { return }
        guard inFlightSemaphore.wait(timeout: .now()) == .success else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let drawable = renderDestination.currentDrawable else {
            inFlightSemaphore.signal()
            return
        }
        let previewTexture = ImagePipeline.shared.processCameraFrame(
            pixelBuffer: pixelBuffer,
            params: state.beautyParams,
            faceContext: faceContext,
            adjustments: state.adjustments,
            filter: state.filter,
            commandBuffer: commandBuffer
        )

        if state.mode == .portrait, let depthData {
            let previewImage = makePreviewImage(
                from: pixelBuffer,
                depthData: depthData,
                faceContext: faceContext,
                state: state,
                previewTexture: previewTexture
            )
            let finalImage = makeDisplayImage(from: previewImage, drawSize: drawSize)
            ciContext.render(
                finalImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawSize),
                colorSpace: colorSpace
            )
        } else if let previewTexture,
                  !renderTextureToDrawable(
                    previewTexture,
                    drawableTexture: drawable.texture,
                    commandBuffer: commandBuffer,
                    drawSize: drawSize
                  ) {
            let previewImage = PicCameraEffectsProcessor.makePreviewImage(
                pixelBuffer: pixelBuffer,
                beautyParams: state.beautyParams,
                faceContext: faceContext,
                adjustments: state.adjustments,
                filter: state.filter
            )
            let finalImage = makeDisplayImage(from: previewImage, drawSize: drawSize)
            ciContext.render(
                finalImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawSize),
                colorSpace: colorSpace
            )
        } else {
            let previewImage = PicCameraEffectsProcessor.makePreviewImage(
                pixelBuffer: pixelBuffer,
                beautyParams: state.beautyParams,
                faceContext: faceContext,
                adjustments: state.adjustments,
                filter: state.filter
            )
            let finalImage = makeDisplayImage(from: previewImage, drawSize: drawSize)
            ciContext.render(
                finalImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawSize),
                colorSpace: colorSpace
            )
        }

        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        lastRenderedFrameSequence = currentFrameSequence
        lastRenderedStateSequence = currentStateSequence
    }

    private func makePreviewImage(
        from pixelBuffer: CVPixelBuffer,
        depthData: AVDepthData?,
        faceContext: FaceContext,
        state: PicCameraRenderState,
        previewTexture: MTLTexture?
    ) -> CIImage {
        let processedImage: CIImage
        if let previewTexture,
           let ciImage = CIImage(mtlTexture: previewTexture, options: [.colorSpace: colorSpace]) {
            processedImage = ciImage.oriented(.leftMirrored)
        } else {
            processedImage = PicCameraEffectsProcessor.makePreviewImage(
                pixelBuffer: pixelBuffer,
                beautyParams: state.beautyParams,
                faceContext: faceContext,
                adjustments: state.adjustments,
                filter: state.filter
            )
        }

        guard state.mode == .portrait,
              let depthData,
              let fusedImage = depthBlurImage(
                image: processedImage,
                depthData: depthData,
                orientation: .right,
                aperture: state.portraitAperture
              ) else {
            return processedImage
        }

        return fusedImage
    }

    nonisolated func depthBlurImage(
        image: CIImage,
        depthData: AVDepthData,
        orientation: CGImagePropertyOrientation,
        aperture: Double = 8
    ) -> CIImage? {
        let disparityDepthData = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32).applyingExifOrientation(orientation)
        let filter = ciContext.depthBlurEffectFilter(
            for: image,
            disparityImage: disparityDepthData.depthDataMap.ciImage,
            portraitEffectsMatte: nil,
            hairSemanticSegmentation: nil,
            glassesMatte: nil,
            gainMap: nil,
            orientation: orientation,
            options: nil
        )
        filter?.setValue(aperture, forKey: "inputAperture")
        return filter?.outputImage
    }

    private func makeDisplayImage(from image: CIImage, drawSize: CGSize) -> CIImage {
        let scale = max(drawSize.width / image.extent.width, drawSize.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = (drawSize.width - scaled.extent.width) * 0.5 - scaled.extent.origin.x
        let offsetY = (drawSize.height - scaled.extent.height) * 0.5 - scaled.extent.origin.y
        let centered = scaled.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        return centered.cropped(to: CGRect(origin: .zero, size: drawSize))
    }

    private func renderTextureToDrawable(
        _ sourceTexture: MTLTexture,
        drawableTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        drawSize: CGSize
    ) -> Bool {
        guard let displayPipelineState,
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return false
        }
        let srcWidth = Float(sourceTexture.width)
        let srcHeight = Float(sourceTexture.height)
        let dstWidth = Float(drawSize.width)
        let dstHeight = Float(drawSize.height)
        let scale = max(dstWidth / srcWidth, dstHeight / srcHeight)
        let scaledWidth = srcWidth * scale
        let scaledHeight = srcHeight * scale
        let offset = SIMD2<Float>(
            (dstWidth - scaledWidth) * 0.5,
            (dstHeight - scaledHeight) * 0.5
        )
        var params = CameraDisplayParamsCPU(scale: scale, offset: offset)

        encoder.setComputePipelineState(displayPipelineState)
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(drawableTexture, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<CameraDisplayParamsCPU>.stride, index: 0)
        let w = displayPipelineState.threadExecutionWidth
        let h = max(1, displayPipelineState.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreadgroups(
            MTLSize(
                width: (drawableTexture.width + w - 1) / w,
                height: (drawableTexture.height + h - 1) / h,
                depth: 1
            ),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
        return true
    }
}
