import Foundation

/// 统一的美颜参数模型 —— 编辑器、美颜页面、美颜相机共用同一份语义。
struct BeautyParams: Sendable, Equatable {
    var smoothing: Double = 0      // 磨皮 0..1
    var whitening: Double = 0      // 美白 (LUT) 0..1
    var whiteningYUV: Double = 0   // 亮肤 (YUV) 0..1
    var slimming: Double = 0       // 瘦脸 0..1（需要 landmarks）

    nonisolated var isIdentity: Bool {
        smoothing < 0.001 && whitening < 0.001 && whiteningYUV < 0.001 && slimming < 0.001
    }
}
