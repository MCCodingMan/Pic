import SwiftUI

struct PicSegmentedControl: View {
    @Environment(\.colorScheme) private var scheme
    let items: [PicCameraMode]
    @Binding var selectedItem: PicCameraMode
    let buttonRotationAngle: Angle

    @Namespace private var matchNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedItem = item
                    }
                } label: {
                    Image(systemName: item.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedItem == item ? DS.ColorToken.surface(scheme) : DS.ColorToken.textPrimary(scheme).opacity(0.78))
                        .rotationEffect(buttonRotationAngle)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44)
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
                                    .matchedGeometryEffect(id: "pic_segment_selection", in: matchNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(5)
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
