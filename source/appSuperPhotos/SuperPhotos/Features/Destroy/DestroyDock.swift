import SwiftUI
import UIKit

/// 销毁坞：炉膛/刀口 + 本批待销毁计数。
/// 任务式流程下不再在坞内执行销毁，只在任务结束时统一交给系统删除。
struct DestroyDock: View {
    let machine: MachineKind
    let phase: DestroyPhase
    let progress: Double
    /// 本批待销毁张数。
    let pendingCount: Int
    let isExpanded: Bool
    /// 无 Home indicator 的设备由外部补的最小留白（safeAreaInset 已消费安全区时传 0）。
    var bottomInset: CGFloat = 0

    /// 点击炉口/刀口：让当前照片执行一次“下滑入待销毁”的等效动作。
    let onTapMouth: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        VStack(spacing: isExpanded ? 8 : 6) {
            mouth
            footer
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, isExpanded ? 14 : 12)
        .padding(.bottom, (isExpanded ? 12 : 8) + bottomInset)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.Radius.dock,
                topTrailingRadius: Theme.Radius.dock,
                style: .continuous
            )
            .fill(Theme.Surface.raised)
            .overlay(alignment: .top) {
                // 上边缘内凹槽，与舞台分隔
                Capsule()
                    .fill(Theme.Surface.sunken)
                    .frame(width: 56, height: 5)
                    .overlay {
                        Capsule().strokeBorder(Theme.Shadow.insetBorder.opacity(0.6), lineWidth: 1)
                    }
                    .padding(.top, 6)
            }
            .shadow(color: Theme.Shadow.dark.opacity(0.55), radius: 12, x: 0, y: -4)
        }
        .animation(
            Theme.Motion.animation(.spring, reduceMotion: reduceMotion),
            value: isExpanded
        )
        .animation(
            Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
            value: machine
        )
    }

    // MARK: - 机器口

    private var mouth: some View {
        ZStack {
            if machine == .fireplace {
                FireplaceMouth(phase: phase, progress: progress)
            } else {
                ShredderMouth(phase: phase, progress: progress)
            }

            if phase == .idle {
                Text(machine == .fireplace ? "下滑照片，丢进炉口" : "下滑照片，丢进刀口")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? 88 : 40)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous))
        .onTapGesture {
            guard phase == .idle || phase == .finished else { return }
            onTapMouth()
        }
        .accessibilityElement()
        .accessibilityLabel(machine == .fireplace ? "壁炉炉口" : "碎纸机刀口")
        .accessibilityHint("点击把当前照片加入本批待销毁")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTapMouth() }
        .animation(
            Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
            value: isExpanded
        )
    }

    // MARK: - 托盘

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text("待销毁 \(pendingCount) 张")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(pendingCount > 0 ? tint : Theme.Text.secondary)

                Text("本批结束后统一删除")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Text.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本批待销毁 \(pendingCount) 张，任务结束时统一交给系统删除")

            Spacer(minLength: Theme.Spacing.sm)
        }
        .frame(minHeight: 36)
    }

    private var tint: Color {
        machine == .fireplace ? Theme.Accent.fire : Theme.Accent.metal
    }
}

// MARK: - 顶部机器选择器

/// 顶部栏正中的主控：壁炉 / 碎纸机。点按或横滑切换。
struct DestroyMachineSelector: View {
    let machine: MachineKind
    let onSwitch: (MachineKind) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MachineKind.allCases) { kind in
                chip(kind)
            }
        }
        .padding(3)
        .neuSurface(.inset, cornerRadius: Theme.Radius.chip)
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    dragOffset = value.translation.width * 0.35
                }
                .onEnded { value in
                    defer {
                        withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
                            dragOffset = 0
                        }
                    }
                    guard abs(value.translation.width) > 40 else { return }
                    let target: MachineKind = value.translation.width < 0 ? .shredder : .fireplace
                    if target != machine {
                        onSwitch(target)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
        )
        .animation(
            Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
            value: machine
        )
    }

    private func chip(_ kind: MachineKind) -> some View {
        let isSelected = kind == machine
        return Button {
            guard !isSelected else { return }
            onSwitch(kind)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(kind.displayName)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isSelected
                    ? (kind == .fireplace ? Theme.Accent.fire : Theme.Accent.metal)
                    : Theme.Text.tertiary
            )
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minHeight: 30)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isSelected ? Theme.Surface.raised : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
