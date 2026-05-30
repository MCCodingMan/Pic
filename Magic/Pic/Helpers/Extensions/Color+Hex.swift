import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Design System Tokens

enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Weight {
        static let regular: Font.Weight = .regular
        static let medium: Font.Weight = .medium
        static let semibold: Font.Weight = .semibold
        static let bold: Font.Weight = .bold
    }

    enum TextStyle {
        case h1, title, headline, subheadline, body, callout, footnote, caption

        var font: Font {
            switch self {
            case .h1: return .largeTitle
            case .title: return .title2
            case .headline: return .headline
            case .subheadline: return .subheadline
            case .body: return .body
            case .callout: return .callout
            case .footnote: return .footnote
            case .caption: return .caption
            }
        }

        var defaultWeight: Font.Weight {
            switch self {
            case .h1, .title, .headline: return DS.Weight.semibold
            default: return DS.Weight.regular
            }
        }
    }

    struct ColorToken {
        private static func makeColor(_ hex: String) -> Color {
            let hexStr = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hexStr).scanHexInt64(&int)
            let a, r, g, b: UInt64
            switch hexStr.count {
            case 3:
                (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6:
                (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
            case 8:
                (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            default:
                (a, r, g, b) = (255, 255, 255, 255)
            }
            return Color(.sRGB,
                         red: Double(r) / 255,
                         green: Double(g) / 255,
                         blue: Double(b) / 255,
                         opacity: Double(a) / 255)
        }
        static func brandPrimary(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#3B82F6") : makeColor("#246BFD")
        }
        static func brandSecondary(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#60A5FA") : makeColor("#1F8EFA")
        }
        static func accent(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#FDBA74") : makeColor("#FFAA00")
        }
        static func success(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#86EFAC") : makeColor("#22C55E")
        }
        static func warning(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#FBBF24") : makeColor("#F59E0B")
        }
        static func danger(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#F87171") : makeColor("#EF4444")
        }
        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#111827") : makeColor("#FFFFFF")
        }
        static func surfaceAlt(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#1F2937") : makeColor("#F9FAFB")
        }
        static func outline(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#374151") : makeColor("#E5E7EB")
        }
        static func textPrimary(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#F9FAFB") : makeColor("#111827")
        }
        static func textSecondary(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? makeColor("#D1D5DB") : makeColor("#4B5563")
        }
        static var onBrand: Color { Color.white }
        static var onBlack: Color { Color.black }
    }

    enum Elevation {
        case level1, level2, level3, level4

        func parameters(for scheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
            let baseColor = scheme == .dark ? Color.white : Color.black
            switch self {
            case .level1: return (baseColor.opacity(scheme == .dark ? 0.30 : 0.08), 8, 0, 2)
            case .level2: return (baseColor.opacity(scheme == .dark ? 0.35 : 0.10), 16, 0, 4)
            case .level3: return (baseColor.opacity(scheme == .dark ? 0.40 : 0.12), 24, 0, 8)
            case .level4: return (baseColor.opacity(scheme == .dark ? 0.45 : 0.16), 32, 0, 12)
            }
        }
    }

    struct ShadowModifier: ViewModifier {
        @Environment(\.colorScheme) var scheme
        let elevation: Elevation
        func body(content: Content) -> some View {
            let p = elevation.parameters(for: scheme)
            content.shadow(color: p.color, radius: p.radius, x: p.x, y: p.y)
        }
    }

    struct TextStyleModifier: ViewModifier {
        let style: TextStyle
        let weight: Font.Weight?
        func body(content: Content) -> some View {
            content.font(style.font).fontWeight(weight ?? style.defaultWeight)
        }
    }
}

extension View {
    func dsShadow(_ elevation: DS.Elevation) -> some View {
        modifier(DS.ShadowModifier(elevation: elevation))
    }
    func dsCorner(_ radius: CGFloat = DS.Radius.md) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    @ViewBuilder func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}

extension Text {
    func dsStyle(_ style: DS.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(DS.TextStyleModifier(style: style, weight: weight))
    }
}

// MARK: - AppButton Component

enum ButtonVariant {
    case primary
    case secondary
    case tertiary
    case destructive
    case ghost
}

enum ButtonSize {
    case small
    case medium
    case large
}

struct AppButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var scheme
    let variant: ButtonVariant
    let size: ButtonSize
    let loading: Bool

    private var height: CGFloat {
        switch size {
        case .small: return 36
        case .medium: return 44
        case .large: return 52
        }
    }

    private var hPadding: CGFloat {
        switch size {
        case .small: return DS.Space.md
        case .medium: return DS.Space.lg
        case .large: return DS.Space.xl
        }
    }
    
    // 字体大小
    private var fontSize: CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 16
        case .large: return 18
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        // 背景与描边
        let bg: Color
        let fg: Color
        let border: Color?

        switch variant {
        case .primary:
            bg = DS.ColorToken.brandPrimary(scheme)
            fg = DS.ColorToken.onBrand
            border = nil
        case .secondary:
            bg = DS.ColorToken.surfaceAlt(scheme)
            fg = DS.ColorToken.textPrimary(scheme)
            border = DS.ColorToken.outline(scheme)
        case .tertiary:
            bg = .clear
            fg = DS.ColorToken.brandPrimary(scheme)
            border = nil
        case .destructive:
            bg = DS.ColorToken.danger(scheme)
            fg = DS.ColorToken.onBrand
            border = nil
        case .ghost:
            bg = .clear
            fg = DS.ColorToken.textPrimary(scheme)
            border = DS.ColorToken.outline(scheme)
        }

        return configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .frame(height: height)
            .padding(.horizontal, hPadding)
            .background(bg.opacity(loading ? 0.7 : (isPressed ? 0.85 : 1.0)))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(border ?? .clear, lineWidth: border != nil ? 1 : 0)
            )
            .foregroundColor(fg.opacity(loading ? 0.7 : 1.0))
            .dsCorner(DS.Radius.md)
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .dsShadow(variant == .tertiary || variant == .ghost ? .level1 : .level2)
            .opacity(loading ? 0.9 : 1.0)
            .overlay(alignment: .center) {
                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: fg))
                        .accessibilityLabel(Text("加载中"))
                }
            }
            .accessibilityAddTraits(.isButton)
    }
}

struct AppButton: View {
    let title: String
    let variant: ButtonVariant
    let size: ButtonSize
    let loading: Bool
    let icon: Image?
    let fullWidth: Bool
    let action: () -> Void

    init(_ title: String,
         variant: ButtonVariant = .primary,
         size: ButtonSize = .medium,
         loading: Bool = false,
         icon: Image? = nil,
         fullWidth: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.variant = variant
        self.size = size
        self.loading = loading
        self.icon = icon
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                if let icon = icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: size == .small ? 14 : (size == .medium ? 18 : 20),
                               height: size == .small ? 14 : (size == .medium ? 18 : 20))
                }
                
                if loading {
                    Text(title).opacity(0) // 占位保持宽度
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(AppButtonStyle(variant: variant, size: size, loading: loading))
        .disabled(loading)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Card Component

enum CardVariant {
    case elevated
    case flat
    case outlined
}

struct Card<Content: View>: View {
    @Environment(\.colorScheme) var scheme
    let variant: CardVariant
    let padding: CGFloat
    let content: Content

    init(variant: CardVariant = .elevated,
         padding: CGFloat = DS.Space.lg,
         @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let bg = DS.ColorToken.surface(scheme)
        let border = DS.ColorToken.outline(scheme)

        VStack(alignment: .leading, spacing: DS.Space.md) {
            content
        }
        .padding(padding)
        .background(bg)
        .dsCorner(DS.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(variant == .outlined ? border : .clear, lineWidth: variant == .outlined ? 1 : 0)
        )
        .if(variant == .elevated) { v in
            v.dsShadow(.level2)
        }
    }
}
