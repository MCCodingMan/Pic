import SwiftUI
internal import AVFoundation

struct PicCameraTopBarView: View {
    @Environment(\.colorScheme) private var scheme

    let viewModel: PicCameraViewModel
    let buttonRotationAngle: Angle
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                    .frame(width: 36, height: 36)
                    .background(DS.ColorToken.surface(scheme))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(DS.ColorToken.outline(scheme), lineWidth: 0.5)
                    )
                    .dsShadow(.level2)
                    .rotationEffect(buttonRotationAngle)
            }
            .buttonStyle(.plain)

            topActionScroller
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var topActionScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(visibleToolbarActions) { action in
                    topBarButton(for: action)
                }

                gridToggleButton
                aspectRatioToggleButton
                levelToggleButton

                if viewModel.mode == .portrait {
                    apertureToggleButton
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .background(DS.ColorToken.surface(scheme))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DS.ColorToken.outline(scheme), lineWidth: 0.5)
        )
        .dsShadow(.level2)
        .frame(height: 40)
    }

    private func topBarButton(for action: PicCameraViewModel.ToolbarAction) -> some View {
        Button {
            handleToolbarAction(action)
            viewModel.showToolbarHint(toolbarHint(for: action))
        } label: {
            Image(systemName: iconName(for: action))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(foregroundColor(for: action))
                .frame(width: 30, height: 30)
                .background(viewModel.isToolbarActionActive(action) ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : .clear)
                .clipShape(Circle())
                .rotationEffect(buttonRotationAngle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(for: action))
    }

    private var apertureToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleApertureControl()
            }
            viewModel.showToolbarHint("光圈")
        } label: {
            Image(systemName: "camera.aperture")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(viewModel.isApertureControlVisible ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8))
                .frame(width: 30, height: 30)
                .background(viewModel.isApertureControlVisible ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : .clear)
                .clipShape(Circle())
                .rotationEffect(buttonRotationAngle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("光圈")
    }

    private var gridToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleGrid()
            }
            viewModel.showToolbarHint("网格：\(viewModel.isGridEnabled ? "开" : "关")")
        } label: {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(viewModel.isGridEnabled ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8))
                .frame(width: 30, height: 30)
                .background(viewModel.isGridEnabled ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : .clear)
                .clipShape(Circle())
                .rotationEffect(buttonRotationAngle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("网格")
    }

    private var aspectRatioToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.cycleAspectRatio()
            }
            viewModel.showToolbarHint("显示比例 \(viewModel.aspectRatio.rawValue)")
        } label: {
            Image(systemName: aspectRatioIconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(viewModel.aspectRatio == .ratio9x16 ? DS.ColorToken.textPrimary(scheme).opacity(0.8) : DS.ColorToken.accent(scheme))
                .frame(width: 30, height: 30)
                .background(viewModel.aspectRatio == .ratio9x16 ? .clear : DS.ColorToken.brandPrimary(scheme).opacity(0.1))
                .clipShape(Circle())
                .rotationEffect(buttonRotationAngle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("显示比例")
    }

    private var levelToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.toggleLevel()
            }
            viewModel.showToolbarHint("水平仪：\(viewModel.isLevelEnabled ? "开" : "关")")
        } label: {
            Image(systemName: "level")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(viewModel.isLevelEnabled ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8))
                .frame(width: 30, height: 30)
                .background(viewModel.isLevelEnabled ? DS.ColorToken.brandPrimary(scheme).opacity(0.1) : .clear)
                .clipShape(Circle())
                .rotationEffect(buttonRotationAngle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("水平仪")
    }

    private var visibleToolbarActions: [PicCameraViewModel.ToolbarAction] {
        viewModel.toolbarActions.filter { action in
            switch action {
            case .flash:
                viewModel.supportsFlash
            case .livePhoto:
                viewModel.supportsLivePhoto && viewModel.mode != .portrait
            default:
                true
            }
        }
    }

    private func handleToolbarAction(_ action: PicCameraViewModel.ToolbarAction) {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch action {
            case .beauty:
                viewModel.toggleBeautyPanel()
            case .quickBeauty:
                viewModel.toggleQuickBeautyPanel()
            case .adjust:
                viewModel.toggleAdjustPanel()
            case .filter:
                viewModel.toggleFilterPanel()
            case .autoFilter:
                viewModel.toggleAutoFilter()
            case .flash:
                viewModel.toggleFlash()
            case .livePhoto:
                viewModel.toggleLivePhoto()
            case .settings:
                viewModel.isShowingSettings = true
            }
        }
    }

    private func iconName(for action: PicCameraViewModel.ToolbarAction) -> String {
        switch action {
        case .flash:
            flashIconName
        default:
            action.icon
        }
    }

    private func title(for action: PicCameraViewModel.ToolbarAction) -> String {
        switch action {
        case .beauty:
            return "美颜"
        case .quickBeauty:
            return "快捷美颜"
        case .adjust:
            return "调节"
        case .filter:
            return "滤镜"
        case .autoFilter:
            return "自动滤镜"
        case .flash:
            return "闪光灯"
        case .livePhoto:
            return "实况照片"
        case .settings:
            return "设置"
        }
    }

    private func toolbarHint(for action: PicCameraViewModel.ToolbarAction) -> String {
        switch action {
        case .flash:
            return "闪光灯：\(flashStateText)"
        case .livePhoto:
            return "实况照片：\(viewModel.isLivePhotoEnabled ? "开" : "关")"
        case .autoFilter:
            return "自动滤镜：\(viewModel.isAutoFilterEnabled ? "开" : "关")"
        case .beauty, .quickBeauty, .adjust, .filter:
            return "\(title(for: action))：\(viewModel.isToolbarActionActive(action) ? "开" : "关")"
        case .settings:
            return title(for: action)
        }
    }

    private func foregroundColor(for action: PicCameraViewModel.ToolbarAction) -> Color {
        switch action {
        case .beauty:
            return viewModel.activePanel == .beauty || viewModel.isBeautyModified ? DS.ColorToken.accent(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .quickBeauty:
            return viewModel.activePanel == .quickBeauty || viewModel.beautyIntensity > 0.001 ? DS.ColorToken.accent(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .adjust:
            return viewModel.activePanel == .adjust || !viewModel.adjustments.isDefault ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .filter:
            return viewModel.activePanel == .filter || viewModel.isFilterModified ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .autoFilter:
            return viewModel.isAutoFilterEnabled ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .flash:
            return flashTintColor
        case .livePhoto:
            return viewModel.isLivePhotoEnabled ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .settings:
            return DS.ColorToken.textPrimary(scheme).opacity(0.8)
        }
    }

    private var flashIconName: String {
        switch viewModel.flashMode {
        case .off:
            return "bolt.slash.fill"
        case .auto:
            return "bolt.badge.a.fill"
        case .on:
            return "bolt.fill"
        @unknown default:
            return "bolt.slash.fill"
        }
    }

    private var flashTintColor: Color {
        switch viewModel.flashMode {
        case .off:
            return DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .auto:
            return DS.ColorToken.accent(scheme)
        case .on:
            return DS.ColorToken.warning(scheme)
        @unknown default:
            return DS.ColorToken.textPrimary(scheme).opacity(0.8)
        }
    }

    private var flashStateText: String {
        switch viewModel.flashMode {
        case .off:
            return "关"
        case .auto:
            return "自动"
        case .on:
            return "开"
        @unknown default:
            return "关"
        }
    }

    private var aspectRatioIconName: String {
        switch viewModel.aspectRatio {
        case .ratio1x1:
            return "square"
        case .ratio3x4:
            return "rectangle.ratio.3.to.4"
        case .ratio9x16:
            return "rectangle.ratio.9.to.16"
        }
    }
}
