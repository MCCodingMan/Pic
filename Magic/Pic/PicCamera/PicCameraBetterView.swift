import SwiftUI
import UIKit
internal import AVFoundation

struct PicCameraBetterView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PicCameraViewModel()
    @State private var pinchStartZoomFactor: CGFloat?
    @State private var levelAngle: Double = 0
    @State private var motionReader = PicCameraLevelMotionReader()
    @State private var previewRect: CGRect = .zero
    @State private var previewBlurRadius: CGFloat = 0
    @State private var previewBlurOverlayOpacity: Double = 0
    @State private var selectedMode: PicCameraMode = .photo
    @State private var focusIndicator: FocusIndicator?
    @State private var isFocusIndicatorVisible = false
    @State private var focusIndicatorDismissTask: Task<Void, Never>?
    @State private var isZoomIndicatorVisible = false
    @State private var zoomIndicatorDismissTask: Task<Void, Never>?
    @State private var captureFlashOpacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, DS.ColorToken.surface(.dark)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let renderer = viewModel.renderer {
                VStack(spacing: 0) {
                    previewContainer(renderer: renderer)
                    Spacer(minLength: 12)
                }
            }
        }
        .overlay(alignment: .bottom) {
            PicCameraBetterBottomOverlayView(
                viewModel: viewModel,
                modeBinding: modeBinding,
                buttonRotationAngle: buttonRotationAngle,
                isZoomIndicatorVisible: isZoomIndicatorVisible,
                onPreviewCapturedImage: {
                    guard viewModel.capturedImage != nil else { return }
                    viewModel.isCapturedPreviewPresented = true
                }
            )
        }
        .overlay {
            if captureFlashOpacity > 0 {
                Color.white.opacity(captureFlashOpacity).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if viewModel.deviceOrientation.isLandscape {
                    cameraToast(message: "当前以竖屏构图保存", systemImage: "iphone", kind: .info)
                }
                if let toast = viewModel.cameraToast {
                    cameraToast(message: toast.message, systemImage: toast.systemImage, kind: toast.kind)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 54)
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: viewModel.cameraToast)
        }
        .overlay {
            if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                permissionOverlay
            }
        }
        .task {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            viewModel.updateDeviceOrientation(initialDeviceOrientation)
            motionReader.updateOrientation(viewModel.deviceOrientation)
            await viewModel.onAppear()
            selectedMode = viewModel.mode
            if viewModel.isLevelEnabled { startLevelUpdates() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                let orientation = UIDevice.current.orientation
                guard orientation.isValidInterfaceOrientation else { continue }
                withAnimation(.easeInOut(duration: 0.28)) { viewModel.updateDeviceOrientation(orientation) }
                motionReader.updateOrientation(orientation)
            }
        }
        .onChange(of: viewModel.isLevelEnabled) { _, isEnabled in
            if isEnabled {
                motionReader.updateOrientation(viewModel.deviceOrientation)
                startLevelUpdates()
            } else {
                motionReader.stop()
            }
        }
        .onChange(of: viewModel.isShowingSettings) { _, isShowing in
            if isShowing {
                motionReader.stop()
            } else if viewModel.isLevelEnabled {
                motionReader.updateOrientation(viewModel.deviceOrientation)
                startLevelUpdates()
            }
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            motionReader.stop()
            focusIndicatorDismissTask?.cancel()
            zoomIndicatorDismissTask?.cancel()
            viewModel.persistHistoryIfNeeded()
            viewModel.onDisappear()
        }
        .sheet(isPresented: settingsBinding) {
            PicCameraSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: capturedPreviewBinding) {
            if let image = viewModel.capturedImage {
                PicCameraCapturePreviewView(
                    image: image,
                    onContinue: { viewModel.isCapturedPreviewPresented = false },
                    onOpenAlbum: openPhotosApp,
                    onDone: {
                        viewModel.isCapturedPreviewPresented = false
                        dismiss()
                    }
                )
            }
        }
        .alert("保存失败", isPresented: saveErrorBinding) {
            Button("取消", role: .cancel) { }
            Button("去设置") { openSettings() }
        } message: {
            Text(viewModel.saveErrorMessage.isEmpty ? "无法保存到相册，请检查相册权限。" : viewModel.saveErrorMessage)
        }
        .onChange(of: viewModel.isCapturing) { _, isCapturing in
            if isCapturing { playCaptureFlash() }
        }
    }

    private var modeBinding: Binding<PicCameraMode> {
        Binding(
            get: { selectedMode },
            set: { newValue in
                selectedMode = newValue
                Task { await transitionMode(to: newValue) }
            }
        )
    }

    private var settingsBinding: Binding<Bool> {
        Binding(get: { viewModel.isShowingSettings }, set: { viewModel.isShowingSettings = $0 })
    }

    private var capturedPreviewBinding: Binding<Bool> {
        Binding(get: { viewModel.isCapturedPreviewPresented && viewModel.capturedImage != nil }, set: { viewModel.isCapturedPreviewPresented = $0 })
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { viewModel.isShowingSaveError }, set: { viewModel.isShowingSaveError = $0 })
    }

    private var initialDeviceOrientation: UIDeviceOrientation {
        let orientation = UIDevice.current.orientation
        return orientation.isValidInterfaceOrientation ? orientation : .portrait
    }

    private var buttonRotationAngle: Angle {
        switch viewModel.deviceOrientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return .degrees(0)
        }
    }

    private func previewContent(renderer: PicCameraRenderer) -> some View {
        PicCameraMetalPreview(renderer: renderer, service: viewModel.service, isPaused: viewModel.isShowingSettings)
            .contentShape(.rect)
            .simultaneousGesture(focusGesture())
            .simultaneousGesture(pinchZoomGesture())
            .blur(radius: previewBlurRadius)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .local) }, action: { previewRect = $0 })
            .overlay {
                Rectangle().stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .overlay {
                Rectangle().fill(.black.opacity(previewBlurOverlayOpacity)).allowsHitTesting(false)
            }
            .overlay {
                if viewModel.isGridEnabled {
                    PicCameraGridView().stroke(.white.opacity(0.32), lineWidth: 1).allowsHitTesting(false)
                }
            }
            .overlay {
                if viewModel.isLevelEnabled {
                    if viewModel.deviceOrientation.isLandscape {
                        PicCameraLandscapeLevelView(angle: levelAngle, rotationAngle: buttonRotationAngle)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    } else {
                        PicCameraPortraitLevelView(angle: levelAngle)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
            }
            .overlay {
                if let focusIndicator {
                    FocusIndicatorView()
                        .opacity(isFocusIndicatorVisible ? 1 : 0)
                        .scaleEffect(isFocusIndicatorVisible ? 1 : 1.18)
                        .position(focusIndicator.location)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
    }

    private func previewContainer(renderer: PicCameraRenderer) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            previewContent(renderer: renderer)
                .aspectRatio(viewModel.aspectRatio.portraitAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(PicCameraAspectRatio.ratio9x16.portraitAspect, contentMode: .fit)
    }

    private func focusGesture() -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard previewRect.size.width > 0, previewRect.size.height > 0 else { return }
            showFocusIndicator(at: value.location)
            let normalizedPoint = CGPoint(
                x: min(max(value.location.x / previewRect.size.width, 0), 1),
                y: min(max(value.location.y / previewRect.size.height, 0), 1)
            )
            Task { await viewModel.focus(at: normalizedPoint) }
        }
    }

    private func transitionMode(to newMode: PicCameraMode) async {
        guard newMode != viewModel.mode else {
            selectedMode = viewModel.mode
            return
        }
        viewModel.renderer?.prepareForModeSwitch(targetMode: newMode)
        viewModel.renderer?.canRender = false
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                previewBlurRadius = 18
                previewBlurOverlayOpacity = 0.18
            }
        }

        let switched = await viewModel.switchMode(to: newMode)

        if !switched {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedMode = viewModel.mode
            }
        }
        try? await Task.sleep(for: .seconds(0.8))
        viewModel.renderer?.canRender = true
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.22)) {
                previewBlurRadius = 0
                previewBlurOverlayOpacity = 0
            }
        }
    }

    private func showFocusIndicator(at location: CGPoint) {
        focusIndicatorDismissTask?.cancel()
        focusIndicator = FocusIndicator(location: location)
        isFocusIndicatorVisible = false

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            isFocusIndicatorVisible = true
        }

        focusIndicatorDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                isFocusIndicatorVisible = false
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            focusIndicator = nil
        }
    }

    private func pinchZoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchStartZoomFactor == nil {
                    pinchStartZoomFactor = viewModel.selectedZoomFactor
                }
                showZoomIndicator()
                let baseZoom = pinchStartZoomFactor ?? viewModel.selectedZoomFactor
                viewModel.requestZoomFactor(baseZoom * value)
            }
            .onEnded { _ in
                pinchStartZoomFactor = nil
                Task { await viewModel.flushRequestedZoomFactor() }
                scheduleZoomIndicatorDismiss()
            }
    }

    private func showZoomIndicator() {
        isZoomIndicatorVisible = true
        scheduleZoomIndicatorDismiss()
    }

    private func startLevelUpdates() {
        motionReader.start { angle in
            levelAngle = angle
        }
    }

    private func scheduleZoomIndicatorDismiss() {
        zoomIndicatorDismissTask?.cancel()
        zoomIndicatorDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isZoomIndicatorVisible = false
            }
        }
    }

    private var permissionOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DS.ColorToken.brandPrimary(scheme))

            Text("需要相机权限")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.ColorToken.textPrimary(scheme))

            Text("请在系统设置中允许访问相机后再拍照。")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.ColorToken.textSecondary(scheme))

            HStack(spacing: 10) {
                Button("关闭") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textPrimary(scheme))
                    .frame(width: 96, height: 40)
                    .background(Capsule().fill(DS.ColorToken.surfaceAlt(scheme)))

                Button("去设置") { openSettings() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.onBrand)
                    .frame(width: 112, height: 40)
                    .background(Capsule().fill(DS.ColorToken.brandPrimary(scheme)))
            }
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.ColorToken.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.ColorToken.outline(scheme), lineWidth: 1)
        )
        .dsShadow(.level3)
        .padding(24)
    }

    private func cameraToast(message: String, systemImage: String, kind: PicCameraToast.Kind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(toastForeground(for: kind))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(toastBackground(for: kind)))
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        .dsShadow(.level2)
    }

    private func toastForeground(for kind: PicCameraToast.Kind) -> Color {
        switch kind {
        case .info:
            return DS.ColorToken.textPrimary(scheme)
        case .success, .error:
            return DS.ColorToken.onBrand
        }
    }

    private func toastBackground(for kind: PicCameraToast.Kind) -> Color {
        switch kind {
        case .info:
            return DS.ColorToken.surface(scheme).opacity(0.86)
        case .success:
            return DS.ColorToken.success(scheme).opacity(0.92)
        case .error:
            return DS.ColorToken.danger(scheme).opacity(0.92)
        }
    }

    private func playCaptureFlash() {
        captureFlashOpacity = 0
        withAnimation(.easeOut(duration: 0.08)) {
            captureFlashOpacity = 0.65
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.22)) {
                captureFlashOpacity = 0
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}

private struct PicCameraBetterBottomOverlayView: View {
    @Environment(\.colorScheme) private var scheme

    let viewModel: PicCameraViewModel
    let modeBinding: Binding<PicCameraMode>
    let buttonRotationAngle: Angle
    let isZoomIndicatorVisible: Bool
    let onPreviewCapturedImage: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            panelOrStatus
            quickToolsRow
            captureControlsRow
            modeRow
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var panelOrStatus: some View {
        if let activePanel = viewModel.activePanel {
            panelContent(for: activePanel)
        } else if viewModel.mode == .portrait, viewModel.isApertureControlVisible {
            apertureSliderCard
        } else if isZoomIndicatorVisible {
            statusCard(zoomText(for: viewModel.selectedZoomFactor), systemImage: "arrow.up.left.and.arrow.down.right")
        } else if viewModel.isCapturing {
            statusCard("正在拍摄", systemImage: "camera.fill")
        } else if viewModel.isSavingCapture {
            statusCard("正在保存", systemImage: "square.and.arrow.down.fill")
        } else if viewModel.isConfigurationFailed {
            statusCard("当前设备不支持该拍摄模式", systemImage: "exclamationmark.triangle.fill")
        } else if viewModel.isPortraitDepthUnavailable {
            statusCard("当前设备不支持真实景深", systemImage: "person.crop.rectangle.badge.exclamationmark")
        }
    }

    @ViewBuilder
    private func panelContent(for panel: PicCameraViewModel.ToolPanel) -> some View {
        switch panel {
        case .beauty:
            beautyPanel
        case .quickBeauty:
            quickBeautyPanel
        case .filter:
            filterPanel
        case .adjust:
            adjustPanel
        }
    }

    private var quickToolsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickActionButton(title: "美颜", icon: "sparkles", tint: DS.ColorToken.accent(scheme), active: viewModel.activePanel == .beauty || viewModel.isBeautyModified) {
                    viewModel.toggleBeautyPanel()
                }
                quickActionButton(title: "快捷", icon: "wand.and.stars.inverse", tint: DS.ColorToken.accent(scheme), active: viewModel.activePanel == .quickBeauty || viewModel.beautyIntensity > 0.001) {
                    viewModel.toggleQuickBeautyPanel()
                }
                quickActionButton(title: "调节", icon: "dial.medium", tint: DS.ColorToken.success(scheme), active: viewModel.activePanel == .adjust || !viewModel.adjustments.isDefault) {
                    viewModel.toggleAdjustPanel()
                }
                quickActionButton(title: "滤镜", icon: "camera.filters", tint: DS.ColorToken.warning(scheme), active: viewModel.activePanel == .filter || viewModel.isFilterModified) {
                    viewModel.toggleFilterPanel()
                }
                quickActionButton(title: "自动", icon: "wand.and.stars", tint: DS.ColorToken.warning(scheme), active: viewModel.isAutoFilterEnabled) {
                    viewModel.toggleAutoFilter()
                }
                if viewModel.mode == .portrait {
                    quickActionButton(title: "光圈", icon: "camera.aperture", tint: DS.ColorToken.warning(scheme), active: viewModel.isApertureControlVisible) {
                        viewModel.toggleApertureControl()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func quickActionButton(title: String, icon: String, tint: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
            viewModel.showToolbarHint(title)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? tint : .white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(active ? tint.opacity(0.14) : .white.opacity(0.08)))
            .overlay(Capsule().stroke(active ? tint.opacity(0.48) : .white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var captureControlsRow: some View {
        HStack {
            capturedImageButton
            Spacer(minLength: 24)
            captureButton
            Spacer(minLength: 24)
            switchCameraButton
        }
    }

    @ViewBuilder
    private var capturedImageButton: some View {
        if let image = viewModel.capturedImage {
            Button(action: onPreviewCapturedImage) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCapturing)
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 54, height: 54)
        }
    }

    private var captureButton: some View {
        Button {
            viewModel.capture()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(.white)
                    .frame(width: 62, height: 62)
                if viewModel.isCapturing || viewModel.isSavingCapture {
                    ProgressView().tint(.black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isCapturing || viewModel.isSavingCapture || viewModel.isConfigurationFailed)
        .opacity(viewModel.isCapturing || viewModel.isSavingCapture || viewModel.isConfigurationFailed ? 0.55 : 1)
    }

    private var switchCameraButton: some View {
        Button {
            Task { await viewModel.switchCameraPosition() }
        } label: {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(buttonRotationAngle)
                )
        }
        .buttonStyle(.plain)
    }

    private var modeRow: some View {
        PicSegmentedControl(items: PicCameraMode.allCases, selectedItem: modeBinding, buttonRotationAngle: buttonRotationAngle)
            .padding(.horizontal, 14)
    }

    private var beautyPanel: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PicCameraViewModel.BeautyControl.allCases) { control in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { viewModel.selectBeautyControl(control) }
                        } label: {
                            Text(control.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(viewModel.selectedBeautyControl == control ? DS.ColorToken.accent(scheme) : .white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(viewModel.selectedBeautyControl == control ? DS.ColorToken.accent(scheme).opacity(0.18) : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let selected = viewModel.selectedBeautyControl {
                parameterSlider(
                    value: Binding(
                        get: { viewModel.beautyValue(for: selected) },
                        set: { viewModel.updateBeautyValue(selected, value: $0) }
                    ),
                    range: 0...1
                )
            }
        }
    }

    private var quickBeautyPanel: some View {
        parameterSlider(
            value: Binding(
                get: { viewModel.beautyIntensity },
                set: { viewModel.updateBeautyIntensity($0) }
            ),
            range: 0...1
        )
    }

    private var adjustPanel: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustmentType.allCases) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { viewModel.selectAdjustment(type) }
                        } label: {
                            Text(type.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(viewModel.selectedAdjustment == type ? DS.ColorToken.success(scheme) : .white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(viewModel.selectedAdjustment == type ? DS.ColorToken.success(scheme).opacity(0.18) : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let selected = viewModel.selectedAdjustment {
                parameterSlider(
                    value: Binding(
                        get: { selected.getValue(from: viewModel.adjustments) },
                        set: { viewModel.updateAdjustment(selected, value: $0) }
                    ),
                    range: selected.range,
                    defaultRawValue: selected.defaultValue
                )
            }
        }
    }

    private var filterPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(PicCameraViewModel.FilterPanelCategory.allCases) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { viewModel.selectFilterPanelCategory(category) }
                    } label: {
                        Text(category.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(viewModel.selectedFilterPanelCategory == category ? DS.ColorToken.warning(scheme) : .white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(viewModel.selectedFilterPanelCategory == category ? DS.ColorToken.warning(scheme).opacity(0.18) : .white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.shouldShowFilterOptions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { viewModel.setFilter(.original) }
                        } label: {
                            Text("原图")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(viewModel.selectedFilter == .original ? DS.ColorToken.warning(scheme) : .white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(viewModel.selectedFilter == .original ? DS.ColorToken.warning(scheme).opacity(0.18) : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        ForEach(viewModel.availableFilterItems) { filter in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { viewModel.setFilter(filter) }
                            } label: {
                                Text(filter.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(viewModel.selectedFilter == filter ? DS.ColorToken.warning(scheme) : .white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(viewModel.selectedFilter == filter ? DS.ColorToken.warning(scheme).opacity(0.18) : .white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var apertureSliderCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "f.cursive")
                Text(String(format: "%.1f", viewModel.portraitAperture))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)

            PillSlider(
                value: Binding(
                    get: { viewModel.portraitAperture },
                    set: { viewModel.updatePortraitAperture($0) }
                ),
                range: viewModel.portraitApertureRange,
                tintColor: DS.ColorToken.warning(scheme),
                trackHeight: 32,
                thumbSize: 24,
                valueStr: nil
            )
            .frame(height: 32)
        }
        .padding(.horizontal, 6)
    }

    private func parameterSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        defaultRawValue: Double = 0
    ) -> some View {
        let config = normalizedWaveSliderConfig(from: range)
        let defaultDisplayValue = (min(max(defaultRawValue, config.rawRange.lowerBound), config.rawRange.upperBound) * config.scale).rounded()
        let displayValue = Binding<Double>(
            get: {
                let raw = min(max(value.wrappedValue, config.rawRange.lowerBound), config.rawRange.upperBound)
                return (raw * config.scale).rounded()
            },
            set: { newDisplayValue in
                let clampedDisplay = min(max(newDisplayValue, config.displayRange.lowerBound), config.displayRange.upperBound)
                let raw = clampedDisplay / config.scale
                value.wrappedValue = min(max(raw, config.rawRange.lowerBound), config.rawRange.upperBound)
            }
        )

        return WaveRulerSlider(
            value: displayValue,
            range: config.displayRange,
            step: 1,
            majorTickInterval: 10,
            minorTickInterval: 5,
            showValue: false,
            defaultMarkerValue: defaultDisplayValue
        )
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func normalizedWaveSliderConfig(from inputRange: ClosedRange<Double>) -> (
        rawRange: ClosedRange<Double>,
        displayRange: ClosedRange<Double>,
        scale: Double
    ) {
        let rawLower = min(inputRange.lowerBound, inputRange.upperBound)
        let rawUpper = max(inputRange.lowerBound, inputRange.upperBound)

        let safeRawRange: ClosedRange<Double>
        if rawLower.isFinite, rawUpper.isFinite, (rawUpper - rawLower) > 0.0001 {
            safeRawRange = rawLower...rawUpper
        } else {
            safeRawRange = 0...1
        }

        let span = safeRawRange.upperBound - safeRawRange.lowerBound
        let tickCap = 400.0
        let scale = min(100.0, max(1.0, floor(tickCap / max(span, 0.0001))))

        let displayLower = (safeRawRange.lowerBound * scale).rounded()
        let displayUpper = (safeRawRange.upperBound * scale).rounded()
        let safeDisplayRange: ClosedRange<Double> = displayLower < displayUpper
        ? displayLower...displayUpper
        : displayLower...(displayLower + 1)

        return (safeRawRange, safeDisplayRange, scale)
    }

    private func statusCard(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.12)))
    }

    private func zoomText(for factor: CGFloat) -> String {
        if factor.rounded(.towardZero) == factor {
            return "\(Int(factor))x"
        }
        return String(format: "%.1fx", factor)
    }
}
