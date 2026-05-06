//
//  SiderAlbum.TailorViewModel.swift
//  Sider
//
//  Created by CoderWan on 2024/12/13.
//

import SwiftUI

struct RotateState {
    var rawValue: Int = 0
    
    mutating func next() {
        rawValue -= 90
    }
    
    var isVertical: Bool {
        -rawValue % 180 == 0
    }
    
    var rotateType: RotateStateType {
        switch -rawValue % 360 {
        case 0: return .rotate0
        case 90: return .rotate90
        case 180: return .rotate180
        case 270: return .rotate270
        default: return .rotate0
        }
    }
    
    mutating func reset() {
        rawValue = 0
    }
}

enum RotateStateType: Int {
    case rotate0 = 0
    case rotate90 = -90
    case rotate180 = -180
    case rotate270 = -270
    
    var transformRotate: CGFloat {
        switch self {
        case .rotate0: return 0
        case .rotate90: return 90
        case .rotate180: return 180
        case .rotate270: return -90
        }
    }
}

@Observable
final class TailorViewViewModel {
    // 第一次进来裁剪框的位置
    var firstCropRect: CGRect = .zero
    // 裁剪框的位置，比例
    var cropRect: CGRect = .zero
    
    var rotateState = RotateState()
    
    @ObservationIgnored @ReadWriteLock
    var croppedImageMap: [Date: UIImage] = [:]
    
    @ObservationIgnored
    var lastCropDate: Date
    // 裁剪区域的大小
    @ObservationIgnored
    var tailorSize: CGSize = .zero {
        didSet {
            let tailorRatio = tailorSize.width / tailorSize.height
            let imageRatio = imageSize.width / imageSize.height
            
            // 第一次进来，获取裁剪框的位置比例
            if imageRatio > tailorRatio { // 横放
                // 图片放在裁剪区域缩小或者放大的倍数
                let widthRatio = imageSize.width / tailorSize.width
                // 图片在裁剪区域中的实际的高度
                let imageShowHeight = imageSize.height / widthRatio
                // 图片在视图上的实际大小，缩放比例为1倍的情况
                normalImageSize = CGSize(width: tailorSize.width, height: imageShowHeight)
                firstNormalImageSize = normalImageSize
                // 图片在裁剪区域中占的比例
                let imageHeightRatio = imageShowHeight / tailorSize.height
                // 图片允许的最小高度比例
                let minHeightRatio = 54 / tailorSize.height
                // 如果高度比例比最小高度比例小，则需要把图片放大到最小比例
                if imageHeightRatio < minHeightRatio {
                    let scale = minHeightRatio / imageHeightRatio
                    imageScale = scale
                    // 获得裁剪框的位置比例
                    cropRect = CGRect(x: 0,
                                      y: (1 - minHeightRatio) / 2,
                                      width: 1,
                                      height: minHeightRatio)
                } else {
                    // 获得裁剪框的位置比例
                    cropRect = CGRect(x: 0,
                                      y: (1 - imageHeightRatio) / 2,
                                      width: 1,
                                      height: imageHeightRatio)
                }
            } else { // 纵放
                // 图片放在裁剪区域缩小或者放大的倍数
                let heightRatio = imageSize.height / tailorSize.height
                // 图片在裁剪区域中的实际的高度
                let imageShowWidth = imageSize.width / heightRatio
                // 图片在视图上的实际大小，缩放比例为1倍的情况
                normalImageSize = CGSize(width: imageShowWidth, height: tailorSize.height)
                firstNormalImageSize = normalImageSize
                // 图片在裁剪区域中占的比例
                let imageWidthRatio = imageShowWidth / tailorSize.width
                // 最小宽度比例
                let minWidthRatio = 54 / tailorSize.width
                // 如果宽度比例比最小宽度比例小，则需要把图片放大到最小比例
                if imageWidthRatio < minWidthRatio {
                    let scale = minWidthRatio / imageWidthRatio
                    imageScale = scale
                    // 获得裁剪框的位置比例
                    cropRect = CGRect(x: (1 - minWidthRatio) / 2,
                                      y: 0,
                                      width: minWidthRatio,
                                      height: 1)
                } else {
                    // 获得裁剪框的位置比例
                    cropRect = CGRect(x: (1 - imageWidthRatio) / 2,
                                      y: 0,
                                      width: imageWidthRatio,
                                      height: 1)
                }
            }
            firstCropRect = cropRect
        }
    }
    let originalImage: UIImage
    // 图片的大小，分辨率
    let imageSize: CGSize
    // 图片在视图上的实际大小，缩放比例为1倍的情况, 用于回到初始状态
    var firstNormalImageSize: CGSize = .zero
    // 图片在视图上的实际大小，缩放比例为1倍的情况
    var normalImageSize: CGSize = .zero
    // 图片位置
    var currentOffset: CGPoint = .zero
    // 记录上一次的位置
    @ObservationIgnored
    var lastOffset: CGPoint = .zero
    // 图片缩放比例
    var imageScale: CGFloat = 1.0
    // 记录上一次的缩放比例
    @ObservationIgnored
    var lastImageScale: CGFloat = 1.0
    @ObservationIgnored
    var isSelfAdjust = false
    
    var adjustRotate: Int = 0
    
    init(image: UIImage) {
        self.originalImage = image
        self.imageSize = image.size
        let date = Date()
        self.lastCropDate = date
        self.croppedImageMap = [date: image]
    }
    
    func reset() {
        withAnimation {
            cropRect = firstCropRect
            currentOffset = .zero
            lastOffset = .zero
            imageScale = 1.0
            lastImageScale = 1.0
            rotateState.reset()
            normalImageSize = firstNormalImageSize
        }
    }
    
    func adjustSizeAndPosition() {
        if !isSelfAdjust {
            limitSize()
            limitPosition()
        } else {
            isSelfAdjust = false
        }
    }
    
    /// 刷新缩放比例
    /// - Parameter value: 变化量
    func freshScale(with value: CGFloat) {
        imageScale = lastImageScale * value
        currentOffset = lastOffset * value
    }
    
    /// 刷新当前偏移量
    /// - Parameter value: 偏移量大小
    func freshOffset(with value: CGSize) {
        currentOffset = lastOffset + value
    }
    
    /// 旋转
    func rotate() {
        rotateState.next()
        //            rotateCropRect()
    }
    
    // 检查图片，调整图片的位置
    func limitPosition() {
        // 获取到当前图片实际展示的大小
        let showImageSize = normalImageSize * imageScale
        // 获取图片当前的Rect
        let imageMinX = currentOffset.x - (showImageSize.width - tailorSize.width) / 2
        let imageMinY = currentOffset.y - (showImageSize.height - tailorSize.height) / 2
        let imageMaxX = imageMinX + showImageSize.width
        let imageMaxY = imageMinY + showImageSize.height
        
        // 裁剪框的Rect
        let limitMinX = tailorSize.width * cropRect.minX
        let limitMinY = tailorSize.height * cropRect.minY
        let limitMaxX = tailorSize.width * cropRect.maxX
        let limitMaxY = tailorSize.height * cropRect.maxY
        
        // 对比Rect
        var realx = currentOffset.x
        if limitMinX < imageMinX {
            realx = currentOffset.x + limitMinX - imageMinX
        } else if limitMaxX > imageMaxX {
            realx = currentOffset.x + limitMaxX - imageMaxX
        }
        var realy = currentOffset.y
        if limitMinY < imageMinY {
            realy = currentOffset.y + limitMinY - imageMinY
        } else if limitMaxY > imageMaxY {
            realy = currentOffset.y + limitMaxY - imageMaxY
        }
        withAnimation {
            currentOffset = CGPoint(x: realx, y: realy)
            lastOffset = currentOffset
        }
    }
    
    // 检查宽高调整图片的缩放比例
    func limitSize() {
        // 获取到当前图片实际展示的大小
        let showImageSize = normalImageSize * imageScale
        // 宽度比例
        let widthRatio = showImageSize.width / tailorSize.width
        // 高度比例
        let heightRatio = showImageSize.height / tailorSize.height
        /*
         // 这段代码也是对的，不过不去确定赋值相同的值会不会引起刷新，所以暂时不用
         imageScale = max(imageScale, imageScale * max(cropRect.width / widthRatio, cropRect.height / heightRatio))
         lastImageScale = imageScale
         */
        // 判断一下是否需要放大，只要裁剪框的宽度或者高度 > 当前图片的宽高
        
        withAnimation {
            if cropRect.width > widthRatio || cropRect.height > heightRatio {
                if cropRect.width / widthRatio > cropRect.height / heightRatio {
                    // 宽度为标准放大
                    imageScale = imageScale * cropRect.width / widthRatio
                    currentOffset = currentOffset * cropRect.width / widthRatio
                } else {
                    // 高度为标准放大
                    imageScale = imageScale * cropRect.height / heightRatio
                    currentOffset = currentOffset * cropRect.height / heightRatio
                }
            }
            lastImageScale = imageScale
        }
    }
    
    /// 裁剪框移动到屏幕中间
    func cropAreaMoveToCenter() {
        Task {
            lastCropDate = Date()
            // 移动到中间的偏移量
            let centerOffsetRatio = cropRect.center - CGPoint(x: 0.5, y: 0.5)
            // 移动之后的裁剪位置
            let centerCropRectRatio = CGRect(x: cropRect.minX - centerOffsetRatio.x,
                                             y: cropRect.minY - centerOffsetRatio.y,
                                             width: cropRect.width,
                                             height: cropRect.height)
            
            // 取宽和高最小的缩放比例
            let scaleRatio = min(1 / cropRect.width, 1 / cropRect.height)
            // 调整后的裁剪框大小
            let adjustedSizeRatio = centerCropRectRatio.size * scaleRatio
            
            let adjustedCropRect = CGRect(origin: CGPoint(x: (1 - adjustedSizeRatio.width) / 2,
                                                          y: (1 - adjustedSizeRatio.height) / 2),
                                          size: adjustedSizeRatio)
            
            // 移动的距离
            let moveOffset = lastOffset - centerOffsetRatio * tailorSize
            isSelfAdjust = true
            withAnimation {
                cropRect = adjustedCropRect
                imageScale = lastImageScale * scaleRatio
                lastImageScale = imageScale
                currentOffset = moveOffset * scaleRatio
                lastOffset = currentOffset
            }
            cropImage()
        }
    }
    
    /// 旋转裁剪框
    func rotateCropRect() {
        normalImageSize = normalImageSize.flip()
        // 得到实际的宽高
        let realSize = cropRect.size * tailorSize
        // 翻转宽高
        let reverSize = realSize.flip()
        // 翻转后的比例
        let reverSizeRatio = reverSize / tailorSize
        // 翻转后不放大的比例
        let adjustedCropRectNotScale = CGRect(origin: CGPoint(x: (1 - reverSizeRatio.width) / 2,
                                                              y: (1 - reverSizeRatio.height) / 2),
                                              size: reverSizeRatio)
        // 取宽和高最小的缩放比例
        let scaleRatio = min(1 / reverSizeRatio.width, 1 / reverSizeRatio.height)
        // 调整后的裁剪框大小
        let adjustedSizeRatio = reverSizeRatio * scaleRatio
        
        let adjustedCropRect = CGRect(origin: CGPoint(x: (1 - adjustedSizeRatio.width) / 2,
                                                      y: (1 - adjustedSizeRatio.height) / 2),
                                      size: adjustedSizeRatio)
        
        let newOffset = lastOffset * scaleRatio
        
        isSelfAdjust = true
        // 先保存没有放大的尺寸，做无痕动画
        cropRect = adjustedCropRectNotScale
        currentOffset = CGPoint(x: lastOffset.y, y: -lastOffset.x)
        withAnimation {
            cropRect = adjustedCropRect
            imageScale = lastImageScale * scaleRatio
            lastImageScale = imageScale
            currentOffset = CGPoint(x: newOffset.y, y: -newOffset.x)
            lastOffset = currentOffset
        }
    }
    
    func getNewestCroppedImage(_ complete: @escaping (UIImage?) -> Void) {
        let cropMap = self.croppedImageMap
        let lastCropDateTemp = self.lastCropDate
        Task.detached(priority: .userInitiated) {
            var waitTime = 20
            while waitTime > 0 {
                if let key = cropMap.keys.first {
                    if key.isNewerOrSameThanDate(date: lastCropDateTemp) {
                        complete(cropMap[key])
                        return
                    }
                }
                try? await Task.sleep(for: .seconds(0.05))
                waitTime -= 1
            }
            complete(nil)
        }
    }
    
    func cropImage() {
        let realimageSize = {
            let imageRatio = imageSize.height / imageSize.width
            let cropRatio = tailorSize.height / tailorSize.width
            if imageRatio < cropRatio {
                if rotateState.isVertical {
                    return CGSize(width: tailorSize.width * imageScale,
                                  height: imageRatio * tailorSize.width * imageScale)
                } else {
                    return CGSize(width: imageRatio * tailorSize.width * imageScale,
                                  height: tailorSize.width * imageScale)
                }
            } else {
                if rotateState.isVertical {
                    return CGSize(width: tailorSize.height / imageRatio * imageScale,
                                  height: tailorSize.height * imageScale)
                } else {
                    return CGSize(width: tailorSize.height * imageScale,
                                  height: tailorSize.height / imageRatio * imageScale)
                }
            }
        }()
        
        let imageMinx = currentOffset.x - (realimageSize.width - tailorSize.width) / 2
        let imageMiny = currentOffset.y - (realimageSize.height - tailorSize.height) / 2
        let imageMaxx = imageMinx + realimageSize.width
        let imageMaxy = imageMiny + realimageSize.height
        
        let limitMinx = tailorSize.width * cropRect.minX
        let limitMiny = tailorSize.height * cropRect.minY
        let limitMaxx = tailorSize.width * cropRect.maxX
        let limitMaxy = tailorSize.height * cropRect.maxY
        
        let zeroRectRatio = CGRect(x: (limitMinx - imageMinx) / (imageMaxx - imageMinx),
                                   y: (limitMiny - imageMiny) / (imageMaxy - imageMiny),
                                   width: (limitMaxx - limitMinx) / (imageMaxx - imageMinx),
                                   height: (limitMaxy - limitMiny) / (imageMaxy - imageMiny))
        
        var cRect = CGRect.zero
        
        if rotateState.rotateType == .rotate270 {
            cRect = CGRect(x: zeroRectRatio.origin.y * originalImage.size.width,
                           y: (1 - zeroRectRatio.maxX) * originalImage.size.height,
                           width: zeroRectRatio.height * originalImage.size.width,
                           height: zeroRectRatio.width * originalImage.size.height)
        } else if rotateState.rotateType == .rotate180 {
            cRect = CGRect(x: (1 - zeroRectRatio.maxX) * originalImage.size.width,
                           y: (1 - zeroRectRatio.maxY) * originalImage.size.height,
                           width: zeroRectRatio.width * originalImage.size.width,
                           height: zeroRectRatio.height * originalImage.size.height)
        } else if rotateState.rotateType == .rotate90 {
            cRect = CGRect(x: (1 - zeroRectRatio.maxY) * originalImage.size.width,
                           y: zeroRectRatio.minX * originalImage.size.height,
                           width: zeroRectRatio.height * originalImage.size.width,
                           height: zeroRectRatio.width * originalImage.size.height)
        } else {
            cRect = CGRect(x: zeroRectRatio.origin.x * originalImage.size.width,
                           y: zeroRectRatio.origin.y * originalImage.size.height,
                           width: zeroRectRatio.width * originalImage.size.width,
                           height: zeroRectRatio.height * originalImage.size.height)
        }
        Task.detached(priority: .background) {[self] in
            await $croppedImageMap.update { map in
                map.removeAll()
            }
            let date = Date()
            let image = await (try? originalImage.cropImage(with: cRect, angle: rotateState.rotateType.transformRotate)) ?? originalImage
            if await date.isNewerOrSameThanDate(date: lastCropDate) {
                await $croppedImageMap.update { map in
                    if let key = map.keys.first {
                        if date.isNewerOrSameThanDate(date: key) {
                            map.removeAll()
                            map[date] = image
                        }
                    } else {
                        map[date] = image
                    }
                }
            }
        }
    }
}

fileprivate extension CGSize {
    static func *(lhs: Self, rhs: CGFloat) -> Self {
        return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    
    static func *(lhs: Self, rhs: Self) -> Self {
        return CGSize(width: lhs.width * rhs.width, height: lhs.height * rhs.height)
    }
    
    static func /(lhs: Self, rhs: Self) -> Self {
        return CGSize(width: lhs.width / rhs.width, height: lhs.height / rhs.height)
    }
    
    static func /(lhs: Self, rhs: CGFloat) -> Self {
        return CGSize(width: lhs.width / rhs, height: lhs.height / rhs)
    }
    
    func flip() -> Self {
        CGSize(width: height, height: width)
    }
}


fileprivate extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
    
    static func *(lhs: Self, rhs: CGSize) -> Self {
        return CGRect(x: lhs.minX * rhs.width,
                      y: lhs.minY * rhs.height,
                      width: lhs.width * rhs.width,
                      height: lhs.height * rhs.height)
    }
    
    static func +(lhs: Self, rhs: CGPoint) -> Self {
        return CGRect(x: lhs.minX * rhs.x,
                      y: lhs.minY * rhs.y,
                      width: lhs.width,
                      height: lhs.height)
    }
}

fileprivate extension CGPoint {
    static func +(lhs: Self, rhs: CGSize) -> Self {
        return CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height)
    }

    static func *(lhs: Self, rhs: CGSize) -> Self {
        return CGPoint(x: lhs.x * rhs.width, y: lhs.y * rhs.height)
    }
    
    static func /(lhs: Self, rhs: CGSize) -> Self {
        return CGPoint(x: lhs.x / rhs.width, y: lhs.y / rhs.height)
    }
    
    static func -(lhs: Self, rhs: CGPoint) -> Self {
        return CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    
    static func +(lhs: Self, rhs: CGPoint) -> Self {
        return CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    static func *(lhs: Self, rhs: CGFloat) -> Self {
        return CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
    
    static func /(lhs: Self, rhs: CGFloat) -> Self {
        return CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }
    
    func flip() -> Self {
        CGPoint(x: y, y: x)
    }
}
