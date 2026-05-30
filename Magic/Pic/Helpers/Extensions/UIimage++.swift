//
//  UIimage++.swift
//  Magic
//
//  Created by CoderWan on 2026/4/2.
//

import UIKit
import CoreImage

private enum CIImageRenderContext {
    nonisolated static let context = CIContext(options: [.cacheIntermediates: false])
    
}

extension UIImage {
    enum CropError: Error {
        case cropError
        case rotateError
    }
    
    var haveAlpha: Bool {
        guard let alphaInfo = self.cgImage?.alphaInfo else { return false }
        return alphaInfo == .first || alphaInfo == .last ||
        alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
    }
    
    
    
    nonisolated func cropped(toAspect aspect: CGFloat?) throws -> UIImage {
        guard let aspect, let cgImage = cgImage else {
            throw CropError.cropError
        }
        
        let orientation = imageOrientation
        let isSideways = orientation == .left || orientation == .right
        || orientation == .leftMirrored || orientation == .rightMirrored
        
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let pixelAspect = isSideways ? (1.0 / aspect) : aspect
        
        let cropWidth: CGFloat
        let cropHeight: CGFloat
        if pixelWidth / pixelHeight > pixelAspect {
            cropHeight = pixelHeight
            cropWidth = cropHeight * pixelAspect
        } else {
            cropWidth = pixelWidth
            cropHeight = cropWidth / pixelAspect
        }
        
        let cropRect = CGRect(
            x: ((pixelWidth - cropWidth) / 2).rounded(),
            y: ((pixelHeight - cropHeight) / 2).rounded(),
            width: cropWidth.rounded(),
            height: cropHeight.rounded()
        )
        
        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            throw CropError.cropError
        }
        return UIImage(cgImage: croppedImage, scale: scale, orientation: orientation)
    }
    
    func cropImage(with frame: CGRect,
                   angle: CGFloat) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = !self.haveAlpha
        format.scale = self.scale
        let renderer = UIGraphicsImageRenderer(size: frame.size, format: format)
        let croppedImage = renderer.image { context in
            let context = context.cgContext
            context.translateBy(x: -frame.origin.x, y: -frame.origin.y)
            self.draw(at: .zero)
        }
        if let croppedCgImage = croppedImage.cgImage {
            let cropImage = UIImage(cgImage: croppedCgImage,
                                    scale: self.scale,
                                    orientation: .up)
            return try cropImage.rotated(by: angle)
        }
        throw CropError.cropError
    }
    
    
    /// 旋转UIImage到指定角度
    /// - Parameter degrees: 要旋转的角度（以度为单位）
    /// - Returns: 旋转后的UIImage
    func rotated(by degrees: CGFloat) throws -> UIImage {
        // 将角度转换为弧度
        let radians = -degrees * .pi / 180
        
        // 计算旋转后的图像尺寸
        var newSize = CGRect(origin: .zero, size: self.size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        // 开始图像上下文
        UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else {
            throw CropError.rotateError
        }
        
        // 移动坐标中心到图像中心
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        // 旋转上下文
        context.rotate(by: radians)
        // 绘制原始图像
        self.draw(in: CGRect(x: -self.size.width / 2, y: -self.size.height / 2, width: self.size.width, height: self.size.height))
        
        // 获取旋转后的图像
        if let rotatedImage = UIGraphicsGetImageFromCurrentImageContext() {
            return rotatedImage
        }
        throw CropError.rotateError
    }
}


extension CIImage {
    nonisolated func cropCIImage(aspectRatio: CGFloat) -> CIImage {
        let imageWidth = extent.width
        let imageHeight = extent.height
        let imageAspectRatio = imageWidth / imageHeight
        
        let cropRect: CGRect
        
        if imageAspectRatio > aspectRatio {
            // 图像比目标比例更"宽" → 限制宽度，高度不变
            let cropWidth = imageHeight * aspectRatio
            let cropX = extent.minX + (imageWidth - cropWidth) / 2
            cropRect = CGRect(x: cropX, y: extent.minY, width: cropWidth, height: imageHeight)
        } else {
            // 图像比目标比例更"高" → 限制高度，宽度不变
            let cropHeight = imageWidth / aspectRatio
            let cropY = extent.minY + (imageHeight - cropHeight) / 2
            cropRect = CGRect(x: extent.minX, y: cropY, width: imageWidth, height: cropHeight)
        }
        
        return cropped(to: cropRect)
    }
    
    nonisolated var uiImage: UIImage {
        let translated = transformed(
            by: CGAffineTransform(
                translationX: -extent.origin.x,
                y: -extent.origin.y
            )
        )
        let renderRect = CGRect(origin: .zero, size: translated.extent.size).integral
        guard let cgImage = CIImageRenderContext.context.createCGImage(translated, from: renderRect) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}
