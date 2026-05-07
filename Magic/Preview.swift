//
//  Preview.swift
//  Magic
//
//  Created by CoderWan on 2026/4/22.
//

import SwiftUI

struct PersonOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let headSize = w * 0.24
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + h * 0.20)
        let headRect = CGRect(
            x: headCenter.x - headSize * 0.5,
            y: headCenter.y - headSize * 0.5,
            width: headSize,
            height: headSize
        )
        path.addEllipse(in: headRect)

        // Connected body outline (shoulders with slight curve + shaped arms)
        path.move(to: CGPoint(x: rect.midX - w * 0.05, y: rect.minY + h * 0.34)) // neck left
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + w * 0.05, y: rect.minY + h * 0.34), // neck right
            control: CGPoint(x: rect.midX, y: rect.minY + h * 0.31) // connect with head bottom
        )

        path.addCurve(
            to: CGPoint(x: rect.midX + w * 0.21, y: rect.minY + h * 0.43), // right shoulder
            control1: CGPoint(x: rect.midX + w * 0.08, y: rect.minY + h * 0.36),
            control2: CGPoint(x: rect.midX + w * 0.17, y: rect.minY + h * 0.41)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX + w * 0.34, y: rect.minY + h * 0.62), // right hand outer
            control1: CGPoint(x: rect.midX + w * 0.27, y: rect.minY + h * 0.50),
            control2: CGPoint(x: rect.midX + w * 0.33, y: rect.minY + h * 0.57)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + w * 0.27, y: rect.minY + h * 0.67), // right hand inner
            control: CGPoint(x: rect.midX + w * 0.33, y: rect.minY + h * 0.66)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX + w * 0.17, y: rect.minY + h * 0.76), // right waist
            control1: CGPoint(x: rect.midX + w * 0.23, y: rect.minY + h * 0.70),
            control2: CGPoint(x: rect.midX + w * 0.20, y: rect.minY + h * 0.73)
        )
        path.addLine(to: CGPoint(x: rect.midX + w * 0.16, y: rect.minY + h * 0.95))
        path.addLine(to: CGPoint(x: rect.midX + w * 0.04, y: rect.minY + h * 0.95))
        path.addLine(to: CGPoint(x: rect.midX + w * 0.04, y: rect.minY + h * 0.79))
        path.addLine(to: CGPoint(x: rect.midX - w * 0.04, y: rect.minY + h * 0.79))
        path.addLine(to: CGPoint(x: rect.midX - w * 0.04, y: rect.minY + h * 0.95))
        path.addLine(to: CGPoint(x: rect.midX - w * 0.16, y: rect.minY + h * 0.95))
        path.addLine(to: CGPoint(x: rect.midX - w * 0.17, y: rect.minY + h * 0.76)) // left waist
        path.addCurve(
            to: CGPoint(x: rect.midX - w * 0.27, y: rect.minY + h * 0.67), // left hand inner
            control1: CGPoint(x: rect.midX - w * 0.20, y: rect.minY + h * 0.73),
            control2: CGPoint(x: rect.midX - w * 0.23, y: rect.minY + h * 0.70)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - w * 0.34, y: rect.minY + h * 0.62), // left hand outer
            control: CGPoint(x: rect.midX - w * 0.33, y: rect.minY + h * 0.66)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX - w * 0.21, y: rect.minY + h * 0.43), // left shoulder
            control1: CGPoint(x: rect.midX - w * 0.33, y: rect.minY + h * 0.57),
            control2: CGPoint(x: rect.midX - w * 0.27, y: rect.minY + h * 0.50)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX - w * 0.05, y: rect.minY + h * 0.34), // close near neck
            control1: CGPoint(x: rect.midX - w * 0.17, y: rect.minY + h * 0.41),
            control2: CGPoint(x: rect.midX - w * 0.08, y: rect.minY + h * 0.36)
        )

        return path
    }
}

struct Preview: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PersonOutlineShape()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [10, 8]
                    )
                )
                .frame(width: 260, height: 420)
        }
    }
}

#Preview {
    Preview()
}
