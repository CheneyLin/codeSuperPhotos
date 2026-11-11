import SwiftUI

/// 新拟物按钮样式：凸起 / 凹陷，按下时压平并轻微缩放。
struct NeuButtonStyle: ButtonStyle {
    var variant: NeuSurfaceStyle = .raised
    var cornerRadius: CGFloat = Theme.Radius.card
    var tint: Color = Theme.Text.primary
    var horizontalPadding: CGFloat = Theme.Spacing.lg
    var verticalPadding: CGFloat = Theme.Spacing.md

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(tint)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .background {
                NeuSurfaceBackground(
                    style: pressedStyle(isPressed: configuration.isPressed),
                    cornerRadius: cornerRadius
                )
            }
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .neuAnimation(.fast, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func pressedStyle(isPressed: Bool) -> NeuSurfaceStyle {
        guard isPressed else { return variant }
        return variant == .inset ? .inset : .pressed
    }
}

/// 圆形图标按钮，固定 44×44 点击区。
struct NeuIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = Theme.Metrics.minTouchTarget
    var tint: Color = Theme.Text.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background {
                NeuSurfaceBackground(
                    style: configuration.isPressed ? .pressed : .raisedSmall,
                    cornerRadius: Theme.Radius.capsule(height: diameter)
                )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .neuAnimation(.fast, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == NeuButtonStyle {
    static var neuRaised: NeuButtonStyle { NeuButtonStyle(variant: .raised) }
    static var neuInset: NeuButtonStyle { NeuButtonStyle(variant: .inset) }
}

extension ButtonStyle where Self == NeuIconButtonStyle {
    static var neuIcon: NeuIconButtonStyle { NeuIconButtonStyle() }
}

/// 胶囊主按钮：随主题强反相——亮色模式深色实体 + 浅白字，暗色模式纯白实体 + 深墨字，
/// 保证按钮从页面底色中跳出来。用于桌面 / 结算 / 保险箱等主 CTA（开始 / 继续整理 /
/// 完成整理 / 再整理一批 / 开门 / 下一步 / 确认保存 等）。不再使用品牌强调色（黄铜）。
struct NeuPillButtonStyle: ButtonStyle {
    /// 底色与文字均走随主题强反相的 token：亮色深色实体 + 浅白字，暗色纯白实体 + 深墨字。
    /// 不再提供品牌强调色（黄铜）变体，所有主 CTA 统一使用这套反相配色。
    var fill: Color = Theme.Surface.pillButton
    var tint: Color = Theme.Text.pillButton
    var font: Font = Theme.Typography.headline
    var horizontalPadding: CGFloat = 32
    var minWidth: CGFloat = 132
    var minHeight: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .background(Capsule(style: .continuous).fill(fill))
            .shadow(color: .black.opacity(0.18), radius: 9, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Capsule())
            .neuAnimation(.fast, value: configuration.isPressed)
    }
}

/// 文字型次级按钮：无背景，仅图标 + 文字，用于次要操作（如“直接结束”“恢复”）。
/// 图标尺寸由调用方在 label 内自行设定（建议 18pt），文字走统一字号档。
struct NeuTextButtonStyle: ButtonStyle {
    var font: Font = Theme.Typography.body.weight(.medium)
    var tint: Color = Theme.Text.secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(tint)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
            .neuAnimation(.fast, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NeuPillButtonStyle {
    static var neuPill: NeuPillButtonStyle { NeuPillButtonStyle() }
}

extension ButtonStyle where Self == NeuTextButtonStyle {
    static var neuText: NeuTextButtonStyle { NeuTextButtonStyle() }
}

#Preview("按钮") {
    VStack(spacing: Theme.Spacing.xl) {
        Button("开始整理") {}
            .buttonStyle(.neuRaised)

        Button {
        } label: {
            Label("存入保险箱", systemImage: "lock")
        }
        .buttonStyle(.neuPill)

        Button("危险操作") {}
            .buttonStyle(NeuButtonStyle(variant: .inset, tint: Theme.State.danger))

        Button {
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.neuIcon)
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.Surface.base)
}
