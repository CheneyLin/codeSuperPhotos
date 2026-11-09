import SwiftUI

/// 一次任务的收尾结算。
struct TaskSettlement: Identifiable, Equatable {
    let id = UUID()
    let albumTitle: String
    let total: Int
    let kept: Int
    let snoozed: Int
    let encrypted: Int
    let deleted: Int
    /// 在系统确认框里取消、未能执行的部分；原图仍在相册。
    let cancelled: Int
    /// 加密或删除失败的部分；原图仍在相册。
    let failed: Int
}

/// 结算页：给出明确结果，并允许直接开始下一轮。
struct TaskSettlementView: View {
    let settlement: TaskSettlement
    let onNext: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.Surface.base.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer(minLength: Theme.Spacing.xl)

                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46, weight: .regular))
                        .foregroundStyle(Theme.Accent.brass)

                    Text("本次整理完成")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Text.primary)

                    Text("「\(settlement.albumTitle)」· 共 \(settlement.total) 张")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    statRow(title: "加密", value: settlement.encrypted, tint: Theme.Accent.brass)
                    statRow(title: "删除", value: settlement.deleted, tint: Theme.State.danger)
                    statRow(title: "保留", value: settlement.kept, tint: Theme.Text.primary)
                    statRow(title: "延后", value: settlement.snoozed, tint: Theme.Text.secondary)
                }
                .padding(Theme.Spacing.md)
                .neuSurface(.inset, cornerRadius: Theme.Radius.card)

                if settlement.cancelled > 0 {
                    Text("有 \(settlement.cancelled) 张在系统确认框中被取消：原图保留在相册，未写入重复副本。")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                if settlement.failed > 0 {
                    Text("有 \(settlement.failed) 张未能加密或删除，原图保留在相册，可在下一批重试。")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }

                VStack(spacing: Theme.Spacing.md) {
                    Button {
                        onNext()
                    } label: {
                        Text("再整理一批")
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Surface.base)
                            .padding(.horizontal, 40)
                            .frame(minHeight: 50)
                            .background { Capsule().fill(Theme.Accent.brass) }
                    }
                    .buttonStyle(.plain)

                    Button("返回桌面", action: onClose)
                        .buttonStyle(
                            NeuButtonStyle(
                                variant: .raisedSmall,
                                cornerRadius: Theme.Radius.chip,
                                tint: Theme.Text.secondary,
                                horizontalPadding: Theme.Spacing.xl,
                                verticalPadding: Theme.Spacing.xs
                            )
                        )
                }

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private func statRow(title: String, value: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Text.secondary)

            Spacer()

            Text("\(value) 张")
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TaskSettlementView(
        settlement: TaskSettlement(
            albumTitle: "旅行",
            total: 100,
            kept: 62,
            snoozed: 8,
            encrypted: 18,
            deleted: 12,
            cancelled: 0,
            failed: 0
        ),
        onNext: {},
        onClose: {}
    )
}
