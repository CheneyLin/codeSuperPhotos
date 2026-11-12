import SwiftUI

/// 洞洞板上的道具按钮：3D 图标，按下时轻微摆动。
///
/// 由旧版 `PegboardActionButton`（圆形操作按钮）合并而来，并已移除挂钩（hook）图形，
/// 仅保留图标与摆动动画，统一用于保险箱 / 设置 / 撤销 / 结束等入口。
///
/// 不可用态（`isEnabled == false`）的行为——不再用 `.disabled` 拦截交互：
/// - 按钮仍可点，不阻止交互；
/// - 优先换用 `disabledAssetName` 图片（未提供则复用正图，均不降透明度）；
/// - 点击时不执行绑定的 `action`，而是绕「上边中点」晃动一次作为拒绝提示。
///
/// 尺寸：iPad 上整体放大到 150%（图标与命中框同比例），其余设备保持原尺寸。
struct PegboardHookButton: View {
    let assetName: String
    /// 无障碍标签（原 hook 用 `title`、原 action 用 `accessibilityTitle`，合并为统一字段）。
    let title: String
    var iconSize: CGFloat = 54
    /// 自增时绕「上边中点」轻晃一次；由外部在需要提示时触发。
    var swayToken: Int = 0
    /// 是否可执行绑定的 `action`。false 时换 disable 图、点击只晃动不执行。
    var isEnabled: Bool = true
    /// 不可用态自定义图片（可选）。提供时不可用态显示该图、不使用透明度。
    var disabledAssetName: String? = nil
    /// 无障碍提示语（仅启用态朗读）。
    var accessibilityHintText: String = ""
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    @State private var isPressed = false
    /// 不可用态点击的「拒绝」晃动令牌：自增即触发一次晃动提示。
    @State private var denyToken = 0

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// 整体缩放系数：iPad 放大到 150%，其余设备保持 100%。图标与命中框同比例放大。
    private let scale: CGFloat = is_iPad ? 1.5 : 1.0

    /// 当前应显示的图片：不可用且提供了 `disabledAssetName` 时换图，否则用正图。
    private var imageName: String {
        isEnabled ? assetName : (disabledAssetName ?? assetName)
    }

    /// 提示摆动的关键帧值；用结构体承载，便于 KeyframeTrack 驱动。
    private struct Sway {
        var angle: Double = 0
    }

    /// 晃动触发源：外部提示（`hint`）与不可用态点击拒绝（`deny`）任一变化都触发同一段晃动。
    private struct ShakeTrigger: Equatable {
        var hint: Int
        var deny: Int
    }

    var body: some View {
        Button {
            if isEnabled {
                action()
            } else {
                denyToken += 1
            }
        } label: {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize * scale, height: iconSize * scale)
                .rotationEffect(.degrees(isPressed ? 7 : 0), anchor: .top)
                .shadow(color: .black.opacity(0.18), radius: 6 * scale, x: 0, y: 5 * scale)
                // 提示摆动：只绕上边中点转，不绕中心；减弱动态效果时幅度为 0。
                // `swayToken` 为外部提示，`denyToken` 为不可用态点击的拒绝提示，
                // 二者任一变化都触发同一段晃动。
                .keyframeAnimator(initialValue: Sway(), trigger: ShakeTrigger(hint: swayToken, deny: denyToken)) { content, value in
                    content.rotationEffect(.degrees(value.angle), anchor: .top)
                } keyframes: { _ in
                    let amplitude: Double = reduceMotion ? 0 : 1
                    KeyframeTrack(\.angle) {
                        CubicKeyframe(-5 * amplitude, duration: 0.16)
                        CubicKeyframe(4 * amplitude, duration: 0.16)
                        CubicKeyframe(-2.5 * amplitude, duration: 0.14)
                        CubicKeyframe(0, duration: 0.16)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 64 * scale, height: 64 * scale)
        .contentShape(Circle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
                        isPressed = false
                    }
                }
        )
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? accessibilityHintText : "当前不可用，轻点会晃动提示".localized)
    }
}

#Preview {
    ZStack {
        SceneryBackgroundView()
        HStack {
            PegboardHookButton(assetName: "icon_vault_keys", title: "保险箱", iconSize: 64) {}
            Spacer()
            PegboardHookButton(assetName: "icon_config", title: "设置", iconSize: 64) {}
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
