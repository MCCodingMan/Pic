import SwiftUI
internal import AVFoundation

struct PicCameraSideWavePanelView: View {
    @Environment(\.colorScheme) private var scheme

    let viewModel: PicCameraViewModel
    let buttonRotationAngle: Angle
    @Binding var isPresented: Bool

    @State private var showButtons = false
    @State private var showCapsule = false
    @State private var panelTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            panelContent
                .offset(x: showCapsule ? 0 : 72)
                .opacity(showCapsule ? 1 : 0)
                .allowsHitTesting(isPresented)
        }
        .padding(.trailing, 12)
        .onAppear {
            if isPresented {
                showCapsule = true
            }
        }
        .onChange(of: isPresented) { _, presented in
            panelTask?.cancel()
            if presented {
                showCapsule = true
                showButtons = false
                panelTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled, isPresented else { return }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        showButtons = true
                    }
                }
            } else {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    showButtons = false
                }
                let reverseMaxDelay = Double(max(sideButtons.count - 1, 0)) * 0.045
                let capsuleDelay = UInt64((reverseMaxDelay + 0.18) * 1_000_000_000)
                panelTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: capsuleDelay)
                    guard !Task.isCancelled, !isPresented else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCapsule = false
                    }
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showCapsule)
        .onDisappear {
            panelTask?.cancel()
        }
    }

    private var panelContent: some View {
        let items = sideButtons
        return VStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                sideButton(item: item, delayIndex: index, totalCount: items.count)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    private func sideButton(item: SideButtonItem, delayIndex: Int, totalCount: Int) -> some View {
        let enterDelay = Double(delayIndex) * 0.045
        let exitDelay = Double(max(totalCount - 1 - delayIndex, 0)) * 0.045
        return Button(action: item.action) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 34, height: 34)
                .background(item.isActive ? DS.ColorToken.brandPrimary(scheme).opacity(0.16) : .clear)
                .clipShape(Circle())
                .rotationEffect(buttonRotationAngle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .offset(x: showButtons ? 0 : 34)
        .opacity(showButtons ? 1 : 0)
        .animation(
            .spring(response: 0.34, dampingFraction: 0.84).delay(showButtons ? enterDelay : exitDelay),
            value: showButtons
        )
    }

    private var sideButtons: [SideButtonItem] {
        var items = visibleToolbarActions.map(makeToolbarItem)
        items.append(
            SideButtonItem(
                id: "grid",
                icon: "square.grid.3x3",
                title: "网格",
                tint: viewModel.isGridEnabled ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.86),
                isActive: viewModel.isGridEnabled,
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.toggleGrid() }
                    viewModel.showToolbarHint("网格：\(viewModel.isGridEnabled ? "开" : "关")")
                }
            )
        )
        items.append(
            SideButtonItem(
                id: "ratio",
                icon: aspectRatioIconName,
                title: "显示比例",
                tint: viewModel.aspectRatio == .ratio9x16 ? DS.ColorToken.textPrimary(scheme).opacity(0.86) : DS.ColorToken.accent(scheme),
                isActive: viewModel.aspectRatio != .ratio9x16,
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.cycleAspectRatio() }
                    viewModel.showToolbarHint("显示比例 \(viewModel.aspectRatio.rawValue)")
                }
            )
        )
        items.append(
            SideButtonItem(
                id: "level",
                icon: "level",
                title: "水平仪",
                tint: viewModel.isLevelEnabled ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.86),
                isActive: viewModel.isLevelEnabled,
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) { viewModel.toggleLevel() }
                    viewModel.showToolbarHint("水平仪：\(viewModel.isLevelEnabled ? "开" : "关")")
                }
            )
        )
        if viewModel.mode == .portrait {
            items.append(
                SideButtonItem(
                    id: "aperture",
                    icon: "f.cursive.circle",
                    title: "光圈",
                    tint: viewModel.isApertureControlVisible ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.86),
                    isActive: viewModel.isApertureControlVisible,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) { viewModel.toggleApertureControl() }
                        viewModel.showToolbarHint("光圈")
                    }
                )
            )
        }
        return items
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

    private func makeToolbarItem(for action: PicCameraViewModel.ToolbarAction) -> SideButtonItem {
        SideButtonItem(
            id: action.id,
            icon: iconName(for: action),
            title: title(for: action),
            tint: foregroundColor(for: action),
            isActive: viewModel.isToolbarActionActive(action),
            action: {
                handleToolbarAction(action)
                viewModel.showToolbarHint(toolbarHint(for: action))
            }
        )
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
            "美颜"
        case .quickBeauty:
            "快捷美颜"
        case .adjust:
            "调节"
        case .filter:
            "滤镜"
        case .autoFilter:
            "自动滤镜"
        case .flash:
            "闪光灯"
        case .livePhoto:
            "实况照片"
        case .settings:
            "设置"
        }
    }

    private func toolbarHint(for action: PicCameraViewModel.ToolbarAction) -> String {
        switch action {
        case .flash:
            "闪光灯：\(flashStateText)"
        case .livePhoto:
            "实况照片：\(viewModel.isLivePhotoEnabled ? "开" : "关")"
        case .autoFilter:
            "自动滤镜：\(viewModel.isAutoFilterEnabled ? "开" : "关")"
        case .beauty, .quickBeauty, .adjust, .filter:
            "\(title(for: action))：\(viewModel.isToolbarActionActive(action) ? "开" : "关")"
        case .settings:
            title(for: action)
        }
    }

    private func foregroundColor(for action: PicCameraViewModel.ToolbarAction) -> Color {
        switch action {
        case .beauty:
            viewModel.activePanel == .beauty || viewModel.isBeautyModified ? DS.ColorToken.accent(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .quickBeauty:
            viewModel.activePanel == .quickBeauty || viewModel.beautyIntensity > 0.001 ? DS.ColorToken.accent(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .adjust:
            viewModel.activePanel == .adjust || !viewModel.adjustments.isDefault ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .filter:
            viewModel.activePanel == .filter || viewModel.isFilterModified ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .autoFilter:
            viewModel.isAutoFilterEnabled ? DS.ColorToken.warning(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .flash:
            flashTintColor
        case .livePhoto:
            viewModel.isLivePhotoEnabled ? DS.ColorToken.success(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .settings:
            DS.ColorToken.textPrimary(scheme).opacity(0.8)
        }
    }

    private var flashIconName: String {
        switch viewModel.flashMode {
        case .off:
            "bolt.slash.fill"
        case .auto:
            "bolt.badge.a.fill"
        case .on:
            "bolt.fill"
        @unknown default:
            "bolt.slash.fill"
        }
    }

    private var flashTintColor: Color {
        switch viewModel.flashMode {
        case .off:
            DS.ColorToken.textPrimary(scheme).opacity(0.8)
        case .auto:
            DS.ColorToken.accent(scheme)
        case .on:
            DS.ColorToken.warning(scheme)
        @unknown default:
            DS.ColorToken.textPrimary(scheme).opacity(0.8)
        }
    }

    private var flashStateText: String {
        switch viewModel.flashMode {
        case .off:
            "关"
        case .auto:
            "自动"
        case .on:
            "开"
        @unknown default:
            "关"
        }
    }

    private var aspectRatioIconName: String {
        switch viewModel.aspectRatio {
        case .ratio1x1:
            "square"
        case .ratio3x4:
            "rectangle.ratio.3.to.4"
        case .ratio9x16:
            "rectangle.ratio.9.to.16"
        }
    }
}

private struct SideButtonItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let tint: Color
    let isActive: Bool
    let action: () -> Void
}
