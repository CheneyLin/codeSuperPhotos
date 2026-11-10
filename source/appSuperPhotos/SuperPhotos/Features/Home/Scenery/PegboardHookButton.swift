import SwiftUI

/// 洞洞板上的悬挂道具按钮：挂钩 + 3D 图标，按下时轻微摆动。
struct PegboardHookButton: View {
    let assetName: String
    let title: String
    var iconSize: CGFloat = 54
    /// 自增时绕「上边中点」轻晃一次；由外部在需要提示时触发。
    var swayToken: Int = 0
    /// 处理态禁用：保留占位与布局，只降到 50% 透明度。
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    @State private var isPressed = false

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// 提示摆动的关键帧值；用结构体承载，便于 KeyframeTrack 驱动。
    private struct Sway {
        var angle: Double = 0
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: -1) {
                //hook

                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .rotationEffect(.degrees(isPressed ? 7 : 0), anchor: .top)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 5)
                    // 提示摆动：只绕上边中点转，不绕中心；减弱动态效果时幅度为 0。
                    .keyframeAnimator(initialValue: Sway(), trigger: swayToken) { content, value in
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !isPressed else { return }
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
    }

    private var hook: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Theme.Scenery.hook)
                .frame(width: 3, height: 12)

            Circle()
                .stroke(Theme.Scenery.hook, lineWidth: 2.5)
                .frame(width: 8, height: 8)
                .offset(y: -3)
        }
        .frame(height: 15)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        SceneryBackgroundView()
        HStack {
            PegboardHookButton(assetName: "icon_vault_keys", title: "保险箱") {}
            Spacer()
            PegboardHookButton(assetName: "icon_tool_screwdriver", title: "设置", iconSize: 50) {}
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// 洞洞板上的小圆形操作按钮：处理态才出现，最小 64pt 命中区。
struct PegboardActionButton: View {
    let assetName: String
    let accessibilityTitle: String
    var accessibilityHintText: String = ""
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 4)
                // 命中区严格等于 44pt 圆形，不向四周透明放大。
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 64, height: 64)
        .contentShape(Circle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(isEnabled ? accessibilityHintText : "当前不可用")
    }
}
