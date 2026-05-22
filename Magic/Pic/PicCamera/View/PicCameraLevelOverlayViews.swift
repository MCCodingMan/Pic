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

struct PicCameraPortraitCompositionGuideView: View {
    let aspectRatio: PicCameraAspectRatio
    let deviceOrientation: UIDeviceOrientation
    let category: PicCameraViewModel.CompositionCategory
    let position: PicCameraViewModel.CompositionPosition?
    let poseName: String?
    var rotationAngle: Angle = .zero

    private var guide: PicCameraPortraitCompositionGuide {
        PicCameraPortraitCompositionGuide(
            aspectRatio: aspectRatio,
            isLandscape: deviceOrientation.isLandscape,
            category: category,
            position: position
        )
    }

    var body: some View {
        GeometryReader { proxy in
            if category == .portrait, let poseName {
                Image(poseName)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.82)
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    .frame(
                        width: proxy.size.width * guide.personSize.width * 2.8,
                        height: proxy.size.height * guide.personSize.height * 2.8
                    )
                    .position(
                        x: proxy.size.width * guide.personCenter.x,
                        y: proxy.size.height * guide.personCenter.y
                    )
            }
        }
    }
}

private struct PicCameraPortraitCompositionGuide {
    enum GuideLine {
        case eyeThird
        case leftThird
        case rightThird
        case lowerThird
    }

    let title: String
    let hint: String
    let personCenter: CGPoint
    let personSize: CGSize
    let zoneCenter: CGPoint
    let zoneSize: CGSize
    let labelCenter: CGPoint
    let line: GuideLine
    let zoneColor: Color

    init(
        aspectRatio: PicCameraAspectRatio,
        isLandscape: Bool,
        category: PicCameraViewModel.CompositionCategory,
        position: PicCameraViewModel.CompositionPosition?
    ) {
        let selectedPosition = position ?? PicCameraViewModel.CompositionPosition
            .recommendations(category: category, aspectRatio: aspectRatio, isLandscape: isLandscape)
            .first ?? .centered
        let ratioName = aspectRatio.displayName(isLandscape: isLandscape)
        let nextTitle = "\(ratioName) \(selectedPosition.rawValue)"
        var nextHint = category.rawValue
        var nextPersonCenter = CGPoint(x: 0.5, y: 0.58)
        var nextPersonSize = CGSize(width: 0.32, height: 0.72)
        var nextZoneSize = CGSize(width: 0.48, height: 0.68)
        var nextLabelCenter = CGPoint(x: 0.5, y: 0.15)
        var nextLine: GuideLine = .eyeThird
        var nextZoneColor: Color = category == .portrait ? .yellow : .green

        if category == .portrait {
            switch (aspectRatio, isLandscape) {
            case (.ratio1x1, _):
                nextHint = "头顶留一点空间"
                nextPersonSize = CGSize(width: 0.42, height: 0.78) // 半身更大
                nextZoneSize = CGSize(width: 0.56, height: 0.76)
                nextZoneColor = .white
                switch selectedPosition {
                case .centered, .eyeThird:
                    nextPersonCenter = CGPoint(x: 0.5, y: 0.56)
                    nextLine = .eyeThird
                default:
                    nextPersonCenter = CGPoint(x: 0.36, y: 0.56) // 略偏一侧≈1/3
                    nextLine = .leftThird
                }
            case (.ratio3x4, false):
                nextHint = "中线略偏下，眼睛靠上 1/3"
                nextPersonSize = CGSize(width: 0.40, height: 0.84)
                nextZoneSize = CGSize(width: 0.56, height: 0.8)
                switch selectedPosition {
                case .leftThird:
                    nextPersonCenter = CGPoint(x: 0.35, y: 0.62)
                    nextLine = .leftThird
                case .rightThird:
                    nextPersonCenter = CGPoint(x: 0.65, y: 0.62)
                    nextLine = .rightThird
                default:
                    nextPersonCenter = CGPoint(x: 0.5, y: 0.62)
                    nextLine = .eyeThird
                }
            case (.ratio9x16, false):
                nextHint = "人物在下半部分，顶部留场景"
                nextLabelCenter = CGPoint(x: 0.5, y: 0.13)
                nextPersonSize = CGSize(width: 0.36, height: 0.78)
                nextZoneSize = CGSize(width: 0.5, height: 0.6)
                nextZoneColor = .cyan
                switch selectedPosition {
                case .leftThird, .leadingSpace:
                    nextPersonCenter = CGPoint(x: 0.33, y: 0.7)
                    nextLine = .leftThird
                case .rightThird:
                    nextPersonCenter = CGPoint(x: 0.67, y: 0.7)
                    nextLine = .rightThird
                default:
                    nextPersonCenter = CGPoint(x: 0.5, y: 0.7)
                    nextLine = .lowerThird
                }
            case (.ratio3x4, true): // 4:3
                nextHint = "人物在左右三分线，自然留环境"
                nextPersonSize = CGSize(width: 0.26, height: 0.68)
                nextZoneSize = CGSize(width: 0.36, height: 0.72)
                nextZoneColor = .green
                switch selectedPosition {
                case .rightThird:
                    nextPersonCenter = CGPoint(x: 0.67, y: 0.58)
                    nextLine = .rightThird
                case .centered:
                    nextPersonCenter = CGPoint(x: 0.54, y: 0.58)
                    nextLine = .eyeThird
                default:
                    nextPersonCenter = CGPoint(x: 0.33, y: 0.58)
                    nextLine = .leftThird
                }
            case (.ratio9x16, true): // 16:9
                nextHint = "人物放左右三分，视线方向留白"
                nextLabelCenter = CGPoint(x: 0.5, y: 0.16)
                nextPersonSize = CGSize(width: 0.24, height: 0.62) // 高度>=1/3
                nextZoneSize = CGSize(width: 0.34, height: 0.72)
                nextZoneColor = .orange
                switch selectedPosition {
                case .rightThird:
                    nextPersonCenter = CGPoint(x: 0.68, y: 0.59)
                    nextLine = .rightThird
                default:
                    nextPersonCenter = CGPoint(x: 0.32, y: 0.59)
                    nextLine = .leftThird
                }
            }
        } else {
            switch selectedPosition {
            case .centered:
                nextPersonCenter = CGPoint(x: 0.5, y: 0.58)
                nextLine = .eyeThird
            case .slightSide:
                nextPersonCenter = CGPoint(x: 0.42, y: 0.56)
                nextLine = .eyeThird
            case .lowerThird:
                nextPersonCenter = CGPoint(x: isLandscape ? 0.5 : 0.34, y: 0.69)
                nextLine = .lowerThird
            case .leftThird, .leadingSpace:
                nextPersonCenter = CGPoint(x: 0.33, y: isLandscape ? 0.57 : 0.62)
                nextLine = .leftThird
            case .rightThird:
                nextPersonCenter = CGPoint(x: 0.67, y: isLandscape ? 0.57 : 0.62)
                nextLine = .rightThird
            case .eyeThird:
                nextPersonCenter = CGPoint(x: 0.5, y: 0.58)
                nextLine = .eyeThird
            case .foreground:
                nextPersonCenter = CGPoint(x: 0.38, y: 0.72)
                nextLine = .lowerThird
            case .horizonThird:
                nextPersonCenter = CGPoint(x: 0.5, y: 0.62)
                nextLine = .eyeThird
            case .wideScene:
                nextPersonCenter = CGPoint(x: isLandscape ? 0.28 : 0.36, y: 0.62)
                nextLine = .leftThird
            }
        }

        title = nextTitle
        hint = nextHint
        personCenter = nextPersonCenter
        personSize = category == .portrait ? nextPersonSize : CGSize(width: nextPersonSize.width * 0.72, height: nextPersonSize.height * 0.72)
        zoneCenter = nextPersonCenter
        zoneSize = nextZoneSize
        labelCenter = nextLabelCenter
        line = nextLine
        zoneColor = nextZoneColor
    }
}

private struct PicCameraPersonGuideShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path { path in
            let headRadius = rect.width * 0.16
            let headCenter = CGPoint(x: rect.midX, y: rect.minY + headRadius * 1.15)
            path.addEllipse(in: CGRect(
                x: headCenter.x - headRadius,
                y: headCenter.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            ))

            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.28))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.63))

            path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.43))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY + rect.height * 0.43))

            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.63))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY))
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.63))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY))
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
