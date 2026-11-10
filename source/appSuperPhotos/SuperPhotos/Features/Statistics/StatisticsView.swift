import SwiftUI

/// 整理统计：今日 / 本周 / 本月（VIP）/ 累计。
struct StatisticsView: View {
    @Environment(StatisticsService.self) private var statistics
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(VaultStore.self) private var vault
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var period: StatPeriod = .today
    @State private var isResetConfirmPresented = false
    @State private var isVIPHintPresented = false
    @State private var toastMessage: ToastMessage?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                periodPicker
                headlineCard
                detailGrid
                preferenceCard
                vaultCard
                footer
                resetButton
            }
            .padding(Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .navigationTitle("整理统计")
        .navigationBarTitleDisplayMode(.inline)
        .alert("重置统计？", isPresented: $isResetConfirmPresented) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                statistics.reset()
                toastMessage = ToastMessage(text: "统计已重置，照片与保险箱不受影响", kind: .warning)
            }
        } message: {
            Text("只清空整理记录与空间估算，不会删除任何照片、保险箱副本或清单。")
        }
        .alert("需要 VIP", isPresented: $isVIPHintPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("免费版提供今日、本周、累计与五款道具分布；本月统计属于 VIP 权益。一期只有模拟开关，不涉及购买。")
        }
        .toast($toastMessage, topPadding: 8)
        .task {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["UI_TEST_STATS_PERIOD"],
               let requested = StatPeriod(rawValue: raw),
               !requested.requiresVIP || entitlements.isEnabled(.statsAdvanced) {
                period = requested
            }
            #endif
        }
    }

    private var summary: StatSummary {
        statistics.summary(for: period)
    }

    // MARK: - 周期

    private var periodPicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(StatPeriod.allCases) { option in
                Button {
                    select(option)
                } label: {
                    HStack(spacing: 3) {
                        if option.requiresVIP && !entitlements.isEnabled(.statsAdvanced) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(option.title)
                            .font(Theme.Typography.caption.weight(.semibold))
                    }
                    .foregroundStyle(
                        period == option ? Theme.Text.primary : Theme.Text.secondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .neuSurface(
                        period == option ? .inset : .raisedSmall,
                        cornerRadius: Theme.Radius.chip
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(period == option ? .isSelected : [])
            }
        }
    }

    private func select(_ option: StatPeriod) {
        if option.requiresVIP && !entitlements.isEnabled(.statsAdvanced) {
            isVIPHintPresented = true
            return
        }
        withAnimation(Theme.Motion.animation(.fast, reduceMotion: reduceMotion)) {
            period = option
        }
    }

    // MARK: - 大数

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\(period.title)已清理")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)

            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(summary.destroyed)")
                    .font(Theme.Typography.display.monospacedDigit())
                    .foregroundStyle(Theme.Text.primary)
                    .contentTransition(.numericText())
                Text("件")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Text.secondary)
            }

            HStack(spacing: Theme.Spacing.xs) {
                Text("释放空间 ≈ \(summary.readableDestroyedBytes)")
                    .font(Theme.Typography.body.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)
                if summary.bytesUnknown > 0 {
                    Text("· \(summary.bytesUnknown) 件大小未知")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 明细

    private var detailGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Spacing.md),
                      GridItem(.flexible(), spacing: Theme.Spacing.md)],
            spacing: Theme.Spacing.md
        ) {
            metricCard(title: "已入库", value: "\(summary.imported)", unit: "件", symbol: "lock.fill")
            metricCard(title: "已取出", value: "\(summary.restored)", unit: "件", symbol: "arrow.uturn.backward")
            metricCard(title: "已浏览", value: "\(summary.browsed)", unit: "张", symbol: "eye")
            metricCard(title: "连续整理", value: "\(statistics.streak())", unit: "天", symbol: "flame")
        }
    }

    private func metricCard(title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Text.tertiary)
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.title.monospacedDigit())
                    .foregroundStyle(Theme.Text.primary)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 道具使用分布

    /// 五款道具的件数与占比对所有档位开放：这是「用了哪款道具」的客观记录，
    /// 与 VIP 的「本月周期 / 趋势报告」不是同一类信息。
    private var preferenceCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("道具使用分布")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Text.primary)
                Spacer()
                if let top = summary.topMachine {
                    Text("最常用 · \(top.displayName)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }
            }

            if summary.destroyed == 0 {
                Text("这个周期还没有销毁记录。")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.secondary)
            } else {
                DeviceDistributionBar(summary: summary, height: 12)
                DeviceDistributionList(summary: summary)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 保险箱占用

    private var vaultCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Accent.brass)

            VStack(alignment: .leading, spacing: 2) {
                Text("保险箱占用")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
                Text("\(vault.records.count) 件 · \(vault.totalBytes > 0 ? VaultLimits.readableBytes(vault.totalBytes) : "0 KB")")
                    .font(Theme.Typography.headline.monospacedDigit())
                    .foregroundStyle(Theme.Text.primary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 页脚与重置

    private var footer: some View {
        Text("口径：已浏览 = 单次停留 ≥ 0.5 秒的照片，按唯一资产计；已销毁件数按当时选中的道具（废纸篓 / 碎纸机 / 壁炉 / 邮筒 / 任意门）分别统计，占比以本周期销毁总数为分母；释放空间为本地资源大小估算，iCloud 未下载的资产计为未知；系统『最近删除』保留 30 天，空间由系统延迟回收。")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetButton: some View {
        Button {
            isResetConfirmPresented = true
        } label: {
            Text("重置统计")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeuButtonStyle(variant: .inset, tint: Theme.State.danger))
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
            .environment(StatisticsService())
            .environment(EntitlementStore())
            .environment(VaultStore())
    }
}
