import UIKit
import Vision

/// 统一的人脸检测服务。
///
/// 两条入口：
/// - `detectInPhoto(_:)` —— Vision 高精度（带 landmarks），用于编辑器打开图 / 相机拍照后处理。
///   带 revision 3→2→1 fallback。
/// - `contextFromMetadata(rects:imageSize:)` —— 把 AVCaptureMetadataOutput 的 face bounds
///   包成 FaceContext，用于相机实时预览（无 landmarks，仅 box）。
///
/// 调用方拿到 FaceContext 之后，传给 ImagePipeline / FaceMaskGenerator / 瘦脸 等下游消费。
nonisolated enum FaceDetectionService {

    
    // MARK: - 高精度（Vision）

    /// 在后台执行 Vision 高精度人脸 + landmarks 检测。
    static func detectInPhoto(_ image: UIImage) async -> FaceContext {
        await Task.detached(priority: .userInitiated) {
            performVisionDetection(image: image)
        }.value
    }

    /// 同步版本（已经在后台 Task 里时使用）
    static func detectInPhotoSync(_ image: UIImage) -> FaceContext {
        performVisionDetection(image: image)
    }

    private static func performVisionDetection(image: UIImage) -> FaceContext {
        guard let cgImage = image.cgImage else { return .empty }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        var observations: [VNFaceObservation] = []

        let revisions: [Int] = [3, 2, 1]
        for rev in revisions {
            let request = VNDetectFaceLandmarksRequest()
            request.revision = rev
            do {
                try handler.perform([request])
                observations = request.results ?? []
                break
            } catch {
                continue
            }
        }

        let faces = observations.map {
            FaceContext.Face(boundingBox: $0.boundingBox, observation: $0)
        }
        return FaceContext(
            faces: faces,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            source: .vision
        )
    }

    // MARK: - 实时（AVCaptureMetadataOutput）

    /// 把 AVCaptureMetadataOutput.face 的 bounds 包成 FaceContext。
    /// AVMetadata 的 bounds 同样是归一化坐标，但 y 轴向下；调用方需保证已在显示坐标系下转换好。
    static func contextFromMetadata(rects: [CGRect], imageSize: CGSize) -> FaceContext {
        let faces = rects.map {
            FaceContext.Face(boundingBox: $0, observation: nil)
        }
        return FaceContext(faces: faces, imageSize: imageSize, source: .avMetadata)
    }
}
