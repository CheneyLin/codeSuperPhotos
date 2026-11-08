import SwiftUI

/// 新拟物表面：凸起 / 小凸起 / 凹陷 / 按下态。
/// 业务页面只能通过 `NeuSurface` 或 `NeuSurfaceBackground` 使用，禁止自行拼阴影。
enum NeuSurfaceStyle {
    /// 卡片、按钮、坞体
    case raised
    /// chip、把手
    case raisedSmall
    /// 炉膛、托盘、输入槽、舞台底槽
    case inset
    /// 按下态，仅由交互组件短暂使用
    case pressed
}

/// 在内容背后铺设一层新拟物表面。
struct NeuSurface<Content: View>: View {
    private let style: NeuSurfaceStyle
    private let cornerRadius: CGFloat
    private let fill: Color?
    private let content: Content

    init(
        style: NeuSurfaceStyle = .raised,
        cornerRadius: CGFloat = Theme.Radius.card,
        fill: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content.background {
            NeuSurfaceBackground(style: style, cornerRadius: cornerRadius, fill: fill)
        }
    }
}

/// 可直接用作 `.background` 的纯表面层。
struct NeuSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    let style: NeuSurfaceStyle
    let cornerRadius: CGFloat
    let fill: Color?

    init(style: NeuSurfaceStyle, cornerRadius: CGFloat, fill: Color? = nil) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.fill = fill
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        switch style {
        case .raised, .raisedSmall, .pressed:
            raised(shape)
        case .inset:
            inset(shape)
        }
    }

    // MARK: - 凸起

    private func raised(_ shape: RoundedRectangle) -> some View {
        let isPressed = style == .pressed
        let isDark = colorScheme == .dark
        let isHighContrast = contrast == .increased

        let offset: CGFloat
        let blur: CGFloat
        let highlightOffset: CGFloat
        let highlightBlur: CGFloat

        switch style {
        case .raised:
            offset = isDark ? 4 : 6
            blur = isDark ? 8 : 12
            highlightOffset = isDark ? -4 : -6
            highlightBlur = isDark ? 6 : 12
        case .raisedSmall:
            offset = isDark ? 2 : 3
            blur = isDark ? 4 : 6
            highlightOffset = isDark ? -2 : -3
            highlightBlur = isDark ? 4 : 6
        case .pressed, .inset:
            offset = 2
            blur = 4
            highlightOffset = -1
            highlightBlur = 2
        }

        let darkAlpha: Double = isPressed ? 1 : 0.9
        let lightAlpha: Double = isPressed ? 0.7 : 1

        return shape
            .fill(fill ?? Theme.Surface.raised)
            .shadow(
                color: Theme.Shadow.dark.opacity(darkAlpha),
                radius: blur,
                x: offset,
                y: offset
            )
            .shadow(
                color: Theme.Shadow.highlight.opacity(lightAlpha),
                radius: highlightBlur,
                x: highlightOffset,
                y: highlightOffset
            )
            .overlay {
                // 左上 1pt 高光描边 + 右下暗描边：暗色模式下保住形体
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Theme.Shadow.raisedBorder,
                            Theme.Shadow.raisedBorder.opacity(0.15),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isHighContrast ? 1.5 : 1
                )
            }
    }

    // MARK: - 凹陷

    private func inset(_ shape: RoundedRectangle) -> some View {
        let isHighContrast = contrast == .increased

        return shape
            .fill(fill ?? Theme.Surface.sunken)
            .overlay {
                // SwiftUI 无原生内阴影：用偏移描边 + 裁剪模拟
                shape
                    .strokeBorder(Theme.Shadow.dark, lineWidth: 4)
                    .blur(radius: 3)
                    .offset(x: 2, y: 2)
                    .clipShape(shape)
            }
            .overlay {
                shape
                    .strokeBorder(Theme.Shadow.highlight, lineWidth: 4)
                    .blur(radius: 3)
                    .offset(x: -2, y: -3)
                    .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(Theme.Shadow.insetBorder, lineWidth: isHighContrast ? 1.5 : 1)
            }
    }
}

// MARK: - 便捷修饰符

extension View {
    func neuSurface(
        _ style: NeuSurfaceStyle = .raised,
        cornerRadius: CGFloat = Theme.Radius.card,
        fill: Color? = nil
    ) -> some View {
        background {
            NeuSurfaceBackground(style: style, cornerRadius: cornerRadius, fill: fill)
        }
    }
}

#Preview("明暗对比") {
    HStack(spacing: Theme.Spacing.xl) {
        surfaceSample
            .environment(\.colorScheme, .light)
        surfaceSample
            .environment(\.colorScheme, .dark)
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.Surface.base)
}

private var surfaceSample: some View {
    VStack(spacing: Theme.Spacing.xl) {
        Text("Raised")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.secondary)
            .frame(width: 140, height: 72)
            .neuSurface(.raised, cornerRadius: Theme.Radius.card)

        Text("Small")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.secondary)
            .frame(width: 140, height: 40)
            .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)

        Text("Inset")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.secondary)
            .frame(width: 140, height: 72)
            .neuSurface(.inset, cornerRadius: Theme.Radius.card)
    }
}
