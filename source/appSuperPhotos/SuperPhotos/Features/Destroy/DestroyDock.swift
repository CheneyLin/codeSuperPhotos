import SwiftUI
import UIKit

/// 销毁坞：机器选择条 + 炉膛/刀口 + 待处理托盘。
/// 折叠 132 / 展开 208；只有机器选择条响应横滑切换。
struct DestroyDock: View {
    let machine: MachineKind
    let phase: DestroyPhase
    let progress: Double
    let tickets: [DestroyTicket]
    let pendingCount: Int
    /// 累积到该张数时点亮销毁指示灯并弹出确认（默认 10）。
    let autoConfirmThreshold: Int
    let thumbnails: ThumbnailProvider
    let isExpanded: Bool
    /// 无 Home indicator 的设备由外部补的最小留白（safeAreaInset 已消费安全区时传 0）。
    var bottomInset: CGFloat = 0

    let onSwitchMachine: (MachineKind) -> Void
    /// 点击炉口/刀口：让当前照片执行一次“下滑入待销毁”的等效动作。
    let onTapMouth: () -> Void
    let onStart: () -> Void
    let onCancel: () -> Void
    let onClear: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var selectorDragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: isExpanded ? 8 : 6) {
            machineSelector
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

    // MARK: - 机器选择条

    private var machineSelector: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(MachineKind.allCases) { kind in
                machineChip(kind)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if phase.canCancel {
                Button("取消", action: onCancel)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.State.danger)
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .transition(.opacity)
            } else if !tickets.isEmpty {
                Button("清空", action: onClear)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Text.tertiary)
                    .buttonStyle(.plain)
            }
        }
        .frame(height: isExpanded ? 32 : 28)
        .contentShape(Rectangle())
        .offset(x: selectorDragOffset)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard phase == .idle || phase == .finished else { return }
                    selectorDragOffset = value.translation.width * 0.35
                }
                .onEnded { value in
                    defer {
                        withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
                            selectorDragOffset = 0
                        }
                    }
                    guard abs(value.translation.width) > 40 else { return }
                    let target: MachineKind = value.translation.width < 0 ? .shredder : .fireplace
                    if target != machine {
                        onSwitchMachine(target)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
        )
    }

    private func machineChip(_ kind: MachineKind) -> some View {
        let isSelected = kind == machine
        return Button {
            onSwitchMachine(kind)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(kind.displayName)
                    .font(Theme.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(
                isSelected
                    ? (kind == .fireplace ? Theme.Accent.fire : Theme.Accent.metal)
                    : Theme.Text.tertiary
            )
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: isExpanded ? 32 : 28)
            .neuSurface(
                isSelected ? .inset : .raisedSmall,
                cornerRadius: Theme.Radius.chip
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 机器口

    private var mouth: some View {
        ZStack {
            if machine == .fireplace {
                FireplaceMouth(phase: phase, progress: progress)
            } else {
                ShredderMouth(phase: phase, progress: progress)
            }

            if let first = tickets.first, phase.isBusy {
                destroyingThumbnail(for: first.id)
            }

            if phase == .charging {
                chargingOverlay
            }

            if phase == .armed || (phase == .idle && tickets.isEmpty) {
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
        .accessibilityHint("点击把当前照片加入待销毁累积")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTapMouth() }
        .animation(
            Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
            value: isExpanded
        )
    }

    @ViewBuilder
    private func destroyingThumbnail(for localID: String) -> some View {
        let isDestroying = phase == .destroying || phase == .awaitingSystemConfirm

        DockThumbnail(localID: localID, side: 56, thumbnails: thumbnails)
            .scaleEffect(isDestroying ? 0.25 : 1)
            .opacity(isDestroying ? 0.05 : (phase == .ejecting ? 0.4 : 1))
            .rotationEffect(.degrees(isDestroying ? -8 : 0))
            .offset(y: isDestroying ? 6 : (phase == .ejecting ? -8 : 0))
            .animation(
                .easeIn(duration: machine.destroyDuration * 0.8),
                value: isDestroying
            )
            .animation(
                Theme.Motion.animation(.spring, reduceMotion: reduceMotion),
                value: phase == .ejecting
            )
            .allowsHitTesting(false)
    }

    private var chargingOverlay: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Surface.sunken)
                    .frame(height: 6)
                Capsule()
                    .fill(machine == .fireplace ? Theme.Accent.fire : Theme.Accent.metal)
                    .frame(width: max(6, 160 * progress), height: 6)
            }
            .frame(width: 160)

            Text(pendingCount >= autoConfirmThreshold ? "将销毁 \(pendingCount) 张 · 可点取消退回" : "即将销毁 · 点取消可退回")
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Text.secondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)
        .allowsHitTesting(false)
    }

    // MARK: - 托盘

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isReady ? tint : Theme.Surface.sunken)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle().strokeBorder(
                                isReady ? tint.opacity(0.9) : Theme.Shadow.insetBorder,
                                lineWidth: 1
                            )
                        }
                        .shadow(color: isReady ? tint.opacity(0.65) : .clear, radius: 7)
                        .animation(
                            Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
                            value: isReady
                        )

                    Text("待销毁 \(tickets.count) / \(autoConfirmThreshold)")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(isReady ? tint : Theme.Text.secondary)

                    if isReady {
                        Text("已满")
                            .font(Theme.Typography.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }

                progressBar
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("待销毁 \(tickets.count) 张，达到 \(autoConfirmThreshold) 张自动触发确认")
            .accessibilityValue("\(tickets.count) / \(autoConfirmThreshold)")

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                onStart()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("销毁")
                        .font(Theme.Typography.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 32)
                .background {
                    Capsule().fill(
                        tickets.isEmpty || phase.isBusy
                            ? Theme.Text.tertiary.opacity(0.35)
                            : tint
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(tickets.isEmpty || phase.isBusy)
            .accessibilityLabel("确认销毁待累积的 \(tickets.count) 张照片")
        }
        .frame(minHeight: 36)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Surface.sunken)
                    .overlay {
                        Capsule().strokeBorder(Theme.Shadow.insetBorder.opacity(0.7), lineWidth: 1)
                    }

                Capsule()
                    .fill(tint)
                    .frame(width: max(0, proxy.size.width * progressRatio))
                    .opacity(tickets.isEmpty ? 0 : 1)
            }
        }
        .frame(height: 7)
        .animation(
            Theme.Motion.animation(.standard, reduceMotion: reduceMotion),
            value: progressRatio
        )
        .accessibilityHidden(true)
    }

    private var progressRatio: CGFloat {
        guard autoConfirmThreshold > 0 else { return 0 }
        return min(1, CGFloat(tickets.count) / CGFloat(autoConfirmThreshold))
    }

    private var isReady: Bool {
        tickets.count >= autoConfirmThreshold
    }

    private var tint: Color {
        machine == .fireplace ? Theme.Accent.fire : Theme.Accent.metal
    }
}

// MARK: - 托盘缩略图

struct DockThumbnail: View {
    let localID: String
    let side: CGFloat
    let thumbnails: ThumbnailProvider

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.Surface.sunken)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.Shadow.raisedBorder, lineWidth: 1)
        }
        .task(id: localID) {
            image = await thumbnails.image(
                for: localID,
                targetSize: CGSize(width: side * UIScreen.main.scale, height: side * UIScreen.main.scale)
            )
        }
    }
}
