import SwiftUI

/// 左侧保险箱：嵌在左墙里的保险箱实体，照片左滑飞入时轻跳一下；轻点打开私密保险箱。
///
/// 视觉沿用用户调整后的「大图 + 左侧嵌墙」：绘制边长 = 基准边长 × 3，
/// 图标右边缘贴住左栏右边缘，左侧约 65% 落在屏幕外。
/// 命中区单独定义：从屏幕左边缘到左栏右边缘、高度等于图标可见高度，
/// 与可见箱体严格重合；不再拿放大后的整张图标当按钮，
/// 避免热区跑到屏外（点不到）或越界压住中栏（抢舞台手势）。
struct VaultDoorColumn: View {
    let width: CGFloat
    let count: Int
    /// 照片是否正落入；每次置位触发一次跳动。
    let isOpen: Bool
    /// 与左上角钥匙按钮共用同一个入口（打开私密保险箱）。
    let onOpen: () -> Void

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

    /// 基准边长：跟着左栏收放；同时被 HomeView 用来反推飞入落点。
    /// 注意这是「放大前」的参考值，不是屏幕上的实际绘制边长。
    static func iconSize(for width: CGFloat) -> CGFloat {
        min(max(64, width * 1.05), 132)
    }

    /// 视觉放大倍数（沿用临时调整的 3 倍），只影响绘制，不参与命中区。
    static let visualScale: CGFloat = 3
    /// 图标露出屏幕的比例：0.35 表示左侧 65% 嵌在墙里。
    static let peekRatio: CGFloat = 0.35

    /// 实际绘制边长。
    static func visualSize(for width: CGFloat) -> CGFloat {
        iconSize(for: width) * visualScale
    }

    /// 可见箱体中心相对屏幕左边缘的 x；HomeView 用它算左滑飞入落点。
    static func visibleCenterX(for width: CGFloat) -> CGFloat {
        visualSize(for: width) * peekRatio / 2
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = hitGeometry(in: proxy)

            ZStack {
                // 视觉层：只负责画，不接收任何命中，放大后溢出屏幕的部分也不会变成热区。
                vaultIcon(size: geometry.iconSize)
                    .frame(width: geometry.iconSize, height: geometry.iconSize)
                    .position(x: geometry.iconCenterX, y: proxy.size.height / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // 命中层：透明按钮，矩形与「可见箱体」同宽同高，垂直居中。
                Button(action: onOpen) {
                    Color.clear
                        .frame(width: geometry.hitWidth, height: geometry.hitHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: geometry.hitCenterX, y: proxy.size.height / 2)
                .accessibilityLabel("私密保险箱，已存 \(count) 件")
                .accessibilityHint("点按打开私密保险箱")
                .accessibilityAddTraits(.isButton)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .onChange(of: isOpen) { _, open in
            guard open else { return }
            bounceToken += 1
        }
    }

    // MARK: - 几何

    /// 视觉落点与命中区的一次性计算结果，避免在 body 里散落 magic number。
    private struct HitGeometry {
        let iconSize: CGFloat
        let iconCenterX: CGFloat
        let hitCenterX: CGFloat
        let hitWidth: CGFloat
        let hitHeight: CGFloat
    }

    private func hitGeometry(in proxy: GeometryProxy) -> HitGeometry {
        let iconSize = Self.visualSize(for: width)
        let columnMinX = proxy.frame(in: .global).minX

        // 图标右边缘贴住左栏右边缘；.position 用 GeometryReader 局部坐标，
        // 所以中心 = 栏宽 − 半边长（负值即左侧嵌进墙里）。
        let iconCenterX = proxy.size.width - iconSize / 2

        // 命中区从屏幕左边缘（全局 x = 0）铺到左栏右边缘（全局 x = columnMinX + 栏宽）。
        // 左边界换算成局部坐标是 −columnMinX，宽度因此是 columnMinX + 栏宽。
        let hitMinX = -columnMinX
        let hitWidth = columnMinX + proxy.size.width
        let hitHeight = min(iconSize, proxy.size.height)

        return HitGeometry(
            iconSize: iconSize,
            iconCenterX: iconCenterX,
            hitCenterX: hitMinX + hitWidth / 2,
            hitWidth: hitWidth,
            hitHeight: hitHeight
        )
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
        VaultDoorColumn(width: 78, count: 5, isOpen: false, onOpen: {})
        VaultDoorColumn(width: 78, count: 5, isOpen: true, onOpen: {})
        VaultDoorColumn(width: 148, count: 0, isOpen: false, onOpen: {})
    }
    .frame(height: 460)
    .padding()
    .background(Theme.Scenery.backdrop)
}
