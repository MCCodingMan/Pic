import SwiftUI

/// A custom capsule-shaped slider matching the app's design language.
/// Features a rounded track with filled progress, a white thumb with colored ring,
/// and a subtle outer shadow.
/// Drag is delta-based: value changes relative to where you started, not jumping to finger position.
/// Direction-locked: only responds to horizontal drags to avoid conflicts with vertical ScrollViews.
struct PillSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tintColor: Color? = nil
    var trackHeight: CGFloat = 32
    var thumbSize: CGFloat = 24
    var valueStr: String?
    var onEditingChanged: ((Bool) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var isDragging = false
    @State private var dragStartValue: Double = 0
    /// nil = undecided, true = horizontal, false = vertical
    @State private var isHorizontalDrag: Bool? = nil

    private var accentColor: Color {
        tintColor ?? DS.ColorToken.brandPrimary(scheme)
    }

    private var fraction: Double {
        guard range.upperBound != range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let inset: CGFloat = trackHeight / 2
            let usable = totalWidth - trackHeight
            let thumbX = inset + usable * CGFloat(fraction)

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(DS.ColorToken.surfaceAlt(scheme))
                    .overlay(
                        Capsule()
                            .stroke(DS.ColorToken.outline(scheme).opacity(0.6), lineWidth: 1)
                    )

                // Filled portion
                Capsule()
                    .fill(accentColor)
                    .frame(width: max(trackHeight, thumbX + inset))

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .stroke(accentColor, lineWidth: 2.5)
                    )
                    .overlay(content: {
                        if let valueStr {
                            Text(valueStr)
                                .font(.system(size: 10))
                                .foregroundStyle(.black)
                        }
                    })
                    .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .frame(height: trackHeight)
            .dsShadow(.level1)
            .contentShape(Capsule())
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { gesture in
                        let dx = abs(gesture.translation.width)
                        let dy = abs(gesture.translation.height)

                        // Lock direction on first meaningful movement
                        if isHorizontalDrag == nil && (dx + dy) > 1 {
                            isHorizontalDrag = dx >= dy
                            if isHorizontalDrag == true {
                                dragStartValue = value
                                isDragging = true
                                onEditingChanged?(true)
                            }
                        }

                        guard isHorizontalDrag == true else { return }

                        // Apply full translation immediately (no lost movement)
                        let rangeSpan = range.upperBound - range.lowerBound
                        let delta = Double(gesture.translation.width / usable) * rangeSpan
                        let newValue = dragStartValue + delta
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        if isDragging {
                            isDragging = false
                            onEditingChanged?(false)
                        }
                        isHorizontalDrag = nil
                    }
            )
        }
        .frame(height: trackHeight)
    }
}
