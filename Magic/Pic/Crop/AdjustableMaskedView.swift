//
//  AdjustMaskView.swift
//  Sider
//
//  Created by CoderWan on 2024/12/11.
//

import SwiftUI

struct AdjustableMaskedView: View {
    @Binding var cropRect: CGRect
    let maskedSize: CGSize
    let onEndDrag: () -> Void
    
    var body: some View {
        ZStack {
            AdjustableMaskedShape(
                parentSize: maskedSize,
                radio: 12,
                cropRect: .init(cgRect: cropRect)
            )
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            ResizableView(
                cropRect: $cropRect,
                parentSize: maskedSize,
                onEndDrag: onEndDrag
            )
        }
    }
}

extension AdjustableMaskedView {
    
    struct CropDefaultRectRatio {
        
        let minHeightRatio: CGFloat
        let minWidthRatio: CGFloat
        let ignoreHeight: CGFloat
        let minYRatio: CGFloat
        
        init(parentSize: CGSize) {
            minHeightRatio = 54 / parentSize.height
            minWidthRatio = 54 / parentSize.width
            ignoreHeight = 0
            minYRatio = 0
        }
    }
    
    struct ResizableView: View {
        
        @Binding var cropRect: CGRect
        let parentSize: CGSize
        let onEndDrag: () -> Void
        
        @State var tapPosition: [ResizeHandlePosition] = []
        
        private let defaultRatioConfig: CropDefaultRectRatio
        
        init(cropRect: Binding<CGRect>,
             parentSize: CGSize,
             onEndDrag: @escaping () -> Void) {
            self._cropRect = cropRect
            self.parentSize = parentSize
            self.defaultRatioConfig = CropDefaultRectRatio(parentSize: parentSize)
            self.onEndDrag = onEndDrag
        }
        
        var body: some View {
            ZStack {
                ResizeHandle(position: .top, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .top, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: cropRect.width * parentSize.width / 2, y: -1)
                
                ResizeHandle(position: .right, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .right, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: cropRect.width * parentSize.width + 1, y: cropRect.height * parentSize.height / 2)
                
                ResizeHandle(position: .bottom, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .bottom, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: cropRect.width * parentSize.width / 2, y: cropRect.height * parentSize.height + 1)
                
                ResizeHandle(position: .left, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .left, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: -1, y: cropRect.height * parentSize.height / 2)
                
                ResizeHandle(position: .topLeft, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .topLeft, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: 5, y: 5)
                
                
                ResizeHandle(position: .topRight, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .topRight, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: cropRect.width * parentSize.width - 5, y: 5)
                
                
                ResizeHandle(position: .bottomLeft, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .bottomLeft, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: 5, y: cropRect.height * parentSize.height - 5)
                
                
                ResizeHandle(position: .bottomRight, tapPosition: $tapPosition,
                             onDrag: { updateSize(for: .bottomRight, translation: $0) },
                             onEnd: onEndDrag)
                .position(x: cropRect.width * parentSize.width - 5, y: cropRect.height * parentSize.height - 5)
                
                
            }
            .frame(width: cropRect.width * parentSize.width,
                   height: cropRect.height * parentSize.height)
            .position(x: cropRect.minX * parentSize.width + cropRect.width * parentSize.width / 2,
                      y: cropRect.minY * parentSize.height + cropRect.height * parentSize.height / 2)
        }
        
        private func updateSize(for handle: ResizeHandlePosition, translation: CGSize) {
            var newSize = cropRect.size
            var newPosition = cropRect.origin
            
            let widthRatio = translation.width / parentSize.width
            let heightRatio = translation.height / parentSize.height
            let disableRatio = defaultRatioConfig.ignoreHeight / parentSize.height
            switch handle {
            case .topLeft:
                ReSizeDirection.top(cropRect,
                                    heightRatio,
                                    defaultRatioConfig.minHeightRatio,
                                    defaultRatioConfig.minYRatio)
                .adjust(with: &newPosition, and: &newSize)
                
                ReSizeDirection.left(cropRect,
                                     widthRatio,
                                     defaultRatioConfig.minWidthRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .topRight:
                ReSizeDirection.top(cropRect,
                                    heightRatio,
                                    defaultRatioConfig.minHeightRatio,
                                    defaultRatioConfig.minYRatio)
                .adjust(with: &newPosition, and: &newSize)
                ReSizeDirection.right(cropRect,
                                      widthRatio,
                                      defaultRatioConfig.minWidthRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .bottomLeft:
                ReSizeDirection.bottom(cropRect,
                                       heightRatio,
                                       disableRatio,
                                       defaultRatioConfig.minHeightRatio)
                .adjust(with: &newPosition, and: &newSize)
                ReSizeDirection.left(cropRect,
                                     widthRatio,
                                     defaultRatioConfig.minWidthRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .bottomRight:
                ReSizeDirection.bottom(cropRect,
                                       heightRatio,
                                       disableRatio,
                                       defaultRatioConfig.minHeightRatio)
                .adjust(with: &newPosition, and: &newSize)
                
                ReSizeDirection.right(cropRect,
                                      widthRatio,
                                      defaultRatioConfig.minWidthRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .top:
                ReSizeDirection.top(cropRect,
                                    heightRatio,
                                    defaultRatioConfig.minHeightRatio,
                                    defaultRatioConfig.minYRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .right:
                ReSizeDirection.right(cropRect,
                                      widthRatio,
                                      defaultRatioConfig.minWidthRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .bottom:
                ReSizeDirection.bottom(cropRect,
                                       heightRatio,
                                       disableRatio,
                                       defaultRatioConfig.minHeightRatio)
                .adjust(with: &newPosition, and: &newSize)
            case .left:
                ReSizeDirection.left(cropRect,
                                     widthRatio,
                                     defaultRatioConfig.minWidthRatio)
                .adjust(with: &newPosition, and: &newSize)
            }
            cropRect = CGRect(origin: newPosition, size: newSize)
        }
    }
}

extension AdjustableMaskedView.ResizableView {
    enum ReSizeDirection {
        case left(_ cropRect: CGRect,
                  _ widthRatio: CGFloat,
                  _ minWidthRatio: CGFloat)
        case right(_ cropRect: CGRect,
                   _ widthRatio: CGFloat,
                   _ minWidthRatio: CGFloat)
        case top(_ cropRect: CGRect,
                 _ heightRatio: CGFloat,
                 _ minHeightRatio: CGFloat,
                 _ minYRatio: CGFloat)
        case bottom(_ cropRect: CGRect,
                    _ heightRatio: CGFloat,
                    _ disableRatio: CGFloat,
                    _ minHeightRatio: CGFloat)
        
        func adjust(with newPosition: inout CGPoint,
                    and newSize: inout CGSize) {
            switch self {
            case .left(let originalRect, let widthRatio, let minWidthRatio):
                if newPosition.x + widthRatio < originalRect.maxX - minWidthRatio {
                    newSize.width = max(minWidthRatio, min(newSize.width - widthRatio, originalRect.maxX - 0))
                    newPosition.x = max(0, min(originalRect.maxX - minWidthRatio, newPosition.x + widthRatio))
                }
            case .right(let originalRect, let widthRatio, let minWidthRatio):
                newSize.width = max(minWidthRatio, min(newSize.width + widthRatio, 1 - originalRect.minX - 0))
            case .top(let originalRect, let heightRatio, let minHeightRatio, let minYRatio):
                if newPosition.y + heightRatio < originalRect.maxY - minHeightRatio &&
                    newPosition.y + heightRatio > minYRatio {
                    newSize.height = max(minHeightRatio, newSize.height - heightRatio)
                    newPosition.y = max(minYRatio, min(originalRect.maxY - minHeightRatio, newPosition.y + heightRatio))
                }
            case .bottom(let originalRect, let heightRatio, let disableRatio, let minHeightRatio):
                newSize.height = max(minHeightRatio, min(1 - originalRect.minY - disableRatio, newSize.height + heightRatio))
            }
        }
    }
}

struct CropRect: VectorArithmetic {
    var minX: CGFloat
    var minY: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    // MARK: - Zero 值
    static var zero: CropRect {
        CropRect(minX: 0, minY: 0, width: 0, height: 0)
    }
    
    // MARK: - VectorArithmetic 实现
    static func + (lhs: CropRect, rhs: CropRect) -> CropRect {
        CropRect(
            minX: lhs.minX + rhs.minX,
            minY: lhs.minY + rhs.minY,
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }
    
    static func - (lhs: CropRect, rhs: CropRect) -> CropRect {
        CropRect(
            minX: lhs.minX - rhs.minX,
            minY: lhs.minY - rhs.minY,
            width: lhs.width - rhs.width,
            height: lhs.height - rhs.height
        )
    }
    
    mutating func scale(by rhs: Double) {
        minX *= CGFloat(rhs)
        minY *= CGFloat(rhs)
        width *= CGFloat(rhs)
        height *= CGFloat(rhs)
    }
    
    var magnitudeSquared: Double {
        Double(minX * minX + minY * minY + width * width + height * height)
    }
    
    // MARK: - 转换为 CGRect
    var rect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

extension CropRect {
    init(cgRect: CGRect) {
        self.minX = cgRect.minX
        self.minY = cgRect.minY
        self.width = cgRect.width
        self.height = cgRect.height
    }
}

extension AdjustableMaskedView {
    struct AdjustableMaskedShape: Shape {
        var parentSize: CGSize
        
        var radio: CGFloat
        
        var cropRect: CropRect
        
        private var innerRect: CGRect {
            CGRect(
                x: cropRect.minX * parentSize.width,
                y: cropRect.minY * parentSize.height,
                width: cropRect.width * parentSize.width,
                height: cropRect.height * parentSize.height
            )
        }
        
        typealias AnimatableData = CropRect
        var animatableData: CropRect {
            get { cropRect }
            set { cropRect = newValue }
        }
        
        func path(in size: CGRect) -> Path {
            let newSize = CGRect(x: size.minX - size.width,
                                 y: size.minY - size.height,
                                 width: size.width * 3,
                                 height: size.height * 3)
            var path = Path(newSize)
            path.addRoundedRect(in: innerRect, cornerSize: CGSize(width: radio, height: radio))
            return path
        }
    }
}

extension AdjustableMaskedView {
    struct RectangleTopLeadingShape: Shape {
        let position: ResizeHandlePosition
        let radius: CGFloat
        let size: CGFloat
        func path(in rect: CGRect) -> Path {
            Path { path in
                let maxWH = size
                if position == .topLeft {
                    path.move(to: CGPoint(x: rect.minX, y: maxWH))
                    path.addLine(to: CGPoint(x: rect.minX, y: radius))
                    path.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
                    path.addLine(to: CGPoint(x: maxWH, y: rect.minY))
                } else if position == .topRight {
                    path.move(to: CGPoint(x: rect.maxX - maxWH, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
                    path.addArc(center: CGPoint(x: rect.maxX - radius, y: radius), radius: radius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
                    path.addLine(to: CGPoint(x: rect.maxX, y: maxWH))
                } else if position == .bottomRight {
                    path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - maxWH))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
                    path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
                    path.addLine(to: CGPoint(x: rect.maxX - maxWH, y: rect.maxY))
                } else if position == .bottomLeft {
                    path.move(to: CGPoint(x: maxWH, y: rect.maxY))
                    path.addLine(to: CGPoint(x: radius, y: rect.maxY))
                    path.addArc(center: CGPoint(x: radius, y: rect.maxY - radius), radius: radius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - maxWH))
                }
            }
        }
    }
}

extension AdjustableMaskedView {
    struct ResizeHandle: View {
        let position: ResizeHandlePosition
        @Binding var tapPosition: [ResizeHandlePosition]
        let onDrag: (CGSize) -> Void
        let onEnd: () -> Void
        
        var body: some View {
            switch position {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                RectangleTopLeadingShape(position: position, radius: 12, size: 18)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle().size(CGSize(width: 36, height: 36)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if tapPosition.count == 0 {
                                    tapPosition.append(position)
                                }
                                if tapPosition.contains(position) {
                                    onDrag(value.translation)
                                }
                            }
                            .onEnded { _ in
                                tapPosition.removeAll()
                                onEnd()
                            }
                    )
            default:
                Color.white
                    .frame(width: position == .bottom || position == .top ? 18 : 3,
                           height: position == .bottom || position == .top ? 3 : 18)
                    .contentShape(Rectangle().size(CGSize(width: 36, height: 36)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if tapPosition.count == 0 {
                                    tapPosition.append(position)
                                }
                                if tapPosition.contains(position) {
                                    onDrag(value.translation)
                                }
                            }
                            .onEnded { _ in
                                tapPosition.removeAll()
                                onEnd()
                            }
                    )
            }
        }
    }
}

extension AdjustableMaskedView {
    nonisolated enum ResizeHandlePosition {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, right, bottom, left
        
        var canBothResponse: [ResizeHandlePosition] {
            switch self {
            case .top:
                return [.left, .right, .bottomLeft, .bottom, .bottomRight]
            case .topLeft:
                return [.bottom, .bottomRight, .right]
            case .topRight:
                return [.left, .bottomLeft, .bottom]
            case .left:
                return [.top, .bottom, .topRight, .right, .bottomRight]
            case .right:
                return [.topLeft, .left, .bottomLeft, .top, .bottom]
            case .bottomLeft:
                return [.top, .topRight, .right]
            case .bottom:
                return [.topLeft, .top, .topRight, .left, .right]
            case .bottomRight:
                return [.left, .topLeft, .top]
            }
        }
    }
}
