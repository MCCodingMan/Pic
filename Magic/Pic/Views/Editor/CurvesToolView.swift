import SwiftUI

struct CurvesToolView: View {
    @Binding var curve: Curve
    @Binding var isProcessing: Bool
    @Environment(\.colorScheme) var scheme

    @State private var draggingIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let graphWidth = geometry.size.width
            let graphHeight = geometry.size.height

            ZStack {
                // Background
                DS.ColorToken.surfaceAlt(scheme).opacity(0.6)

                // Grid
                CurveGrid()
                    .stroke(DS.ColorToken.outline(scheme).opacity(0.3), lineWidth: 0.5)

                // Diagonal reference line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: graphHeight))
                    path.addLine(to: CGPoint(x: graphWidth, y: 0))
                }
                .stroke(DS.ColorToken.textSecondary(scheme).opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Curve path with smooth Catmull-Rom
                Path { path in
                    let pts = curve.points.map { pt -> CGPoint in
                        CGPoint(x: pt.x * graphWidth, y: (1 - pt.y) * graphHeight)
                    }
                    guard pts.count >= 2 else { return }
                    path.move(to: pts[0])
                    for i in 0..<pts.count - 1 {
                        let p0 = pts[max(0, i - 1)]
                        let p1 = pts[i]
                        let p2 = pts[min(pts.count - 1, i + 1)]
                        let p3 = pts[min(pts.count - 1, i + 2)]
                        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                        path.addCurve(to: p2, control1: cp1, control2: cp2)
                    }
                }
                .stroke(DS.ColorToken.brandPrimary(scheme), lineWidth: 2)

                // Control points
                ForEach(0..<curve.points.count, id: \.self) { index in
                    let pt = curve.points[index]
                    let x = pt.x * graphWidth
                    let y = (1 - pt.y) * graphHeight
                    let isActive = draggingIndex == index

                    Circle()
                        .fill(DS.ColorToken.brandPrimary(scheme))
                        .frame(width: isActive ? 14 : 10, height: isActive ? 14 : 10)
                        .overlay(
                            Circle()
                                .fill(.white)
                                .frame(width: isActive ? 6 : 4, height: isActive ? 6 : 4)
                        )
                        .shadow(color: DS.ColorToken.brandPrimary(scheme).opacity(0.4), radius: isActive ? 6 : 0)
                        .position(x: x, y: y)
                        .allowsHitTesting(false)
                }

                // Touch overlay
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x / graphWidth
                                let y = 1 - (value.location.y / graphHeight)
                                let index = Int(round(x * 4.0))
                                if index >= 0 && index < 5 {
                                    withAnimation(.interactiveSpring()) { draggingIndex = index }
                                    var newPoints = curve.points
                                    newPoints[index] = CGPoint(x: CGFloat(index) * 0.25, y: min(max(y, 0), 1))
                                    curve.points = newPoints
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.2)) { draggingIndex = nil }
                            }
                    )
            }
        }
        .padding(16)
    }
}

struct CurveGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...3 {
            let pos = CGFloat(i) / 4.0
            path.move(to: CGPoint(x: pos * rect.width, y: 0))
            path.addLine(to: CGPoint(x: pos * rect.width, y: rect.height))
            path.move(to: CGPoint(x: 0, y: pos * rect.height))
            path.addLine(to: CGPoint(x: rect.width, y: pos * rect.height))
        }
        return path
    }
}
