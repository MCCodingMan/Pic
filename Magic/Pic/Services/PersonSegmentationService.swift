import UIKit
import Vision
import Metal
import MetalKit
import CoreImage
import CoreVideo
import GPUImage

/// 人物整体分割服务（基于 Vision `VNGeneratePersonSegmentationRequest`）
///
/// 对齐关键点：
/// 1. **Orientation 归一化**：UIImage.orientation 不是 .up 时，`image.cgImage` 是未旋转的原始像素，
///    直接丢给 Vision 会得到错位 mask。此处先用 UIGraphicsImageRenderer 重绘一张 orientation=.up
///    的归一化图，再跑 Vision。
/// 2. **Y 轴方向**：美颜 pipeline 的输入纹理通过 `MTKTextureLoader(origin:.bottomLeft)` 加载，
///    personMask 必须用同样的 origin 加载，否则会上下镜像。对 GPUImage 的 PictureInput（topLeft）
///    路径，调用方可显式传 `.topLeft`。
nonisolated enum PersonSegmentationService {

    /// 生成人物分割 MTLTexture（同步，应在后台 Task 中调用）。
    /// - Parameters:
    ///   - image: 输入图
    ///   - quality: Vision 分割质量档位
    ///   - origin: 纹理 Y 轴原点，需与消费该 mask 的 pipeline 的输入纹理保持一致
    ///     - `.bottomLeft`：`BeautyPreviewPipeline`（MTKTextureLoader 路径）
    ///     - `.topLeft`：GPUImage `filterWithPipeline` 路径（PictureInput）
    static func generateMaskTexture(for image: UIImage,
                                    quality: VNGeneratePersonSegmentationRequest.QualityLevel = .accurate,
                                    origin: MTKTextureLoader.Origin = .bottomLeft) -> MTLTexture? {

        // 1) orientation 归一化 —— 把像素真正旋转到与显示一致
        let normalized = normalized(image)
        guard let cgImage = normalized.cgImage else { return nil }

        // 2) Vision 分割（在归一化后的像素上跑，mask 与显示朝向一致）
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("PersonSegmentationService perform 失败: \(error)")
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let maskPixelBuffer = observation.pixelBuffer

        // 3) Vision 返回的 mask 可能小于原图，缩放到 cgImage 尺寸
        let targetSize = CGSize(width: cgImage.width, height: cgImage.height)
        let ciMask = CIImage(cvPixelBuffer: maskPixelBuffer)
        let sx = targetSize.width / ciMask.extent.width
        let sy = targetSize.height / ciMask.extent.height
        let scaled = ciMask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        // 3.1) 羽化：先内缩（erode）再高斯模糊，让边缘过渡带变宽 ~短边 1.5%
        //      - erode 用 CIMorphologyMinimum：避免模糊后美白溢出到背景
        //      - 过渡带越宽，分割感越弱，但太宽会丢失细节
        let rect = CGRect(origin: .zero, size: targetSize)
        let shortSide = min(targetSize.width, targetSize.height)
        let erodeRadius = max(1.0, shortSide * 0.004)      // 约 4‰ 内缩
        let blurRadius  = max(2.0, shortSide * 0.015)      // 约 1.5% 羽化
        let feathered = scaled
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: erodeRadius])
            .applyingFilter("CIGaussianBlur",      parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: rect)

        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let scaledCG = context.createCGImage(feathered, from: rect) else { return nil }

        // 4) 通过 MTKTextureLoader 按调用方指定的 origin 加载，
        //    确保与消费侧输入纹理 Y 方向一致
        let loader = MTKTextureLoader(device: sharedMetalRenderingDevice.device)
        let opts: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .origin: origin
        ]
        return try? loader.newTexture(cgImage: scaledCG, options: opts)
    }

    /// 把 UIImage 真正旋转成 orientation = .up 的新图。orientation 已是 .up 的直接返回。
    private static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - 1×1 白色 Fallback
    //
    // 当人物分割失败或未运行时，shader 仍然要绑定 personMask 纹理。
    // 1×1 白纹理在任何 UV 采样下都返回 1.0 → 等价于不做分割。

    static let whiteFallbackTexture: MTLTexture = {
        let device = sharedMetalRenderingDevice.device
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                            width: 1, height: 1, mipmapped: false)
        desc.usage = [.shaderRead]
        let tex = device.makeTexture(descriptor: desc)!
        var pixel: [UInt8] = [255, 255, 255, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: &pixel, bytesPerRow: 4)
        return tex
    }()
}
