import UIKit
import CoreImage
import Vision

/// 统一的图片处理编排层 —— 三个调用方（编辑器、美颜页面、美颜相机）的共同入口。
///
/// 设计原则：
/// 1. **不做人脸检测**。所有需要人脸的方法都接收 `FaceContext`，由调用方先调
///    `FaceDetectionService` 取得。
/// 2. **不重写底层 GPU 管线**。Pipeline 负责编排 + 复用，底层仍是
///    `ImageProcessingService`（compute）与 `applyBeautyPipeline`（fragment）。
/// 3. **统一格式契约**。Beauty 高质量永远输出 UIImage；编辑器永远输入/输出 CIImage；
///    实时帧走 RealtimeBeautyPipeline 输出 MTLTexture。
nonisolated final class ImagePipeline: @unchecked Sendable {
    nonisolated static let shared = ImagePipeline()

    private let realtimePipeline: RealtimeBeautyPipeline?
    private let realtimeFilterPipeline: RealtimeCameraFilterPipeline?

    private init() {
        self.realtimePipeline = RealtimeBeautyPipeline()
        self.realtimeFilterPipeline = RealtimeCameraFilterPipeline()
    }

    // MARK: - 编辑器：调整 / 滤镜 / HSL / 曲线 / 遮罩
    nonisolated func processEditor(_ image: CIImage, edits: EditState) -> CIImage {
        ImageProcessingService.shared.process(image, with: edits)
    }

    // MARK: - 美颜（高质量，UIImage 输入输出）
    /// 人脸信息从外部传入，pipeline 不做检测。
    nonisolated func processBeauty(image: UIImage,
                                   params: BeautyParams,
                                   faceContext: FaceContext) -> UIImage {
        guard !params.isIdentity else { return image }
        return applyBeautyPipeline(
            to: image,
            smoothing: params.smoothing,
            whitening: params.whitening,
            whiteningYUV: params.whiteningYUV,
            slimming: params.slimming,
            landmarks: faceContext.observations
        )
    }

    // MARK: - 实时相机帧（CVPixelBuffer → MTLTexture，全 Metal compute）
    nonisolated func processCameraFrame(pixelBuffer: CVPixelBuffer,
                                        params: BeautyParams,
                                        faceContext: FaceContext,
                                        adjustments: Adjustments,
                                        filter: FilterModel) -> MTLTexture? {
        let needsFilter = !adjustments.isDefault || filter.id != "original"
        let beautyTexture: MTLTexture?
        if !params.isIdentity, let realtimePipeline {
            let cpuParams = RealtimeBeautyPipeline.ParamsCPU(
                smoothing: Float(params.smoothing),
                whitening: Float(params.whitening),
                whiteningYUV: Float(params.whiteningYUV),
                faceCount: Int32(min(faceContext.faces.count, 4))
            )
            if needsFilter, realtimePipeline.supportsFusedFilter {
                beautyTexture = realtimePipeline.process(
                    pixelBuffer: pixelBuffer,
                    params: cpuParams,
                    faceContext: faceContext,
                    adjustments: adjustments,
                    filter: filter
                )
                return beautyTexture
            } else {
                beautyTexture = realtimePipeline.process(
                    pixelBuffer: pixelBuffer,
                    params: cpuParams,
                    faceContext: faceContext
                )
            }
        } else {
            beautyTexture = nil
        }

        guard needsFilter else { return beautyTexture }

        return realtimeFilterPipeline?.process(
            pixelBuffer: pixelBuffer,
            sourceTexture: beautyTexture,
            adjustments: adjustments,
            filter: filter
        )
    }
}
