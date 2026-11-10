import SwiftUI

/// 左侧保险箱：挂在墙上的保险箱图标，照片左滑飞入时图标轻跳一下作为反馈。
///
/// 位置：整栏垂直居中，并有 25% 的图标宽度超出屏幕左边缘（当作嵌在墙里）。
struct VaultDoorColumn: View {
    let width: CGFloat
    let count: Int
    /// 照片是否正落入；每次置位触发一次跳动。
    let isOpen: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// 跳动关键帧值；用结构体承载，便于 KeyframeTrack 驱动。
    private struct VaultBounce {
        var lift: CGFloat = 0
        var scale: CGFloat = 1
    }

    /// 每次照片落入自增，作为跳动触发器；不绑定 `isOpen` 的回落时刻。
    @State private var bounceToken = 0

    /// 图标边长：跟着左栏收放；同时被 HomeView 用来算飞入落点。
    static func iconSize(for width: CGFloat) -> CGFloat {
        min(max(64, width * 1.05), 132)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = Self.iconSize(for: width)
            // 图标中心落在屏幕坐标 0.25×边长处：左边缘正好有 25% 在屏幕外。
            let originX = proxy.frame(in: .global).minX
            let centerX = -0.45 * size - originX

            Button(action: onTap) {
                vaultIcon(size: size*3)
            }
            .buttonStyle(.plain)
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .position(x: centerX, y: proxy.size.height / 2)
            .accessibilityLabel("私密保险箱，已存 \(count) 件")
            .accessibilityHint("点按查看预览，解锁后可管理")
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .onChange(of: isOpen) { _, open in
            guard open else { return }
            bounceToken += 1
        }
    }

    // MARK: - 实体

    private func vaultIcon(size: CGFloat) -> some View {
        ZStack {
            // 照片落入时的暖光，只做呼吸式淡入淡出。
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.Accent.brass.opacity(0.4))
                .frame(width: size * 0.9, height: size * 0.9)
                .blur(radius: size * 0.22)
                .opacity(isOpen ? 1 : 0)
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.24), value: isOpen)

            Image("image_vault")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 6)
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: VaultBounce(), trigger: bounceToken) { content, value in
            content
                .offset(y: value.lift)
                .scaleEffect(value.scale, anchor: .bottom)
        } keyframes: { _ in
            // 轻跳后落回：幅度与时长对齐纸篓晃动，降低动效时更短更小。
            KeyframeTrack(\.lift) {
                CubicKeyframe(reduceMotion ? -2 : -7, duration: reduceMotion ? 0.07 : 0.10)
                CubicKeyframe(0, duration: reduceMotion ? 0.10 : 0.18)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(reduceMotion ? 1.02 : 1.06, duration: reduceMotion ? 0.07 : 0.10)
                CubicKeyframe(1, duration: reduceMotion ? 0.10 : 0.18)
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        VaultDoorColumn(width: 78, count: 5, isOpen: false, onTap: {})
        VaultDoorColumn(width: 78, count: 5, isOpen: true, onTap: {})
        VaultDoorColumn(width: 148, count: 0, isOpen: false, onTap: {})
    }
    .frame(height: 460)
    .padding()
    .background(Theme.Scenery.backdrop)
}
