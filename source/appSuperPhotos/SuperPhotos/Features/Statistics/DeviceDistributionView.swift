import SwiftUI

/// 五款道具的统计展示组件。设置页与统计页共用同一套口径与配色，
/// 避免出现「设置里显示 3 件、统计里显示 2 件」这类分叉。
struct DeviceDistributionBar: View {
    let summary: StatSummary
    var height: CGFloat = 10

    private var activeMachines: [MachineKind] {
        MachineKind.allCases.filter { summary.count(for: $0) > 0 }
    }

    var body: some View {
        GeometryReader { proxy in
            let total = max(summary.destroyed, 1)
            let gap = CGFloat(max(activeMachines.count - 1, 0)) * 2
            let usable = max(0, proxy.size.width - gap)

            HStack(spacing: 2) {
                ForEach(activeMachines) { machine in
                    let ratio = CGFloat(summary.count(for: machine)) / CGFloat(total)
                    Capsule()
                        .fill(machine.tint)
                        .frame(width: max(usable * ratio, 3))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(distributionAccessibilityLabel)
    }

    private var distributionAccessibilityLabel: String {
        let parts = activeMachines.map { "\($0.displayName) \(summary.count(for: $0)) 件" }
        return parts.isEmpty ? "暂无销毁记录" : parts.joined(separator: "，")
    }
}

/// 统计页的五行明细：素材图标 + 名称 + 占比条 + 件数与百分比。
struct DeviceDistributionList: View {
    let summary: StatSummary

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(MachineKind.allCases) { machine in
                row(for: machine)
            }
        }
    }

    private func row(for machine: MachineKind) -> some View {
        let count = summary.count(for: machine)
        let total = max(summary.destroyed, 1)
        let ratio = CGFloat(count) / CGFloat(total)
        let percent = Int((Double(count) / Double(total) * 100).rounded())

        return HStack(spacing: Theme.Spacing.sm) {
            Image(machine.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .opacity(count > 0 ? 1 : 0.45)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(machine.displayName)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Spacer()
                    Text("\(count) 件 · \(percent)%")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Text.primary.opacity(0.09))
                        Capsule()
                            .fill(machine.tint)
                            .frame(width: max(0, proxy.size.width * ratio))
                    }
                }
                .frame(height: 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(machine.displayName) \(count) 件，占 \(percent)%")
    }
}

/// 设置页的五款道具横排选择器；与首页底部点击切换共用 AppSettings。
struct DevicePickerStrip: View {
    let selection: MachineKind
    let onSelect: (MachineKind) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MachineKind.allCases) { machine in
                let isSelected = machine == selection
                Button {
                    onSelect(machine)
                } label: {
                    VStack(spacing: 3) {
                        Image(machine.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 42, height: 42)
                            .opacity(isSelected ? 1 : 0.6)
                        Text(machine.displayName)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.Text.primary : Theme.Text.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(isSelected ? machine.tint.opacity(0.16) : Color.clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .strokeBorder(isSelected ? machine.tint : Color.clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(machine.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

#Preview("分布") {
    VStack(spacing: 24) {
        DeviceDistributionBar(summary: .preview)
        DeviceDistributionList(summary: .preview)
        DevicePickerStrip(selection: .fireplace) { _ in }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Surface.base.ignoresSafeArea())
}

private extension StatSummary {
    /// 仅用于预览的固定样本。
    static var preview: StatSummary {
        var value = StatSummary()
        value.destroyed = 20
        value.wasteBasket = 8
        value.shredder = 5
        value.fireplace = 4
        value.mailbox = 2
        value.anyDoor = 1
        return value
    }
}
