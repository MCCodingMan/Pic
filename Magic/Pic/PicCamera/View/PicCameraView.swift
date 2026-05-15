import SwiftUI
import UIKit
internal import AVFoundation

struct PicCameraView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PicCameraViewModel()
    @State private var levelAngle: Double = 0
    @State private var motionReader = PicCameraLevelMotionReader()
    @State private var previewRect: CGRect = .zero
    @State private var previewBlurRadius: CGFloat = 0
    @State private var previewBlurOverlayOpacity: Double = 0
    @State private var selectedMode: PicCameraMode = .photo
    @State private var focusIndicator: FocusIndicator?
    @State private var isFocusIndicatorVisible = false
    @State private var focusIndicatorDismissTask: Task<Void, Never>?
    @State private var captureFlashOpacity: Double = 0
    @State private var isSideToolbarVisible = false

    var body: some View {
        ZStack {
            DS.ColorToken.surface(.light).ignoresSafeArea()

            if let renderer = viewModel.renderer {
                VStack {
                    previewContainer(renderer: renderer)
                        .animation(.easeInOut(duration: 0.28), value: viewModel.aspectRatio)
                    Spacer()
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(sideToolbarEdgeGesture)
        .overlay(alignment: .bottom) {
            PicCameraBottomOverlayView(
                viewModel: viewModel,
                modeBinding: modeBinding,
                buttonRotationAngle: buttonRotationAngle,
                isZoomIndicatorVisible: false,
                onPreviewCapturedImage: {
                    guard viewModel.capturedImage != nil else { return }
                    viewModel.isCapturedPreviewPresented = true
                }
            )
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                PicCameraSideWavePanelView(
                    viewModel: viewModel,
                    buttonRotationAngle: buttonRotationAngle,
                    isPresented: $isSideToolbarVisible
                )
                .offset(y: -50)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(DS.ColorToken.outline(scheme), lineWidth: 0.5)
                    )
                    .dsShadow(.level2)
                    .rotationEffect(buttonRotationAngle)
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)
            .padding(.top, 8)
        }
        .overlay {
            if captureFlashOpacity > 0 {
                Color.white
                    .opacity(captureFlashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if viewModel.deviceOrientation.isLandscape {
                    cameraToast(
                        message: "当前以横屏构图保存",
                        systemImage: "iphone",
                        kind: .info
                    )
                }

                if let toast = viewModel.cameraToast {
                    cameraToast(
                        message: toast.message,
                        systemImage: toast.systemImage,
                        kind: toast.kind
                    )
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
            if viewModel.isLevelEnabled {
                startLevelUpdates()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIDevice.orientationDidChangeNotification) {
                let orientation = UIDevice.current.orientation
                guard orientation.isValidInterfaceOrientation else { continue }
                withAnimation(.easeInOut(duration: 0.28)) {
                    viewModel.updateDeviceOrientation(orientation)
                }
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
                    onContinue: {
                        viewModel.isCapturedPreviewPresented = false
                    },
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
            if isCapturing {
                playCaptureFlash()
            }
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
        Binding(
            get: { viewModel.isShowingSettings },
            set: { viewModel.isShowingSettings = $0 }
        )
    }

    private var capturedPreviewBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isCapturedPreviewPresented && viewModel.capturedImage != nil },
            set: { viewModel.isCapturedPreviewPresented = $0 }
        )
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isShowingSaveError },
            set: { viewModel.isShowingSaveError = $0 }
        )
    }

    private var initialDeviceOrientation: UIDeviceOrientation {
        let orientation = UIDevice.current.orientation
        return orientation.isValidInterfaceOrientation ? orientation : .portrait
    }

    private var sideToolbarEdgeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                if value.translation.width < -36 {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        isSideToolbarVisible = true
                    }
                } else if value.translation.width > 36 {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        isSideToolbarVisible = false
                    }
                }
            }
    }

    private var isAnyDetailExpanded: Bool {
        viewModel.activePanel != nil || viewModel.isApertureControlVisible
    }

    private var buttonRotationAngle: Angle {
        switch viewModel.deviceOrientation {
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        case .portraitUpsideDown:
            return .degrees(180)
        default:
            return .degrees(0)
        }
    }

    private func previewContent(renderer: PicCameraRenderer) -> some View {
        PicCameraMetalPreview(
            renderer: renderer,
            service: viewModel.service,
            isPaused: viewModel.isShowingSettings
        )
            .contentShape(.rect)
            .simultaneousGesture(focusGesture())
            .blur(radius: previewBlurRadius)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .local) }, action: {
                previewRect = $0
            })
            .overlay(
                Rectangle()
                    .stroke(DS.ColorToken.textPrimary(scheme).opacity(0.08), lineWidth: 1)
            )
            .overlay {
                Rectangle()
                    .fill(DS.ColorToken.surface(scheme).opacity(previewBlurOverlayOpacity))
                    .allowsHitTesting(false)
            }
            .overlay {
                if viewModel.isGridEnabled {
                    PicCameraGridView()
                        .stroke(DS.ColorToken.textPrimary(scheme).opacity(0.32), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if viewModel.isLevelEnabled {
                    if viewModel.deviceOrientation.isLandscape {
                        PicCameraLandscapeLevelView(
                            angle: levelAngle,
                            rotationAngle: buttonRotationAngle
                        )
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(PicCameraAspectRatio.ratio9x16.portraitAspect, contentMode: .fit)
    }

    private func focusGesture() -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if isAnyDetailExpanded {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        viewModel.dismissExpandedDetails()
                        isSideToolbarVisible = false
                    }
                    return
                }

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

    private func startLevelUpdates() {
        motionReader.start { angle in
            levelAngle = angle
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
