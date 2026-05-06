import UIKit
import Vision
import CoreImage
import Metal

/// 统一的人脸遮罩生成器，替代 BeautyView 与 BeautyCameraProcessor 中各自重复的实现。
///
/// 优先级：
/// 1. 若 `FaceContext` 含有 landmarks（`source == .vision`）→ 走精准轮廓路径（faceContour + 额头延伸 + 高斯羽化）
/// 2. 否则走 rect 径向渐变 fallback（实时相机 / AVMetadata 路径）
///
/// 输出 UIImage（白=磨皮区域，黑=非脸部）。
enum FaceMaskGenerator {

    /// 主入口：根据 FaceContext 生成 UIImage 遮罩。
    static func generate(size: CGSize, context: FaceContext) -> UIImage {
        if context.hasLandmarks {
            return generateFromLandmarks(size: size, observations: context.observations)
        }
        return generateFromRects(size: size, rects: context.rects)
    }

    /// 生成 MTLTexture 版本（封装 createMaskTexture 逻辑，与 BeautyView 中的等价）
    static func generateTexture(size: CGSize, context: FaceContext, device: MTLDevice) -> MTLTexture? {
        let image = generate(size: size, context: context)
        return makeTexture(from: image, device: device)
    }

    // MARK: - landmarks 精准路径

    private static func generateFromLandmarks(size: CGSize,
                                               observations: [VNFaceObservation]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let hardMask = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            for face in observations {
                let box = face.boundingBox
                let path = UIBezierPath()
                var contourPixelPoints: [CGPoint] = []

                if let contour = face.landmarks?.faceContour {
                    for pt in contour.normalizedPoints {
                        let px = (box.origin.x + CGFloat(pt.x) * box.width) * size.width
                        let py = (1.0 - (box.origin.y + CGFloat(pt.y) * box.height)) * size.height
                        contourPixelPoints.append(CGPoint(x: px, y: py))
                    }
                }

                var foreheadPoints: [CGPoint] = []
                if let leftBrow = face.landmarks?.leftEyebrow {
                    for pt in leftBrow.normalizedPoints {
                        let px = (box.origin.x + CGFloat(pt.x) * box.width) * size.width
                        let py = (1.0 - (box.origin.y + CGFloat(pt.y) * box.height)) * size.height
                        foreheadPoints.append(CGPoint(x: px, y: py))
                    }
                }
                if let rightBrow = face.landmarks?.rightEyebrow {
                    for pt in rightBrow.normalizedPoints {
                        let px = (box.origin.x + CGFloat(pt.x) * box.width) * size.width
                        let py = (1.0 - (box.origin.y + CGFloat(pt.y) * box.height)) * size.height
                        foreheadPoints.append(CGPoint(x: px, y: py))
                    }
                }

                guard !contourPixelPoints.isEmpty else { continue }

                let browMinY = foreheadPoints.map(\.y).min() ?? contourPixelPoints.map(\.y).min() ?? 0
                let foreheadY = browMinY - box.height * size.height * 0.15

                let firstContour = contourPixelPoints.first!
                let lastContour = contourPixelPoints.last!

                path.move(to: firstContour)
                for pt in contourPixelPoints.dropFirst() { path.addLine(to: pt) }
                path.addLine(to: CGPoint(x: lastContour.x, y: foreheadY))
                path.addLine(to: CGPoint(x: firstContour.x, y: foreheadY))
                path.close()

                UIColor.white.setFill()
                path.fill()
            }
        }

        guard let cgMask = hardMask.cgImage else { return hardMask }
        let ciMask = CIImage(cgImage: cgMask)
        let blurRadius = min(size.width, size.height) * 0.03
        guard let blurred = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: ciMask,
            kCIInputRadiusKey: blurRadius
        ])?.outputImage else { return hardMask }

        let context = CIContext()
        let extent = ciMask.extent
        guard let outputCG = context.createCGImage(blurred, from: extent) else { return hardMask }
        return UIImage(cgImage: outputCG)
    }

    // MARK: - rect 径向渐变路径（fallback / 实时相机）

    private static func generateFromRects(size: CGSize, rects: [CGRect]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            for rect in rects {
                let x = rect.origin.x * size.width
                let y = (1.0 - rect.origin.y - rect.height) * size.height
                let w = rect.width * size.width
                let h = rect.height * size.height
                let expandX = w * 0.1
                let expandY = h * 0.15
                let faceRect = CGRect(x: x - expandX, y: y - expandY,
                                      width: w + expandX * 2, height: h + expandY * 2)
                let center = CGPoint(x: faceRect.midX, y: faceRect.midY)
                let radius = max(faceRect.width, faceRect.height) / 2.0
                let colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.black.cgColor] as CFArray
                let locations: [CGFloat] = [0.0, 0.5, 1.0]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                             colors: colors, locations: locations) {
                    ctx.cgContext.drawRadialGradient(gradient,
                        startCenter: center, startRadius: 0,
                        endCenter: center, endRadius: radius,
                        options: .drawsAfterEndLocation)
                }
            }
        }
    }

    // MARK: - UIImage → MTLTexture

    static func makeTexture(from image: UIImage, device: MTLDevice) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        let w = cgImage.width, h = cgImage.height
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * w
        var pixelData = [UInt8](repeating: 0, count: w * h * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: pixelData, bytesPerRow: bytesPerRow)
        return texture
    }
}
