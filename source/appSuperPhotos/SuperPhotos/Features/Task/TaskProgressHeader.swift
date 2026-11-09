import SwiftUI

/// 任务进度头：只统计“已决定”的张数；保险箱与废纸篓不单独显示进度。
struct TaskProgressHeader: View {
    let albumTitle: String
    let processed: Int
    let total: Int
    let isFinished: Bool
    let isExecuting: Bool
    let onPause: () -> Void
    let onFinish: () -> Void

    private var ratio: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(processed) / CGFloat(total))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(albumTitle)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Text.primary)
                        .lineLimit(1)

                    Text("已处理 \(processed) / \(total) 张")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if isExecuting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("统一处理中")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Text.secondary)
                    }
                } else if isFinished {
                    Button("完成整理", action: onFinish)
                        .buttonStyle(
                            NeuButtonStyle(
                                variant: .raisedSmall,
                                cornerRadius: Theme.Radius.chip,
                                tint: Theme.Accent.brass,
                                horizontalPadding: Theme.Spacing.md,
                                verticalPadding: Theme.Spacing.xs
                            )
                        )
                } else {
                    Button("暂停", action: onPause)
                        .buttonStyle(
                            NeuButtonStyle(
                                variant: .raisedSmall,
                                cornerRadius: Theme.Radius.chip,
                                tint: Theme.Text.secondary,
                                horizontalPadding: Theme.Spacing.md,
                                verticalPadding: Theme.Spacing.xs
                            )
                        )
                        .accessibilityHint("保留进度并返回桌面")
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Surface.sunken)
                        .overlay {
                            Capsule().strokeBorder(Theme.Shadow.insetBorder.opacity(0.6), lineWidth: 1)
                        }

                    Capsule()
                        .fill(Theme.Accent.brass)
                        .frame(width: max(0, proxy.size.width * ratio))
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.24), value: ratio)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }
}

#Preview {
    VStack(spacing: 0) {
        TaskProgressHeader(
            albumTitle: "旅行",
            processed: 37,
            total: 100,
            isFinished: false,
            isExecuting: false,
            onPause: {},
            onFinish: {}
        )
        TaskProgressHeader(
            albumTitle: "旅行",
            processed: 100,
            total: 100,
            isFinished: true,
            isExecuting: false,
            onPause: {},
            onFinish: {}
        )
    }
    .background(Theme.Surface.base)
}
