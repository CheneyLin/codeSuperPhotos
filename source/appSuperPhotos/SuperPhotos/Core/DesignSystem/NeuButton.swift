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

#Preview("按钮") {
    VStack(spacing: Theme.Spacing.xl) {
        Button("开始整理") {}
            .buttonStyle(.neuRaised)

        Button {
        } label: {
            Label("存入保险箱", systemImage: "lock")
        }
        .buttonStyle(NeuButtonStyle(variant: .raised, tint: Theme.Accent.brass))

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
