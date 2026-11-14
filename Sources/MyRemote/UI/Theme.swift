import SwiftUI

// MARK: - 调色板（取自 Duolingo juicy 色板）

enum Duo {

    // 品牌色
    static let owl       = Color(hex: 0x58CC02)   // 主绿
    static let treeFrog  = Color(hex: 0x58A700)   // 绿·底边
    static let seaSponge = Color(hex: 0xD7FFB8)   // 绿·浅
    static let macaw     = Color(hex: 0x1CB0F6)   // 蓝
    static let whale     = Color(hex: 0x1899D6)   // 蓝·底边
    static let iguana    = Color(hex: 0xDDF4FF)   // 蓝·浅
    static let bee       = Color(hex: 0xFFC800)   // 黄
    static let beeDark   = Color(hex: 0xE5A800)   // 黄·底边
    static let beeLight  = Color(hex: 0xFFF4CC)   // 黄·浅
    static let beetle    = Color(hex: 0xCE82FF)   // 紫
    static let lily      = Color(hex: 0xA568CC)   // 紫·底边
    static let beetleLight = Color(hex: 0xF4E8FF) // 紫·浅
    static let cardinal  = Color(hex: 0xFF4B4B)   // 红
    static let fireAnt   = Color(hex: 0xEA2B2B)   // 红·底边
    static let walkingFish = Color(hex: 0xFFDFE0) // 红·浅
    static let fox       = Color(hex: 0xFF9600)   // 橙

    // 中性色
    static let eel    = Color(hex: 0x4B4B4B)      // 主文字
    static let wolf   = Color(hex: 0x777777)      // 次文字
    static let hare   = Color(hex: 0xAFAFAF)      // 弱文字
    static let swan   = Color(hex: 0xE5E5E5)      // 描边
    static let polar  = Color(hex: 0xF7F7F7)      // 背景
    static let white  = Color.white

    // 圆角 / 尺寸
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 16
    static let lipHeight: CGFloat = 3
}

// MARK: - 字体（系统圆体近似 Duolingo 的 DIN Round）

extension Font {
    static func duo(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let duoDisplay = Font.duo(30, .heavy)
    static let duoTitle = Font.duo(22, .heavy)
    static let duoHeading = Font.duo(17, .heavy)
    static let duoBody = Font.duo(14, .medium)
    static let duoBodyBold = Font.duo(14, .bold)
    static let duoCaption = Font.duo(12, .medium)
    static let duoCaptionBold = Font.duo(12, .bold)
    static let duoLabel = Font.duo(11, .heavy)
}

// MARK: - 基础组件

extension View {

    /// Duolingo 风格卡片：白底、2px 描边、22 圆角、可选彩色浅底。
    func duoCard(_ fill: Color = Duo.white,
                 border: Color = Duo.swan,
                 padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Duo.cardRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Duo.cardRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 2)
            )
    }
}

/// 大写小标题，Duolingo 常用样式。
struct DuoSectionLabel: View {
    let text: String
    var color: Color = Duo.hare

    var body: some View {
        Text(text.localized)
            .font(.duoLabel)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// 主按钮：实色 + 底部深色「lip」，按下时下沉。
struct DuoPrimaryButtonStyle: ButtonStyle {
    var color: Color = Duo.owl
    var lip: Color = Duo.treeFrog
    var foreground: Color = .white
    var height: CGFloat = 44
    var radius: CGFloat = Duo.controlRadius
    var expand: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.duo(14, .heavy))
            .tracking(0.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(maxWidth: expand ? .infinity : nil)
            .frame(height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(lip)
                        .offset(y: Duo.lipHeight)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(color)
                }
            )
            .offset(y: configuration.isPressed ? Duo.lipHeight : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// 次要按钮：白底描边 + 灰色 lip。
struct DuoSecondaryButtonStyle: ButtonStyle {
    var foreground: Color = Duo.eel
    var border: Color = Duo.swan
    var height: CGFloat = 40
    var expand: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.duo(13, .heavy))
            .tracking(0.4)
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(maxWidth: expand ? .infinity : nil)
            .frame(height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Duo.controlRadius, style: .continuous)
                        .fill(Duo.swan)
                        .offset(y: 2)
                    RoundedRectangle(cornerRadius: Duo.controlRadius, style: .continuous)
                        .fill(Duo.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: Duo.controlRadius, style: .continuous)
                                .strokeBorder(border, lineWidth: 2)
                        )
                }
            )
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// 圆形图标按钮。
struct DuoIconButton: View {
    let systemName: String
    var tint: Color = Duo.eel
    var background: Color = Duo.polar
    var size: CGFloat = 38
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .overlay(Circle().strokeBorder(Duo.swan, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// 胶囊标签。
struct DuoChip: View {
    let text: String
    var color: Color = Duo.treeFrog
    var background: Color = Duo.seaSponge
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text.localized).font(.duo(11, .heavy))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
    }
}

/// 圆点状态。
struct DuoDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// 进度条：浅色轨道 + 粗胶囊 + 顶部高光。
struct DuoProgressBar: View {
    var value: Double
    var color: Color = Duo.owl
    var track: Color = Duo.swan
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.28))
                            .frame(height: height * 0.38)
                            .padding(.horizontal, height * 0.28)
                            .padding(.top, height * 0.12)
                    }
            }
        }
        .frame(height: height)
    }
}

/// Duolingo 风开关。
struct DuoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Duo.owl : Duo.swan)
                    .frame(width: 46, height: 28)
                Circle()
                    .fill(Duo.white)
                    .frame(width: 22, height: 22)
                    .padding(.horizontal, 3)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "开" : "关")
    }
}

/// 自动换行的横向布局（标签组）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 输入框样式。
struct DuoTextField: View {
    let placeholder: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder.localized).foregroundStyle(Duo.hare))
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 13, design: .monospaced) : .duoBody)
            .foregroundStyle(Duo.eel)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Duo.polar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Duo.swan, lineWidth: 2)
            )
    }
}

// MARK: - 颜色扩展

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
