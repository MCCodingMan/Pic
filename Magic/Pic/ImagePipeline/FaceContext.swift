import Foundation
import CoreGraphics
import Vision

/// 统一的人脸上下文：编辑器（Vision）与相机实时（AVMetadata）共用同一个数据契约。
/// 下游磨皮 / 美白 / 瘦脸 / 遮罩生成只消费 FaceContext，不再自行调用 Vision。
nonisolated struct FaceContext: Sendable {
    enum Source: Sendable {
        case vision        // 高精度 Vision (含 landmarks)
        case avMetadata    // 实时 AVCaptureMetadataOutput (仅 box)
        case none
    }

    struct Face: @unchecked Sendable {
        /// 归一化坐标 (Vision 坐标系：原点左下，y 向上)
        var boundingBox: CGRect
        /// Vision 关键点（实时检测时为 nil）
        var observation: VNFaceObservation?
    }

    var faces: [Face]
    var imageSize: CGSize           // 像素尺寸（已 orientation-normalized）
    var source: Source

    nonisolated static let empty = FaceContext(faces: [], imageSize: .zero, source: .none)

    var isEmpty: Bool { faces.isEmpty }
    var hasLandmarks: Bool { faces.contains { $0.observation?.landmarks != nil } }

    /// 仅 box（用于走 rect-only 路径）
    var rects: [CGRect] { faces.map { $0.boundingBox } }
    /// 仅 observations（用于需要 landmarks 的路径，例如 MLS 瘦脸）
    var observations: [VNFaceObservation] { faces.compactMap { $0.observation } }
}
