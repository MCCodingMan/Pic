import SwiftUI
import Observation
import UIKit
internal import AVFoundation


@MainActor
@Observable
final class PicCameraViewModel {
    enum ToolPanel: Equatable {
        case beauty
        case quickBeauty
        case filter
        case adjust
    }

    enum BeautyControl: String, CaseIterable, Identifiable {
        case smoothing = "磨皮"
        case whitening = "美白"
        case brightening = "亮肤"
        case slimming = "瘦脸"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .smoothing: return "circle.dotted"
            case .whitening: return "sun.max"
            case .brightening: return "sparkles"
            case .slimming: return "face.smiling"
            }
        }
    }

    enum FilterPanelCategory: String, CaseIterable, Identifiable {
        case auto = "自动"
        case scenery = "风景"
        case portrait = "人物"

        var id: String { rawValue }

        var sourceCategory: String? {
            switch self {
            case .auto: return nil
            case .scenery: return "风景"
            case .portrait: return "人物"
            }
        }
    }

    let service = PicCameraService()
    let renderer = PicCameraRenderer.make()

    var mode: PicCameraMode = .photo
    var authorizationStatus: AVAuthorizationStatus = .notDetermined
    var isConfigurationFailed = false
    var capturedImage: UIImage?
    var isCapturedPreviewPresented = false
    var isCapturing = false
    var isSavingCapture = false
    var cameraToast: PicCameraToast?
    var saveErrorMessage = ""
    var isShowingSaveError = false
    var selectedZoomFactor: CGFloat = 1
    var flashMode: AVCaptureDevice.FlashMode = .off
    var supportsFlash = false
    var isLivePhotoEnabled = false
    var supportsLivePhoto = false
    var cameraPosition: AVCaptureDevice.Position = .back
    var isShowingSettings = false
    var isHistorySettingsEnabled = PicCameraHistoryPersistence.historyEnabled()
    var isGridEnabled = false
    var aspectRatio: PicCameraAspectRatio = .ratio9x16
    var isLevelEnabled = true
    var deviceOrientation: UIDeviceOrientation = .portrait
    var activePanel: ToolPanel?
    var skinSmoothing: Double = 0
    var skinWhitening: Double = 0
    var skinWhiteningYUV: Double = 0.0
    var faceSlimming: Double = 0.0
    var liveFaceContext: FaceContext = .empty
    var selectedBeautyControl: BeautyControl?
    var selectedFilterPanelCategory: FilterPanelCategory = .auto
    var selectedFilter: FilterModel = .original
    var isAutoFilterEnabled = false
    var portraitAperture: Double = 8
    var isPortraitDepthUnavailable = false
    var isApertureControlVisible = false
    var adjustments = Adjustments()
    var selectedAdjustment: AdjustmentType?
    var toolbarActions: [ToolbarAction] = [.beauty, .quickBeauty, .adjust, .filter, .autoFilter, .flash, .livePhoto, .settings]
    private(set) var availableFilters: [String: [FilterModel]] = [:]
    private let photoZoomRange: ClosedRange<CGFloat> = 0.5...8
    private let portraitZoomRange: ClosedRange<CGFloat> = 1...4
    private var zoomDisplayMultiplier: CGFloat = 1

    private var bridge: Bridge?
    @ObservationIgnored private var toastDismissTask: Task<Void, Never>?
    @ObservationIgnored private var zoomApplyTask: Task<Void, Never>?

    var beautyParams: BeautyParams {
        BeautyParams(
            smoothing: skinSmoothing,
            whitening: skinWhitening,
            whiteningYUV: skinWhiteningYUV,
            slimming: faceSlimming
        )
    }

    var beautyIntensity: Double {
        max(skinSmoothing, skinWhitening, skinWhiteningYUV)
    }

    var effectiveFilter: FilterModel {
        isAutoFilterEnabled ? .auto : selectedFilter
    }

    var availableFilterItems: [FilterModel] {
        guard let category = selectedFilterPanelCategory.sourceCategory else { return [] }
        return availableFilters[category] ?? []
    }

    var shouldShowFilterOptions: Bool {
        activePanel == .filter && selectedFilterPanelCategory != .auto
    }

    var portraitApertureRange: ClosedRange<Double> {
        1.4...16
    }

    var isBeautyModified: Bool {
        beautyValue(for: .smoothing) > 0.001 ||
        beautyValue(for: .whitening) > 0.001 ||
        beautyValue(for: .brightening) > 0.001 ||
        beautyValue(for: .slimming) > 0.001
    }

    var isFilterModified: Bool {
        isAutoFilterEnabled || selectedFilter != .original
    }

    init() {
        let bridge = Bridge(renderer: renderer)
        let rendererRef = renderer
        self.bridge = bridge
        service.frameConsumer = bridge
        service.onPhotoCapture = { [weak self] image in
            self?.handleCapturedPhoto(image)
        }
        service.onLivePhotoCapture = { [weak self] photo, movieURL in
            self?.handleCapturedLivePhoto(photo, movieURL: movieURL)
        }
        service.onCaptureError = { [weak self] error in
            self?.handleCaptureError(error)
        }
        service.onFaceRects = { [weak rendererRef] rects in
            let context = FaceDetectionService.contextFromMetadata(
                rects: rects,
                imageSize: CGSize(width: 1, height: 1)
            )
            rendererRef?.updateLiveFaceContext(context)
        }
        loadFilters()
        if isHistorySettingsEnabled, let savedState = PicCameraHistoryPersistence.loadState() {
            applyNonServiceState(savedState)
        }
        syncRenderState()
    }

    func onAppear() async {
        authorizationStatus = await service.requestAccessIfNeeded()
        guard authorizationStatus == .authorized else {
            showCameraToast("需要相机权限", systemImage: "camera.fill", kind: .error)
            return
        }

        let configured = await service.configureSessionIfNeeded(mode: mode)
        if !configured {
            isConfigurationFailed = true
            showCameraToast("当前设备不支持相机", systemImage: "exclamationmark.triangle.fill", kind: .error)
            return
        }

        isConfigurationFailed = false
        await service.startSession()
        refreshControls()
        zoomDisplayMultiplier = await service.currentDisplayVideoZoomFactorMultiplier()
        let currentRawZoomFactor = await service.currentZoomFactor()
        selectedZoomFactor = currentRawZoomFactor * zoomDisplayMultiplier
        if isHistorySettingsEnabled {
            await applySavedStateOnAppear()
        } else {
            await applyDefaultStateOnAppear()
        }
        showToolbarIntroIfNeeded()
    }

    func onDisappear() {
        service.stopSession()
        liveFaceContext = .empty
        renderer?.updateLiveFaceContext(.empty)
        toastDismissTask?.cancel()
        zoomApplyTask?.cancel()
    }

    func capture() {
        guard authorizationStatus == .authorized, !isConfigurationFailed, !isCapturing, !isSavingCapture else { return }
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        service.capturePhoto()
    }

    func switchMode(to newMode: PicCameraMode) async -> Bool {
        guard newMode != mode else { return true }
        let requestedZoomFactor = selectedZoomFactor
        let success = await service.switchMode(to: newMode)
        if success {
            mode = newMode
            syncRenderState()
            if mode == .portrait {
                if isLivePhotoEnabled {
                    service.setLivePhotoEnabled(false)
                    isLivePhotoEnabled = false
                }
            } else {
                isApertureControlVisible = false
            }
            isConfigurationFailed = false
            refreshControls()
            zoomDisplayMultiplier = await service.currentDisplayVideoZoomFactorMultiplier()
            await applyZoomFactor(requestedZoomFactor)
            if isPortraitDepthUnavailable {
                showCameraToast("当前设备不支持真实景深", systemImage: "person.crop.rectangle.badge.exclamationmark", kind: .info)
            }
        } else {
            isConfigurationFailed = true
            showCameraToast("当前设备不支持该模式", systemImage: "exclamationmark.triangle.fill", kind: .error)
        }
        return success
    }

    func focus(at normalizedPoint: CGPoint) async {
        await service.focus(at: normalizedPoint)
    }

    func toggleFlash() {
        switch flashMode {
        case .off:
            flashMode = .auto
        case .auto:
            flashMode = .on
        case .on:
            flashMode = .off
        @unknown default:
            flashMode = .off
        }
        service.setFlashMode(flashMode)
    }

    func toggleLivePhoto() {
        guard mode != .portrait else { return }
        let nextValue = !isLivePhotoEnabled
        service.setLivePhotoEnabled(nextValue)
        isLivePhotoEnabled = nextValue
    }

    func switchCameraPosition() async {
        let requestedZoomFactor = selectedZoomFactor
        let success = await service.switchCameraPosition()
        if success {
            isConfigurationFailed = false
            refreshControls()
            zoomDisplayMultiplier = await service.currentDisplayVideoZoomFactorMultiplier()
            await applyZoomFactor(requestedZoomFactor)
            if isPortraitDepthUnavailable {
                showCameraToast("当前设备不支持真实景深", systemImage: "person.crop.rectangle.badge.exclamationmark", kind: .info)
            }
        } else {
            isConfigurationFailed = true
            showCameraToast("切换镜头失败", systemImage: "exclamationmark.triangle.fill", kind: .error)
        }
    }

    func toggleGrid() {
        isGridEnabled.toggle()
    }

    func toggleLevel() {
        isLevelEnabled.toggle()
    }

    func cycleAspectRatio() {
        let all = PicCameraAspectRatio.allCases
        guard let currentIndex = all.firstIndex(of: aspectRatio) else {
            aspectRatio = .ratio9x16
            return
        }
        let nextIndex = all.index(after: currentIndex)
        aspectRatio = nextIndex == all.endIndex ? all[all.startIndex] : all[nextIndex]
        showCameraToast("当前比例 \(aspectRatio.rawValue)", systemImage: aspectRatioIconName, kind: .info)
    }

    func toggleAutoFilter() {
        setAutoFilterEnabled(!isAutoFilterEnabled)
    }

    func setFlashOption(_ option: PicCameraFlashOption) {
        flashMode = option.flashMode
        service.setFlashMode(flashMode)
    }

    func setLivePhotoEnabled(_ enabled: Bool) {
        guard mode != .portrait else {
            service.setLivePhotoEnabled(false)
            isLivePhotoEnabled = false
            return
        }
        service.setLivePhotoEnabled(enabled)
        isLivePhotoEnabled = enabled
    }

    func setAutoFilterEnabled(_ enabled: Bool) {
        isAutoFilterEnabled = enabled
        if enabled {
            selectedFilter = .original
            selectedFilterPanelCategory = .auto
        } else if selectedFilterPanelCategory == .auto {
            selectedFilterPanelCategory = .scenery
        }
        syncRenderState()
    }

    func setHistorySettingsEnabled(_ enabled: Bool) {
        isHistorySettingsEnabled = enabled
        PicCameraHistoryPersistence.setHistoryEnabled(enabled)
        if enabled {
            persistHistoryIfNeeded()
        } else {
            PicCameraHistoryPersistence.clearState()
        }
    }

    func persistHistoryIfNeeded() {
        guard isHistorySettingsEnabled else { return }
        PicCameraHistoryPersistence.saveState(makeCurrentSavedState())
    }

    func updateDeviceOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation.isValidInterfaceOrientation else { return }
        deviceOrientation = orientation
    }

    func setZoomFactor(_ factor: CGFloat) {
        let zoomRange = currentZoomRange()
        let clampedDisplay = min(max(factor, zoomRange.lowerBound), zoomRange.upperBound)
        selectedZoomFactor = clampedDisplay
        let multiplier = max(zoomDisplayMultiplier, 0.0001)
        let targetRawFactor = clampedDisplay / multiplier
        zoomApplyTask?.cancel()
        zoomApplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let appliedRaw = await service.setZoomFactor(targetRawFactor, preferredRange: rawZoomRange())
            selectedZoomFactor = appliedRaw * zoomDisplayMultiplier
        }
    }

    func applyZoomFactor(_ factor: CGFloat) async {
        let zoomRange = currentZoomRange()
        let clampedDisplay = min(max(factor, zoomRange.lowerBound), zoomRange.upperBound)
        let multiplier = max(zoomDisplayMultiplier, 0.0001)
        let targetRawFactor = clampedDisplay / multiplier
        let appliedRaw = await service.setZoomFactor(targetRawFactor, preferredRange: rawZoomRange())
        selectedZoomFactor = appliedRaw * zoomDisplayMultiplier
    }

    private func rawZoomRange() -> ClosedRange<CGFloat> {
        let zoomRange = currentZoomRange()
        let multiplier = max(zoomDisplayMultiplier, 0.0001)
        return (zoomRange.lowerBound / multiplier)...(zoomRange.upperBound / multiplier)
    }

    private func currentZoomRange() -> ClosedRange<CGFloat> {
        mode == .portrait ? portraitZoomRange : photoZoomRange
    }

    private func clampedZoomFactorForCurrentMode(_ factor: CGFloat) -> CGFloat {
        let range = currentZoomRange()
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    func toggleBeautyPanel() {
        if activePanel == .beauty {
            if resetSelectedBeautyControlIfNeeded() {
                return
            }
            activePanel = nil
        } else {
            activePanel = .beauty
            selectedBeautyControl = preferredBeautyControl()
        }
        if activePanel == .beauty {
            selectedAdjustment = nil
        }
    }

    func toggleQuickBeautyPanel() {
        if activePanel == .quickBeauty {
            if beautyIntensity > 0.001 {
                resetQuickBeauty()
                return
            }
            activePanel = nil
        } else {
            activePanel = .quickBeauty
        }
        if activePanel == .quickBeauty {
            selectedBeautyControl = nil
            selectedAdjustment = nil
        }
    }

    func toggleFilterPanel() {
        activePanel = activePanel == .filter ? nil : .filter
        if activePanel == .filter {
            selectedAdjustment = nil
        }
    }

    func toggleAdjustPanel() {
        if activePanel == .adjust {
            if resetSelectedAdjustmentIfNeeded() {
                return
            }
            activePanel = nil
        } else {
            activePanel = .adjust
            selectedAdjustment = preferredAdjustment()
        }
        if activePanel == .adjust {
            selectedBeautyControl = nil
        }
    }

    func selectBeautyControl(_ control: BeautyControl) {
        if activePanel == .beauty,
           selectedBeautyControl == control,
           isBeautyControlModified(control) {
            resetBeautyControl(control)
            return
        }
        activePanel = .beauty
        selectedBeautyControl = control
    }

    func beautyValue(for control: BeautyControl) -> Double {
        switch control {
        case .smoothing: return skinSmoothing
        case .whitening: return skinWhitening
        case .brightening: return skinWhiteningYUV
        case .slimming: return faceSlimming
        }
    }

    func updateBeautyValue(_ control: BeautyControl, value: Double) {
        switch control {
        case .smoothing: skinSmoothing = value
        case .whitening: skinWhitening = value
        case .brightening: skinWhiteningYUV = value
        case .slimming: faceSlimming = value
        }
        syncRenderState()
    }

    func updateBeautyIntensity(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        skinSmoothing = clamped
        skinWhitening = clamped
        skinWhiteningYUV = clamped
        syncRenderState()
    }

    func isBeautyControlModified(_ control: BeautyControl) -> Bool {
        beautyValue(for: control) > 0.001
    }

    private func firstModifiedBeautyControl() -> BeautyControl? {
        BeautyControl.allCases.first { isBeautyControlModified($0) }
    }

    private func preferredBeautyControl() -> BeautyControl {
        if let selectedBeautyControl, isBeautyControlModified(selectedBeautyControl) {
            return selectedBeautyControl
        }
        return firstModifiedBeautyControl() ?? selectedBeautyControl ?? .smoothing
    }

    private func resetSelectedBeautyControlIfNeeded() -> Bool {
        let control = selectedBeautyControl.flatMap { isBeautyControlModified($0) ? $0 : nil }
        ?? firstModifiedBeautyControl()

        guard let control else {
            return false
        }
        selectedBeautyControl = control
        resetBeautyControl(control)
        return true
    }

    private func resetBeautyControl(_ control: BeautyControl) {
        switch control {
        case .smoothing:
            skinSmoothing = 0
        case .whitening:
            skinWhitening = 0
        case .brightening:
            skinWhiteningYUV = 0
        case .slimming:
            faceSlimming = 0
        }
        syncRenderState()
    }

    private func resetQuickBeauty() {
        skinSmoothing = 0
        skinWhitening = 0
        skinWhiteningYUV = 0
        syncRenderState()
    }

    func selectFilterPanelCategory(_ category: FilterPanelCategory) {
        activePanel = .filter
        selectedFilterPanelCategory = category
        switch category {
        case .auto:
            isAutoFilterEnabled = true
            selectedFilter = .original
        case .scenery, .portrait:
            isAutoFilterEnabled = false
            if let sourceCategory = category.sourceCategory,
               selectedFilter.category != sourceCategory {
                selectedFilter = .original
            }
        }
        syncRenderState()
    }

    func setFilter(_ filter: FilterModel) {
        if !isAutoFilterEnabled, selectedFilter == filter, filter != .original {
            selectedFilter = .original
            syncRenderState()
            return
        }

        isAutoFilterEnabled = false
        selectedFilter = filter
        if filter.category == "风景" {
            selectedFilterPanelCategory = .scenery
        } else if filter.category == "人物" {
            selectedFilterPanelCategory = .portrait
        }
        syncRenderState()
    }

    func updateAdjustment(_ type: AdjustmentType, value: Double) {
        type.setValue(&adjustments, value)
        syncRenderState()
    }

    private func firstModifiedAdjustment() -> AdjustmentType? {
        AdjustmentType.allCases.first { $0.isModified(in: adjustments) }
    }

    private func preferredAdjustment() -> AdjustmentType? {
        if let selectedAdjustment, selectedAdjustment.isModified(in: adjustments) {
            return selectedAdjustment
        }
        return firstModifiedAdjustment() ?? selectedAdjustment ?? AdjustmentType.allCases.first
    }

    private func resetSelectedAdjustmentIfNeeded() -> Bool {
        let type = selectedAdjustment.flatMap { $0.isModified(in: adjustments) ? $0 : nil }
        ?? firstModifiedAdjustment()

        guard let type else {
            return false
        }
        selectedAdjustment = type
        resetAdjustment(type)
        return true
    }

    private func resetAdjustment(_ type: AdjustmentType) {
        type.setValue(&adjustments, type.defaultValue)
        syncRenderState()
    }

    func updatePortraitAperture(_ value: Double) {
        let clamped = min(max(value, portraitApertureRange.lowerBound), portraitApertureRange.upperBound)
        portraitAperture = (clamped * 10).rounded() / 10
        syncRenderState()
    }

    func toggleApertureControl() {
        guard mode == .portrait else { return }
        let nextVisible = !isApertureControlVisible
        isApertureControlVisible = nextVisible
        if nextVisible {
            activePanel = nil
            selectedAdjustment = nil
        }
    }

    func dismissExpandedDetails() {
        if isApertureControlVisible {
            toggleApertureControl()
            return
        }

        guard let activePanel else { return }
        switch activePanel {
        case .beauty:
            toggleBeautyPanel()
        case .quickBeauty:
            toggleQuickBeautyPanel()
        case .filter:
            toggleFilterPanel()
        case .adjust:
            toggleAdjustPanel()
        }
    }

    func showToolbarHint(_ text: String) {
        showCameraToast(text, systemImage: "info.circle.fill", kind: .info)
    }

    func selectAdjustment(_ type: AdjustmentType) {
        if activePanel == .adjust,
           selectedAdjustment == type,
           type.isModified(in: adjustments) {
            resetAdjustment(type)
            return
        }
        activePanel = .adjust
        selectedAdjustment = type
    }

    func isToolbarActionActive(_ action: ToolbarAction) -> Bool {
        switch action {
        case .beauty:
            activePanel == .beauty
        case .quickBeauty:
            activePanel == .quickBeauty
        case .adjust:
            activePanel == .adjust
        case .filter:
            activePanel == .filter
        case .autoFilter:
            isAutoFilterEnabled
        case .flash:
            flashMode != .off
        case .livePhoto:
            isLivePhotoEnabled
        case .settings:
            isShowingSettings
        }
    }

    func isToolbarActionModified(_ action: ToolbarAction) -> Bool {
        switch action {
        case .beauty:
            isBeautyModified
        case .quickBeauty:
            beautyIntensity > 0.001
        case .adjust:
            !adjustments.isDefault
        case .filter:
            isFilterModified
        case .autoFilter, .flash, .livePhoto, .settings:
            false
        }
    }

    private func refreshControls() {
        supportsFlash = service.supportsFlash()
        flashMode = service.currentFlashMode()
        supportsLivePhoto = service.supportsLivePhoto()
        isLivePhotoEnabled = service.currentLivePhotoEnabled()
        isPortraitDepthUnavailable = mode == .portrait && !service.supportsPortraitDepthCapture()
        cameraPosition = service.currentCameraPosition()
    }

    private func makeRenderState() -> PicCameraRenderState {
        PicCameraRenderState(
            mode: mode,
            beautyParams: beautyParams,
            adjustments: adjustments,
            filter: effectiveFilter,
            portraitAperture: portraitAperture
        )
    }

    private func syncRenderState() {
        renderer?.updateRenderState(makeRenderState())
    }

    private var aspectRatioIconName: String {
        switch aspectRatio {
        case .ratio1x1:
            return "square"
        case .ratio3x4:
            return "rectangle.ratio.3.to.4"
        case .ratio9x16:
            return "rectangle.ratio.9.to.16"
        }
    }

    private func showToolbarIntroIfNeeded() {
        let key = "pic.camera.toolbar.intro.shown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showCameraToast("长按顶部图标可查看名称", systemImage: "hand.tap.fill", kind: .info, duration: 3)
    }

    private func loadFilters() {
        let allFilters = FilterModel.generateFilters()
        availableFilters = Dictionary(grouping: allFilters, by: \.category)
    }

    private func applySavedStateOnAppear() async {
        guard let savedState = PicCameraHistoryPersistence.loadState() else {
            persistHistoryIfNeeded()
            return
        }

        if let savedMode = PicCameraMode(rawValue: savedState.modeRawValue), savedMode != mode {
            _ = await switchMode(to: savedMode)
        }

        if let targetPosition = cameraPosition(from: savedState.cameraPositionRawValue),
           targetPosition != cameraPosition {
            await switchCameraPosition()
        }

        if let savedFlashMode = flashMode(from: savedState.flashModeRawValue) {
            setFlashOption(PicCameraFlashOption(mode: savedFlashMode))
        } else {
            setFlashOption(.off)
        }

        setLivePhotoEnabled(savedState.isLivePhotoEnabled)
        applyNonServiceState(savedState)
        await applyZoomFactor(CGFloat(savedState.zoomFactor))
        persistHistoryIfNeeded()
    }

    private func applyDefaultStateOnAppear() async {
        if mode != .photo {
            _ = await switchMode(to: .photo)
        }
        if cameraPosition != .back {
            await switchCameraPosition()
        }
        setFlashOption(.off)
        setLivePhotoEnabled(false)
        applyDefaultNonServiceState()
        PicCameraHistoryPersistence.clearState()
    }

    private func applyNonServiceState(_ savedState: PicCameraHistoryPersistence.SavedState) {
        if let savedMode = PicCameraMode(rawValue: savedState.modeRawValue) {
            mode = savedMode
        }
        selectedZoomFactor = clampedZoomFactorForCurrentMode(CGFloat(savedState.zoomFactor))
        if let savedRatio = PicCameraAspectRatio(rawValue: savedState.aspectRatioRawValue) {
            aspectRatio = savedRatio
        } else {
            aspectRatio = .ratio9x16
        }
        isGridEnabled = savedState.isGridEnabled
        isLevelEnabled = savedState.isLevelEnabled
        skinSmoothing = savedState.skinSmoothing
        skinWhitening = savedState.skinWhitening
        skinWhiteningYUV = savedState.skinWhiteningYUV
        faceSlimming = savedState.faceSlimming
        updatePortraitAperture(savedState.portraitAperture)
        adjustments = savedState.adjustments
        setAutoFilterEnabled(savedState.isAutoFilterEnabled)
        if savedState.isAutoFilterEnabled {
            selectedFilter = .original
            selectedFilterPanelCategory = .auto
        } else {
            let restoredFilter = resolveFilter(category: savedState.selectedFilterCategory, name: savedState.selectedFilterName)
            if restoredFilter == .original {
                selectedFilter = .original
                selectedFilterPanelCategory = filterPanelCategory(from: savedState.selectedFilterCategory)
            } else {
                setFilter(restoredFilter)
            }
        }
        syncRenderState()
    }

    private func applyDefaultNonServiceState() {
        isGridEnabled = false
        isLevelEnabled = true
        aspectRatio = .ratio9x16
        skinSmoothing = 0
        skinWhitening = 0
        skinWhiteningYUV = 0
        faceSlimming = 0
        portraitAperture = 8
        adjustments = Adjustments()
        isAutoFilterEnabled = false
        selectedFilter = .original
        selectedFilterPanelCategory = .auto
        activePanel = nil
        selectedBeautyControl = nil
        selectedAdjustment = nil
        isApertureControlVisible = false
        selectedZoomFactor = 1
        syncRenderState()
    }

    private func makeCurrentSavedState() -> PicCameraHistoryPersistence.SavedState {
        PicCameraHistoryPersistence.SavedState(
            modeRawValue: mode.rawValue,
            cameraPositionRawValue: rawValue(for: cameraPosition),
            zoomFactor: Double(selectedZoomFactor),
            flashModeRawValue: rawValue(for: flashMode),
            isLivePhotoEnabled: isLivePhotoEnabled,
            isAutoFilterEnabled: isAutoFilterEnabled,
            isGridEnabled: isGridEnabled,
            isLevelEnabled: isLevelEnabled,
            aspectRatioRawValue: aspectRatio.rawValue,
            skinSmoothing: skinSmoothing,
            skinWhitening: skinWhitening,
            skinWhiteningYUV: skinWhiteningYUV,
            faceSlimming: faceSlimming,
            portraitAperture: portraitAperture,
            selectedFilterCategory: isAutoFilterEnabled ? FilterModel.auto.category : selectedFilter.category,
            selectedFilterName: isAutoFilterEnabled ? FilterModel.auto.name : selectedFilter.name,
            adjustments: adjustments
        )
    }

    private func resolveFilter(category: String, name: String) -> FilterModel {
        if name == FilterModel.original.name {
            return .original
        }

        if let matched = (availableFilters[category] ?? []).first(where: { $0.name == name }) {
            return matched
        }

        for filters in availableFilters.values {
            if let matched = filters.first(where: { $0.category == category && $0.name == name }) {
                return matched
            }
        }

        return .original
    }

    private func filterPanelCategory(from category: String) -> FilterPanelCategory {
        switch category {
        case "风景":
            return .scenery
        case "人物":
            return .portrait
        default:
            return .scenery
        }
    }

    private func rawValue(for position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front:
            return "front"
        case .back:
            return "back"
        default:
            return "unspecified"
        }
    }

    private func cameraPosition(from rawValue: String) -> AVCaptureDevice.Position? {
        switch rawValue {
        case "front":
            return .front
        case "back":
            return .back
        default:
            return nil
        }
    }

    private func rawValue(for flashMode: AVCaptureDevice.FlashMode) -> String {
        switch flashMode {
        case .off:
            return "off"
        case .auto:
            return "auto"
        case .on:
            return "on"
        @unknown default:
            return "off"
        }
    }

    private func flashMode(from rawValue: String) -> AVCaptureDevice.FlashMode? {
        switch rawValue {
        case "off":
            return .off
        case "auto":
            return .auto
        case "on":
            return .on
        default:
            return nil
        }
    }

    private func handleCapturedPhoto(_ photo: AVCapturePhoto) {
        guard let data = photo.fileDataRepresentation() else {
            handleCaptureError(nil)
            return
        }
        let outputOrientation = captureImageOrientation()
        let aspect = captureAspectRatio()
        let beautyParams = beautyParams
        let selectedFilter = effectiveFilter
        let currentFaceContext = renderer?.currentFaceContextSnapshot() ?? liveFaceContext
        let adjustments = adjustments
        let aperture = portraitAperture
        let depthData = photo.depthData
        let renderer = renderer
        let hasActiveFilter = selectedFilter.id != "original" && selectedFilter.id != "auto"
        let shouldPostProcess = !beautyParams.isIdentity
            || !adjustments.isDefault
            || hasActiveFilter

        Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else {
                await MainActor.run { [weak self] in self?.handleCaptureError(nil) }
                return
            }

            if !shouldPostProcess {
                let outputImage: UIImage?
                if let depthData,
                   let ciImage = CIImage(data: data),
                   let result = renderer?.depthBlurImage(
                    image: ciImage.oriented(outputOrientation),
                    depthData: depthData,
                    orientation: outputOrientation,
                    aperture: aperture
                   ) {
                    outputImage = result.cropCIImage(aspectRatio: aspect).uiImage
                } else {
                    outputImage = try? image.cropped(toAspect: aspect)
                }

                await MainActor.run { [weak self] in
                    if let outputImage {
                        self?.updateCapturedImageAndSave(outputImage)
                    } else {
                        self?.handleCaptureError(nil)
                    }
                }
                return
            }

            let faceContext: FaceContext
            if beautyParams.slimming > 0.001 {
                faceContext = await FaceDetectionService.detectInPhoto(image)
            } else {
                faceContext = currentFaceContext
            }

            let outputImage: UIImage?
            if let resultCiImage = PicCameraEffectsProcessor.processCapturedImage(
                image,
                beautyParams: beautyParams,
                faceContext: faceContext,
                adjustments: adjustments,
                filter: selectedFilter
            ) {
                if let depthData,
                   let depthImage = renderer?.depthBlurImage(
                    image: resultCiImage.oriented(outputOrientation),
                    depthData: depthData,
                    orientation: outputOrientation,
                    aperture: aperture
                   ) {
                    outputImage = depthImage.cropCIImage(aspectRatio: aspect).uiImage
                } else {
                    outputImage = resultCiImage.oriented(outputOrientation).cropCIImage(aspectRatio: aspect).uiImage
                }
            } else {
                outputImage = nil
            }

            await MainActor.run { [weak self] in
                if let outputImage {
                    self?.updateCapturedImageAndSave(outputImage)
                } else {
                    self?.handleCaptureError(nil)
                }
            }
        }
    }

    private func handleCapturedLivePhoto(_ photo: AVCapturePhoto, movieURL: URL) {
        guard let data = photo.fileDataRepresentation() else {
            handleCaptureError(nil)
            return
        }
        let beautyParams = beautyParams
        let selectedFilter = effectiveFilter
        let currentFaceContext = renderer?.currentFaceContextSnapshot() ?? liveFaceContext
        let adjustments = adjustments
        let hasActiveFilter = selectedFilter.id != "original" && selectedFilter.id != "auto"
        let shouldPostProcess = !beautyParams.isIdentity
            || !adjustments.isDefault
            || hasActiveFilter

        let aspect = captureAspectRatio()
        Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else {
                await MainActor.run { [weak self] in self?.handleCaptureError(nil) }
                return
            }

            if !shouldPostProcess {
                let cropImage = try? image.cropped(toAspect: aspect)
                await MainActor.run { [weak self] in
                    if let cropImage {
                        self?.updateCapturedLivePhotoAndSave(cropImage, sourcePhotoData: data, movieURL: movieURL)
                    } else {
                        self?.handleCaptureError(nil)
                    }
                }
                return
            }

            let faceContext: FaceContext
            if beautyParams.slimming > 0.001 {
                faceContext = await FaceDetectionService.detectInPhoto(image)
            } else {
                faceContext = currentFaceContext
            }

            let result = PicCameraEffectsProcessor.processCapturedImage(
                image,
                beautyParams: beautyParams,
                faceContext: faceContext,
                adjustments: adjustments,
                filter: selectedFilter
            )
            let outputImage = result?.cropCIImage(aspectRatio: aspect).uiImage

            await MainActor.run { [weak self] in
                if let outputImage {
                    self?.updateCapturedLivePhotoAndSave(outputImage, sourcePhotoData: data, movieURL: movieURL)
                } else {
                    self?.handleCaptureError(nil)
                }
            }
        }
    }

    private func updateCapturedImageAndSave(_ image: UIImage) {
        capturedImage = image
        isCapturing = false
        isSavingCapture = true
        showCameraToast("正在保存", systemImage: "square.and.arrow.down.fill", kind: .info, duration: 1.4)
        Task {
            do {
                try await PhotoLibraryService.shared.saveImage(image)
                isSavingCapture = false
                showCameraToast("已保存到相册", systemImage: "checkmark.circle.fill", kind: .success)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                isSavingCapture = false
                saveErrorMessage = error.localizedDescription
                isShowingSaveError = true
                showCameraToast("保存失败", systemImage: "exclamationmark.triangle.fill", kind: .error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func updateCapturedLivePhotoAndSave(_ image: UIImage, sourcePhotoData: Data, movieURL: URL) {
        capturedImage = image
        isCapturing = false
        isSavingCapture = true
        showCameraToast("正在保存实况照片", systemImage: "livephoto", kind: .info, duration: 1.4)
        Task {
            do {
                try await PhotoLibraryService.shared.saveLivePhoto(
                    stillImage: image,
                    sourcePhotoData: sourcePhotoData,
                    movieURL: movieURL
                )
                isSavingCapture = false
                showCameraToast("已保存到相册", systemImage: "checkmark.circle.fill", kind: .success)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                isSavingCapture = false
                saveErrorMessage = error.localizedDescription
                isShowingSaveError = true
                showCameraToast("保存失败", systemImage: "exclamationmark.triangle.fill", kind: .error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func handleCaptureError(_ error: Error?) {
        isCapturing = false
        isSavingCapture = false
        saveErrorMessage = error?.localizedDescription ?? "照片处理失败，请重试。"
        isShowingSaveError = true
        showCameraToast("拍摄失败", systemImage: "exclamationmark.triangle.fill", kind: .error)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func captureAspectRatio() -> CGFloat {
        if deviceOrientation.isLandscape {
            return 1 / aspectRatio.portraitAspect
        }
        return aspectRatio.portraitAspect
    }

    private func captureImageOrientation() -> CGImagePropertyOrientation {
        switch deviceOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        default:
            return .right
        }
    }

    private func showCameraToast(
        _ message: String,
        systemImage: String,
        kind: PicCameraToast.Kind,
        duration: Double = 2
    ) {
        toastDismissTask?.cancel()
        cameraToast = PicCameraToast(message: message, systemImage: systemImage, kind: kind)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                cameraToast = nil
            }
        }
    }

    private final class Bridge: PicCameraFrameConsumer {
        let renderer: PicCameraRenderer?

        init(renderer: PicCameraRenderer?) {
            self.renderer = renderer
        }

        nonisolated func consume(pixelBuffer: CVPixelBuffer, depthData: AVDepthData?) {
            renderer?.enqueue(pixelBuffer: pixelBuffer, depthData: depthData)
        }
    }
}

extension PicCameraViewModel {
    enum ToolbarAction: String, Identifiable, CaseIterable {
        case beauty
        case quickBeauty
        case adjust
        case filter
        case autoFilter
        case flash
        case livePhoto
        case settings

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .beauty: return "sparkles"
            case .quickBeauty: return "wand.and.stars.inverse"
            case .adjust: return "dial.medium"
            case .filter: return "camera.filters"
            case .autoFilter: return "wand.and.stars"
            case .flash: return "bolt.fill"
            case .livePhoto: return "livephoto"
            case .settings: return "slider.horizontal.3"
            }
        }
    }
}
