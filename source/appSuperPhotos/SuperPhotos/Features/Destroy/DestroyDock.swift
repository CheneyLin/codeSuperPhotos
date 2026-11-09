import SwiftUI
import UIKit

/// 底部纸篓：桌面场景里的实体桶。
/// 照片下滑落入时左右晃动一次；暂不提供点击交互，
/// 壁炉/碎纸机留待后续在纸篓区左右滑动切换。
struct DestroyDock: View {
    /// 本批待删除张数。
    let pendingCount: Int
    /// 每次自增触发一次晃动。
    let shakeToken: Int
    /// 无 Home indicator 的设备由外部补的最小留白（safeAreaInset 已消费安全区时传 0）。
    var bottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// 晃动关键帧值；用结构体承载，便于 KeyframeTrack 驱动。
    private struct BinShake {
        var angle: Double = 0
    }

    var body: some View {
        // 只留纸篓本体：张数不再用文字胶囊呈现，晃动与音效保持不变。
        bin
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 4 + bottomInset)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("废纸篓，本批待删除 \(pendingCount) 张")
            .accessibilityHint("下滑照片可加入废纸篓，任务结束时统一删除")
    }

    // MARK: - 纸篓

    private var bin: some View {
        ZStack(alignment: .bottom) {
            // 落在木桌上的软投影
            Ellipse()
                .fill(Theme.Scenery.desk.opacity(0.28))
                .frame(width: 112, height: 20)
                .blur(radius: 7)
                .offset(y: 5)

            Image("icon_bin_waste")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: Theme.Polaroid.shadow, radius: 9, x: 0, y: 6)
        }
        .frame(height: 100)
        .keyframeAnimator(
            initialValue: BinShake(),
            trigger: shakeToken
        ) { content, value in
            content.rotationEffect(.degrees(value.angle), anchor: .bottom)
        } keyframes: { _ in
            // 左右衰减摆动：幅度大→小→停，像被照片撞了一下。
            KeyframeTrack(\.angle) {
                CubicKeyframe(reduceMotion ? -2.5 : -9, duration: 0.09)
                CubicKeyframe(reduceMotion ? 1.5 : 7, duration: 0.12)
                CubicKeyframe(reduceMotion ? -0.8 : -4, duration: 0.11)
                CubicKeyframe(0, duration: 0.14)
            }
        }
    }
}

#Preview("纸篓") {
    VStack {
        Spacer()
        DestroyDock(pendingCount: 0, shakeToken: 0)
        DestroyDock(pendingCount: 12, shakeToken: 0)
    }
    .background(Theme.Scenery.backdrop)
}
