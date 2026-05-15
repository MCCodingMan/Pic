import SwiftUI

struct PicCameraSettingsSheet: View {
    @Bindable var viewModel: PicCameraViewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingSegmentRow(title: "闪光灯", selection: flashBinding)
            if viewModel.mode != .portrait, viewModel.supportsLivePhoto {
                settingSegmentRow(title: "实况", selection: livePhotoBinding)
            }
            settingSegmentRow(title: "自动滤镜", selection: autoFilterBinding)
            settingSegmentRow(title: "网格", selection: gridBinding)
            settingSegmentRow(title: "水平仪", selection: levelBinding)
            settingSegmentRow(title: "显示比例", selection: ratioBinding)
            settingSegmentRow(title: "保存历史设置", selection: historyBinding)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.ColorToken.surface(scheme))
        .presentationBackground(DS.ColorToken.surface(scheme))
    }

    private func settingSegmentRow<Value: Hashable & CaseIterable & Identifiable & RawRepresentable>(
        title: String,
        selection: Binding<Value>
    ) -> some View where Value.RawValue == String {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.ColorToken.textPrimary(scheme).opacity(0.9))

            Spacer(minLength: 12)

            PicSettingSegmentedControl(
                items: Array(Value.allCases),
                selectedItem: selection
            )
            .frame(maxWidth: 220)
        }
    }

    private var flashBinding: Binding<PicCameraFlashOption> {
        Binding(
            get: { PicCameraFlashOption(mode: viewModel.flashMode) },
            set: { viewModel.setFlashOption($0) }
        )
    }

    private var livePhotoBinding: Binding<PicCameraSwitchOption> {
        Binding(
            get: { PicCameraSwitchOption(viewModel.isLivePhotoEnabled) },
            set: { viewModel.setLivePhotoEnabled($0.isEnabled) }
        )
    }

    private var gridBinding: Binding<PicCameraSwitchOption> {
        Binding(
            get: { PicCameraSwitchOption(viewModel.isGridEnabled) },
            set: { viewModel.isGridEnabled = $0.isEnabled }
        )
    }

    private var autoFilterBinding: Binding<PicCameraSwitchOption> {
        Binding(
            get: { PicCameraSwitchOption(viewModel.isAutoFilterEnabled) },
            set: { viewModel.setAutoFilterEnabled($0.isEnabled) }
        )
    }

    private var levelBinding: Binding<PicCameraSwitchOption> {
        Binding(
            get: { PicCameraSwitchOption(viewModel.isLevelEnabled) },
            set: { viewModel.isLevelEnabled = $0.isEnabled }
        )
    }

    private var ratioBinding: Binding<PicCameraAspectRatio> {
        Binding(
            get: { viewModel.aspectRatio },
            set: { viewModel.aspectRatio = $0 }
        )
    }

    private var historyBinding: Binding<PicCameraSwitchOption> {
        Binding(
            get: { PicCameraSwitchOption(viewModel.isHistorySettingsEnabled) },
            set: { viewModel.setHistorySettingsEnabled($0.isEnabled) }
        )
    }
}

struct PicSettingSegmentedControl<Item: Hashable & Identifiable & RawRepresentable>: View where Item.RawValue == String {
    @Environment(\.colorScheme) private var scheme
    let items: [Item]
    @Binding var selectedItem: Item

    @Namespace private var matchNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedItem = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(
                            selectedItem == item
                            ? DS.ColorToken.surface(scheme)
                            : DS.ColorToken.textPrimary(scheme).opacity(0.78)
                        )
                        .lineLimit(1)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selectedItem == item {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                DS.ColorToken.accent(scheme),
                                                DS.ColorToken.warning(scheme)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "pic_setting_segment_selection", in: matchNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(DS.ColorToken.surface(scheme).opacity(0.42))
                .overlay(
                    Capsule()
                        .stroke(DS.ColorToken.textPrimary(scheme).opacity(0.08), lineWidth: 1)
                )
        )
    }
}
