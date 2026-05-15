import SwiftUI

struct PersonIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let lineWidth = w * 0.06 // 描边粗细由外部控制，这里只画路径
        
        var path = Path()
        
        // ========== 头部（圆形）==========
        let headRadius = w * 0.19
        let headCenterX = w * 0.5
        let headCenterY = h * 0.22
        
        path.addEllipse(in: CGRect(
            x: headCenterX - headRadius,
            y: headCenterY - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        
        // ========== 身体（U 形 / 倒拱门）==========
        let bodyTop = h * 0.47          // 肩膀顶部 Y
        let bodyBottom = h * 0.95       // 身体底部 Y
        let bodyLeft = w * 0.13         // 身体左边 X
        let bodyRight = w * 0.87        // 身体右边 X
        let bodyWidth = bodyRight - bodyLeft
        let cornerRadius = bodyWidth * 0.5  // 顶部半圆弧度
        
        // 从左下角开始，逆时针画 U 形（开口朝下）
        path.move(to: CGPoint(x: bodyLeft, y: bodyBottom))
        // 左侧竖线
        path.addLine(to: CGPoint(x: bodyLeft, y: bodyTop + cornerRadius))
        // 顶部圆弧（肩膀）
        path.addArc(
            center: CGPoint(x: w * 0.5, y: bodyTop + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        // 右侧竖线
        path.addLine(to: CGPoint(x: bodyRight, y: bodyBottom))
        
        // ========== 两条腿（两条竖线）==========
        let legTop = h * 0.68
        let legBottom = h * 0.95
        let leftLegX = w * 0.37
        let rightLegX = w * 0.63
        
        // 左腿
        path.move(to: CGPoint(x: leftLegX, y: legTop))
        path.addLine(to: CGPoint(x: leftLegX, y: legBottom))
        
        // 右腿
        path.move(to: CGPoint(x: rightLegX, y: legTop))
        path.addLine(to: CGPoint(x: rightLegX, y: legBottom))
        
        return path
    }
}

// MARK: - 使用示例
struct PersonIconView: View {
    var body: some View {
        PersonIconShape()
            .stroke(style: StrokeStyle(
                lineWidth: 12,
                lineCap: .round,
                lineJoin: .round
            ))
            .foregroundColor(.black)
            .frame(width: 200, height: 280)
            .padding(40)
    }
}

