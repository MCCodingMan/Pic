import SwiftUI

struct FocusIndicator {
    let location: CGPoint
}

struct FocusIndicatorView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.ColorToken.warning(scheme), lineWidth: 2)
                .frame(width: 74, height: 74)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.ColorToken.onBrand.opacity(0.35), lineWidth: 1)
                .frame(width: 64, height: 64)
        }
    }
}
