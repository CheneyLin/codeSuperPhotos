import SwiftUI

/// 新首屏：默认不展示任何照片，只保留相册图标和“开始/继续”入口。
struct TaskDeskView: View {
    let isTaskActive: Bool
    let isTaskFinished: Bool
    let albumTitle: String
    let processed: Int
    let total: Int
    /// 当前任务里的废纸篓队列张数；为 0 时不显示提示行。
    let pendingDestroy: Int
    let onStart: () -> Void
    let onResume: () -> Void
    /// 未处理的照片按“保留”收尾并直接进入结算。
    let onFinishNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: Theme.Spacing.xl)

            albumIcon

            if isTaskActive {
                VStack(spacing: 6) {
                    Text(isTaskFinished ? "上一批已处理完" : "上次整理到「\(albumTitle)」")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Text.primary)
                        .multilineTextAlignment(.center)

                    Text(isTaskFinished ? "点下方按钮统一加密与删除" : "已处理 \(processed) / \(total) 张")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.secondary)
                }
            }

            VStack(spacing: Theme.Spacing.md) {
                // 废纸篓队列提示：只在本批已有待删除时才出现，避免常驻干扰。
                if isTaskActive, pendingDestroy > 0 {
                    Text("待删除 \(pendingDestroy) 张")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.State.danger)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }

                primaryButton

                if isTaskActive, !isTaskFinished {
                    finishNowButton
                }
            }
            .animation(
                Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
                value: isTaskActive
            )

            // 手势提示已上移到中栏顶部的液晶屏里，这里只保留留白。
            Spacer(minLength: Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var primaryTitle: String {
        guard isTaskActive else { return "开始" }
        return isTaskFinished ? "完成整理" : "继续整理"
    }

    private var primaryButton: some View {
        Button {
            if isTaskActive {
                onResume()
            } else {
                onStart()
            }
        } label: {
            Text(primaryTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .buttonStyle(NeuPillButtonStyle())
        .accessibilityLabel(primaryTitle)
        .hitDebugRegion("主按钮")
    }

    private var finishNowButton: some View {
        Button(action: onFinishNow) {
            HStack(spacing: 5) {
                Image("icon_check_circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)

                Text("直接结束")
            }
        }
        // 图标 14→18、文字 12→15（body），整体调大一档，纳入设计系统文字按钮。
        .buttonStyle(NeuTextButtonStyle())
        .accessibilityHint("未处理的照片按保留处理，随后进入结算")
        .hitDebugRegion("直接结束")
    }

    private var albumIcon: some View {
        ZStack {
            // 桌面上的天蓝辉光，呼应右侧收藏夹的选中色。
            Ellipse()
                .fill(Theme.Scenery.sky.opacity(0.22))
                .frame(width: 166 * (is_iPad ? 1.5 : 1.0), height: 60 * (is_iPad ? 1.5 : 1.0))
                .blur(radius: 20)
                .offset(y: 54)

            Image("icon_photo_stack")
                .resizable()
                .scaledToFit()
                .frame(width: 150 * (is_iPad ? 1.5 : 1.0) , height: 150 * (is_iPad ? 1.5 : 1.0))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 9)
        }
        // 尺寸收在中栏内：外层允许被压缩，窄设备上不会挤到两侧栏。
        .frame(maxWidth: 168 * (is_iPad ? 1.5 : 1.0), maxHeight: 190 * (is_iPad ? 1.5 : 1.0))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    TaskDeskView(
        isTaskActive: false,
        isTaskFinished: false,
        albumTitle: "",
        processed: 0,
        total: 0,
        pendingDestroy: 0,
        onStart: {},
        onResume: {},
        onFinishNow: {}
    )
    .background(Theme.Surface.base)
}

#Preview("继续") {
    TaskDeskView(
        isTaskActive: true,
        isTaskFinished: false,
        albumTitle: "旅行",
        processed: 37,
        total: 100,
        pendingDestroy: 8,
        onStart: {},
        onResume: {},
        onFinishNow: {}
    )
    .background(Theme.Surface.base)
}
