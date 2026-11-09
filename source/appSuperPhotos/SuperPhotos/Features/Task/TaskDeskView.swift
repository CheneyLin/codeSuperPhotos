import SwiftUI

/// 新首屏：默认不展示任何照片，只保留相册图标和“开始”入口。
struct TaskDeskView: View {
    let isTaskActive: Bool
    let isTaskFinished: Bool
    let albumTitle: String
    let processed: Int
    let total: Int
    let onStart: () -> Void
    let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
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
                Button {
                    if isTaskActive {
                        onResume()
                    } else {
                        onStart()
                    }
                } label: {
                    Text(primaryTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Surface.base)
                        .padding(.horizontal, 44)
                        .frame(minHeight: 52)
                        .background {
                            Capsule().fill(Theme.Accent.brass)
                        }
                        .shadow(color: Theme.Accent.brass.opacity(0.35), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryTitle)

                if isTaskActive {
                    Button("重新选择相簿", action: onStart)
                        .buttonStyle(
                            NeuButtonStyle(
                                variant: .raisedSmall,
                                cornerRadius: Theme.Radius.chip,
                                tint: Theme.Text.secondary,
                                horizontalPadding: Theme.Spacing.lg,
                                verticalPadding: Theme.Spacing.xs
                            )
                        )
                }
            }
            .animation(
                Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
                value: isTaskActive
            )

            Spacer(minLength: Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var primaryTitle: String {
        guard isTaskActive else { return "开始" }
        return isTaskFinished ? "完成整理" : "继续整理"
    }

    private var albumIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                .fill(Theme.Surface.raised)
                .frame(width: 132, height: 132)
                .shadow(color: Theme.Shadow.dark, radius: 14, x: 7, y: 7)
                .shadow(color: Theme.Shadow.highlight, radius: 14, x: -7, y: -7)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                        .strokeBorder(Theme.Shadow.raisedBorder, lineWidth: 1)
                }

            Image(systemName: "photo.stack.fill")
                .font(.system(size: 50, weight: .regular))
                .foregroundStyle(Theme.Accent.brass)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Text.secondary)
                        .offset(x: 16, y: 12)
                }
        }
        .frame(width: 148, height: 148)
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
        onStart: {},
        onResume: {}
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
        onStart: {},
        onResume: {}
    )
    .background(Theme.Surface.base)
}
