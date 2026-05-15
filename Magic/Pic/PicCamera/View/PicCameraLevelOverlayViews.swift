import SwiftUI

struct PicCameraGridView: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path { path in
            let thirdWidth = rect.size.width / 3
            let thirdHeight = rect.size.height / 3

            for index in 1...2 {
                path.move(to: CGPoint(x: CGFloat(index) * thirdWidth, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(index) * thirdWidth, y: rect.size.height))
                path.move(to: CGPoint(x: 0, y: CGFloat(index) * thirdHeight))
                path.addLine(to: CGPoint(x: rect.size.width, y: CGFloat(index) * thirdHeight))
            }
        }
    }
}

struct PicCameraPortraitLevelView: View {
    @Environment(\.colorScheme) private var scheme
    let angle: Double

    private var isLevel: Bool { abs(angle) < 0.03 }
    private var accentColor: Color { isLevel ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(.dark) }

    private var dotOffset: CGFloat {
        let clamped = min(max(angle, -.pi / 6), .pi / 6)
        return CGFloat(clamped) / (.pi / 6) * 50
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(0.25), lineWidth: 1)
                .frame(width: 120, height: 120)

            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(accentColor.opacity(0.3))
                        .frame(width: i == 0 ? 16 : 10, height: 1.5)
                        .padding(.trailing, 6)
                }

                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.5), lineWidth: 1)
                        .frame(width: 8, height: 8)

                    Circle()
                        .fill(accentColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: accentColor.opacity(0.6), radius: isLevel ? 6 : 0)
                        .offset(x: dotOffset)
                }
                .frame(width: 12, height: 12)

                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(accentColor.opacity(0.3))
                        .frame(width: i == 2 ? 16 : 10, height: 1.5)
                        .padding(.leading, 6)
                }
            }

            if isLevel {
                Circle()
                    .stroke(DS.ColorToken.success(scheme).opacity(0.15), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
            }
        }
        .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: angle)
        .animation(.easeInOut(duration: 0.2), value: isLevel)
    }
}

struct PicCameraLandscapeLevelView: View {
    @Environment(\.colorScheme) private var scheme
    let angle: Double
    var rotationAngle: Angle = .zero

    private var isLevel: Bool { abs(angle) < 0.03 }
    private var accentColor: Color { isLevel ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(.dark) }

    private var dotOffset: CGFloat {
        let clamped = min(max(angle, -.pi / 6), .pi / 6)
        return CGFloat(clamped) / (.pi / 6) * 50
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(0.25), lineWidth: 1)
                .frame(width: 120, height: 120)

            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(accentColor.opacity(0.3))
                        .frame(width: i == 0 ? 16 : 10, height: 1.5)
                        .padding(.trailing, 6)
                }

                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.5), lineWidth: 1)
                        .frame(width: 8, height: 8)

                    Circle()
                        .fill(accentColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: accentColor.opacity(0.6), radius: isLevel ? 6 : 0)
                        .offset(x: dotOffset)
                }
                .frame(width: 12, height: 12)

                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(accentColor.opacity(0.3))
                        .frame(width: i == 2 ? 16 : 10, height: 1.5)
                        .padding(.leading, 6)
                }
            }

            if isLevel {
                Circle()
                    .stroke(DS.ColorToken.success(scheme).opacity(0.15), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
            }
        }
        .rotationEffect(rotationAngle)
        .animation(.interpolatingSpring(stiffness: 300, damping: 20), value: angle)
        .animation(.easeInOut(duration: 0.2), value: isLevel)
    }
}
