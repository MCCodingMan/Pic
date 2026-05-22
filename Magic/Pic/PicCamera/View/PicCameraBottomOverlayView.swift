import SwiftUI

struct PicCameraBottomOverlayView: View {
    @Environment(\.colorScheme) private var scheme

    let viewModel: PicCameraViewModel
    let modeBinding: Binding<PicCameraMode>
    let buttonRotationAngle: Angle
    let isZoomIndicatorVisible: Bool
    let onPreviewCapturedImage: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            secondaryControlsOverlay
                .padding(.horizontal, 30)

            if viewModel.activePanel == .filter, viewModel.shouldShowFilterOptions {
                filterOptionsRow
                    .padding(.horizontal, 30)
            }

            if viewModel.activePanel == .composition {
                if viewModel.selectedCompositionCategory == .portrait {
                    compositionPoseRow
                        .padding(.horizontal, 30)
                }

                compositionPositionRow
                    .padding(.horizontal, 30)
            }

            if let activePanel = viewModel.activePanel {
                firstLevelRow(for: activePanel)
                    .padding(.horizontal, 30)
            }
            bottomControls
            bottomBar
            
        }
        .padding(.horizontal, 20)
    }
    
    private var bottomBar: some View {
        HStack {
            if let image = viewModel.capturedImage {
                Button(action: onPreviewCapturedImage) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCapturing)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.ColorToken.textPrimary(scheme).opacity(0.08))
                    .frame(width: 52, height: 52)
            }
            Spacer()
            PicSegmentedControl(items: PicCameraMode.allCases, selectedItem: modeBinding, buttonRotationAngle: buttonRotationAngle)
            Spacer()
            Button {
                Task { await viewModel.switchCameraPosition() }
            } label: {
                Circle()
                    .fill(DS.ColorToken.textPrimary(scheme).opacity(0.08))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.textPrimary(scheme))
                            .rotationEffect(buttonRotationAngle)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var secondaryControlsOverlay: some View {
        Group {
            if viewModel.isCapturing {
                statusCapsule("正在拍摄", systemImage: "camera.fill")
            } else if viewModel.isSavingCapture {
                statusCapsule("正在保存", systemImage: "square.and.arrow.down.fill")
            } else if viewModel.isConfigurationFailed {
                Text("当前设备不支持该拍摄模式")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DS.ColorToken.surface(scheme).opacity(0.42)))
            } else if viewModel.isPortraitDepthUnavailable {
                statusCapsule("当前设备不支持真实景深", systemImage: "person.crop.rectangle.badge.exclamationmark")
            } else if viewModel.activePanel == .adjust, let selected = viewModel.selectedAdjustment {
                parameterSliderCard(
                    value: Binding(
                        get: { selected.getValue(from: viewModel.adjustments) },
                        set: { viewModel.updateAdjustment(selected, value: $0) }
                    ),
                    range: selected.range,
                    defaultRawValue: selected.defaultValue
                )
                .id(selected.id)
            } else if viewModel.activePanel == .beauty, let control = viewModel.selectedBeautyControl {
                parameterSliderCard(
                    value: Binding(
                        get: { viewModel.beautyValue(for: control) },
                        set: { viewModel.updateBeautyValue(control, value: $0) }
                    ),
                    range: 0...1
                )
            } else if viewModel.activePanel == .quickBeauty {
                parameterSliderCard(
                    value: Binding(
                        get: { viewModel.beautyIntensity },
                        set: { viewModel.updateBeautyIntensity($0) }
                    ),
                    range: 0...1
                )
            } else if isZoomIndicatorVisible {
                Text(zoomText(for: viewModel.selectedZoomFactor))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.ColorToken.textPrimary(scheme))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(DS.ColorToken.surface(scheme).opacity(0.35)))
                    .padding(.bottom, 8)
            } else if viewModel.mode == .portrait, viewModel.isApertureControlVisible {
                apertureSliderCard
            }
        }
    }

    private var apertureSliderCard: some View {
        let displayValue = Binding<Double>(
            get: { (viewModel.portraitAperture * 10).rounded() },
            set: { viewModel.updatePortraitAperture($0 / 10) }
        )
        let displayRange = (viewModel.portraitApertureRange.lowerBound * 10)...(viewModel.portraitApertureRange.upperBound * 10)

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "f.cursive")
                Text(String(format: "%.1f", viewModel.portraitAperture))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(DS.ColorToken.textPrimary(scheme))

            WaveRulerSlider(
                value: displayValue,
                range: displayRange,
                step: 1,
                majorTickInterval: 10,
                minorTickInterval: 5,
                showValue: false,
                defaultMarkerValue: 0
            )
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 2)
    }

    private func parameterSliderCard(
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
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 20)
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

    @ViewBuilder
    private func firstLevelRow(for panel: PicCameraViewModel.ToolPanel) -> some View {
        switch panel {
        case .beauty:
            beautyControlsRow
        case .quickBeauty:
            EmptyView()
        case .adjust:
            adjustmentControlsRow
        case .filter:
            filterCategoryRow
        case .composition:
            compositionCategoryRow
        }
    }

    private var beautyControlsRow: some View {
        HStack(spacing: 10) {
            Spacer()
            ForEach(PicCameraViewModel.BeautyControl.allCases) { control in
                controlChip(
                    title: control.rawValue,
                    isSelected: viewModel.selectedBeautyControl == control,
                    isModified: viewModel.isBeautyControlModified(control),
                    accent: DS.ColorToken.accent(scheme)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectBeautyControl(control)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var adjustmentControlsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(AdjustmentType.allCases) { type in
                    controlChip(
                        title: type.rawValue,
                        isSelected: viewModel.selectedAdjustment == type,
                        isModified: type.isModified(in: viewModel.adjustments),
                        accent: DS.ColorToken.success(scheme)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectAdjustment(type)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var filterCategoryRow: some View {
        HStack(spacing: 10) {
            Spacer()
            ForEach(manualFilterCategories) { category in
                let isSelected = filterCategorySelected(category)
                controlChip(
                    title: category.rawValue,
                    isSelected: isSelected,
                    isModified: isSelected && viewModel.isFilterModified,
                    accent: DS.ColorToken.warning(scheme)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectFilterPanelCategory(category)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var manualFilterCategories: [PicCameraViewModel.FilterPanelCategory] {
        [.scenery, .portrait]
    }

    private var compositionCategoryRow: some View {
        HStack(spacing: 10) {
            Spacer()
            ForEach(PicCameraViewModel.CompositionCategory.allCases) { category in
                controlChip(
                    title: category.rawValue,
                    isSelected: viewModel.selectedCompositionCategory == category,
                    isModified: false,
                    accent: DS.ColorToken.accent(scheme)
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectCompositionCategory(category)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var compositionPositionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.compositionPositions()) { position in
                    controlChip(
                        title: position.rawValue,
                        isSelected: viewModel.selectedCompositionPosition == position,
                        isModified: false,
                        accent: DS.ColorToken.warning(scheme)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectCompositionPosition(position)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var compositionPoseRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(viewModel.compositionPoseNames(), id: \.self) { poseName in
                    compositionPoseButton(poseName)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 78)
    }

    private func compositionPoseButton(_ poseName: String) -> some View {
        let isSelected = viewModel.selectedCompositionPoseName == poseName
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectCompositionPoseName(poseName)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)

                Image(poseName)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            }
            .frame(width: 56, height: 72)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? DS.ColorToken.accent(scheme) : .white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 8 : 4, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var filterOptionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                originalFilterCard

                ForEach(viewModel.availableFilterItems) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.setFilter(filter)
                        }
                    } label: {
                        filterOptionCard(
                            title: filter.name,
                            isSelected: viewModel.selectedFilter == filter,
                            gradient: filterChipColor(for: filter),
                            selectedForeground: DS.ColorToken.onBrand,
                            idleForeground: DS.ColorToken.textPrimary(scheme)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 78)
    }

    private var originalFilterCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.setFilter(.original)
            }
        } label: {
            filterOptionCard(
                title: "原图",
                isSelected: viewModel.selectedFilter == .original,
                gradient: LinearGradient(
                    colors: [
                        DS.ColorToken.textPrimary(scheme).opacity(0.22),
                        DS.ColorToken.textPrimary(scheme).opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                selectedForeground: DS.ColorToken.textPrimary(scheme),
                idleForeground: DS.ColorToken.textPrimary(scheme)
            )
        }
        .buttonStyle(.plain)
    }

    private func filterOptionCard(
        title: String,
        isSelected: Bool,
        gradient: LinearGradient,
        selectedForeground: Color,
        idleForeground: Color
    ) -> some View {
        let foreground = isSelected ? selectedForeground : idleForeground

        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(gradient)
            .frame(width: 50, height: 50)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(isSelected ? 0.02 : 0.18))
            }
            .overlay {
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? AnyShapeStyle(gradient) : AnyShapeStyle(.white.opacity(0.12)),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 8 : 4, y: 4)
    }

    private func controlChip(
        title: String,
        isSelected: Bool,
        isModified: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(chipForeground(isSelected: isSelected, isModified: isModified, accent: accent))
                .lineLimit(1)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .fill(chipBackground(isSelected: isSelected, isModified: isModified, accent: accent))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var bottomControls: some View {
        Button {
            viewModel.capture()
        } label: {
            ZStack {
                Circle()
                    .stroke(DS.ColorToken.surface(scheme), lineWidth: 4)
                    .frame(width: 62, height: 62)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
                if viewModel.isCapturing || viewModel.isSavingCapture {
                    ProgressView()
                        .tint(DS.ColorToken.surface(scheme))
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(viewModel.isCapturing || viewModel.isSavingCapture || viewModel.isConfigurationFailed)
        .opacity(viewModel.isCapturing || viewModel.isSavingCapture || viewModel.isConfigurationFailed ? 0.55 : 1)
    }

    private func statusCapsule(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(DS.ColorToken.textPrimary(scheme))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(DS.ColorToken.surface(scheme).opacity(0.48)))
    }

    private func chipForeground(isSelected: Bool, isModified: Bool, accent: Color) -> Color {
        if isSelected || isModified {
            return accent
        }
        return DS.ColorToken.textPrimary(scheme).opacity(0.78)
    }

    private func chipBackground(isSelected: Bool, isModified: Bool, accent: Color) -> Color {
        if isSelected {
            return accent.opacity(0.18)
        }
        if isModified {
            return accent.opacity(0.08)
        }
        return DS.ColorToken.textPrimary(scheme).opacity(0.04)
    }

    private func filterCategorySelected(_ category: PicCameraViewModel.FilterPanelCategory) -> Bool {
        switch category {
        case .auto:
            return viewModel.isAutoFilterEnabled
        case .scenery, .portrait:
            return !viewModel.isAutoFilterEnabled && viewModel.selectedFilterPanelCategory == category
        }
    }

    private func zoomText(for factor: CGFloat) -> String {
        if factor.rounded(.towardZero) == factor {
            return "\(Int(factor))x"
        }
        return String(format: "%.1fx", factor)
    }

    private func filterChipColor(for filter: FilterModel) -> LinearGradient {
        let colors: [Color] = filter.category == "风景"
        ? [DS.ColorToken.brandSecondary(scheme), DS.ColorToken.brandPrimary(scheme)]
        : [DS.ColorToken.accent(scheme), DS.ColorToken.danger(scheme)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
