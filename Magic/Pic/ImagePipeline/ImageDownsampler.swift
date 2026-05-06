import UIKit
import CoreImage

/// 统一的图片降采样工具，替代 BeautyView 与 EditorViewModel 中各自的内联实现。
nonisolated enum ImageDownsampler {

    /// 把 UIImage 等比缩放到长边 ≤ maxDimension。已 fix orientation 的图直接 draw 即可。
    static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let maxDim = max(w, h)
        if maxDim <= maxDimension { return image }
        let scale = maxDimension / maxDim
        let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// CIImage 版本：长边 > maxDimension 时等比缩放。
    static func downsample(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let maxDim = max(extent.width, extent.height)
        if maxDim <= maxDimension { return image }
        let scale = maxDimension / maxDim
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}
