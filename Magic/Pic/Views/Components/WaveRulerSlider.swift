//
//  WaveRulerSlider.swift
//  Magic
//
//  Created by CoderWan on 2026/4/17.
//



import SwiftUI

struct WaveRulerSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var majorTickInterval: Int = 10
    var minorTickInterval: Int = 5
    var showValue: Bool = true
    var defaultMarkerValue: Double?
    
    @State private var scrollIndex: Int?
    @State private var lastHapticIndex: Int?
    @State private var isSyncingFromScroll = false
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    
    private let tickSpacing: CGFloat = 6
    private let rulerHeight: CGFloat = 35
    private let labelHeight: CGFloat = 14
    private let labelSpacing: CGFloat = 3
    private let ratio: CGFloat = 10
    
    private var rulerContentHeight: CGFloat {
        rulerHeight + labelSpacing + labelHeight
    }
    
    private var totalTicks: Int {
        let safeStep = max(step, 0.0001)
        let span = max(range.upperBound - range.lowerBound, 0)
        return max(Int((span / safeStep).rounded(.down)), 0)
    }
    
    private var displayValue: Double {
        valueForIndex(currentIndex)
    }
    
    private var currentIndex: Int {
        let safeStep = max(step, 0.0001)
        let raw = ((clampedValue - range.lowerBound) / safeStep).rounded()
        return min(max(Int(raw), 0), totalTicks)
    }
    
    private var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
    
    private var safeMajorTickInterval: Int {
        max(majorTickInterval, 1)
    }
    
    private var safeMinorTickInterval: Int {
        max(minorTickInterval, 1)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showValue {
                Text("\(Int(displayValue))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            GeometryReader { geometry in
                let horizontalInset = max((geometry.size.width - tickSpacing) / 2, 0)
                
                ZStack(alignment: .top) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 0) {
                            ForEach(0...totalTicks, id: \.self) { i in
                                tickView(for: i)
                                    .id(i)
                            }
                        }
                        .frame(height: rulerContentHeight)
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                    .scrollPosition(id: $scrollIndex, anchor: .center)
                    .onAppear {
                        scrollIndex = currentIndex
                        lastHapticIndex = currentIndex
                        hapticGenerator.prepare()
                    }
                    .onChange(of: scrollIndex) { _, newValue in
                        guard let index = newValue else { return }
                        let snapped = valueForIndex(index)
                        if abs(snapped - value) > 0.0001 {
                            isSyncingFromScroll = true
                            value = snapped
                            isSyncingFromScroll = false
                        }
                        if shouldTriggerHaptic(for: index), lastHapticIndex != index {
                            hapticGenerator.impactOccurred(intensity: 0.7)
                            hapticGenerator.prepare()
                            lastHapticIndex = index
                        }
                    }
                    .onChange(of: value) { _, _ in
                        guard !isSyncingFromScroll else { return }
                        let target = currentIndex
                        if scrollIndex != target {
                            scrollIndex = target
                        }
                    }
                    
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 2, height: rulerHeight)
                        .allowsHitTesting(false)

                    if let markerX = defaultMarkerX(horizontalInset: horizontalInset) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 2, height: 22)
                            .position(x: markerX, y: 11)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: rulerContentHeight)
        }
        .padding(.horizontal, 20)
    }
    
    private func tickView(for index: Int) -> some View {
        let isMajor = index % safeMajorTickInterval == 0
        let isMinor = index % safeMinorTickInterval == 0
        let isCurrent = index == currentIndex
        
        let baseHeight: CGFloat
        let tickWidth: CGFloat
        let tickColor: Color
        
        if isMajor {
            baseHeight = 18
            tickWidth = 2
            tickColor = .white
        } else if isMinor {
            baseHeight = 15
            tickWidth = 1.5
            tickColor = .white.opacity(0.6)
        } else {
            baseHeight = 15
            tickWidth = 1
            tickColor = .white.opacity(0.3)
        }
        
        let tickHeight = isCurrent ? rulerHeight : baseHeight
        let shouldShowLabel = isMajor || isMinor
        
        return VStack(spacing: labelSpacing) {
            RoundedRectangle(cornerRadius: tickWidth / 2)
                .fill(tickColor)
                .frame(width: tickWidth, height: tickHeight)
                .frame(width: tickSpacing, height: rulerHeight, alignment: .bottom)
            
            if shouldShowLabel {
                Text(tickLabel(for: index))
                    .font(.system(size: 9, weight: isMajor ? .semibold : .regular))
                    .foregroundColor(tickColor)
                    .fixedSize()
                    .frame(height: labelHeight)
            } else {
                Color.clear
                    .frame(height: labelHeight)
            }
        }
        .frame(width: tickSpacing, height: rulerContentHeight)
        .animation(.easeInOut(duration: 0.18), value: isCurrent)
    }
    
    private func valueForIndex(_ index: Int) -> Double {
        let safeStep = max(step, 0.0001)
        let raw = range.lowerBound + Double(index) * safeStep
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        return clamped
    }
    
    private func tickLabel(for index: Int) -> String {
        let tickValue = valueForIndex(index)
        let rounded = tickValue.rounded()
        if abs(tickValue - rounded) < 0.0001 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", tickValue)
    }

    private func shouldTriggerHaptic(for index: Int) -> Bool {
        index % safeMinorTickInterval == 0
    }

    private func defaultMarkerX(horizontalInset: CGFloat) -> CGFloat? {
        guard let defaultMarkerValue else { return nil }
        let clamped = min(max(defaultMarkerValue, range.lowerBound), range.upperBound)
        let safeStep = max(step, 0.0001)
        let rawIndex = ((clamped - range.lowerBound) / safeStep).rounded()
        let markerIndex = min(max(Int(rawIndex), 0), totalTicks)
        return horizontalInset + CGFloat(markerIndex) * tickSpacing + tickSpacing / 2
    }
}
