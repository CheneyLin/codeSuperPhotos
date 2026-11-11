import SwiftUI
import UIKit

/// 底部销毁道具：五款素材共用同一个落点，轻点循环切换。
///
/// 三段动效彼此独立、互不抢触发源：
/// - `switchToken`：切换瞬间的「缩小 → 弹出 → 回弹」+ 素材交叉淡化；
/// - `shakeToken`：照片落入时按当前道具播放专属反馈（晃 / 压 / 燃 / 弹 / 开门）；
/// - 常驻微动：壁炉火星、碎纸机纸屑、任意门微光， TimelineView 驱动。
///
    /// 布局高度恒为 100 + 4 + bottomInset，与旧版纸篓一致；指示点与名称牌
    /// 全部走 overlay，不参与排版，`DockHeightKey` 量到的值不变。
    /// 五点选择指示器与名称牌都在切换后自动渐隐（约 1.4s），静息时不占视觉。
struct DestroyDock: View {
    /// 本批待删除张数。
    let pendingCount: Int
    /// 每次自增触发一次「照片落入」反馈。
    let shakeToken: Int
    /// 当前展示的道具。
    let machine: MachineKind
    /// 每次自增触发一次切换动效。
    let switchToken: Int
    /// 轻点切换回调（由外部负责持久化、音效与 LCD 提示）。
    let onSwitch: () -> Void
    /// 无 Home indicator 的设备由外部补的最小留白（safeAreaInset 已消费安全区时传 0）。
    var bottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    @State private var isNameVisible = false
    @State private var nameDismissToken = 0
    /// 五点选择指示器在切换后自动渐隐；启动即显示，1.4s 后淡出，静息时不占视觉。
    @State private var pageDotsVisible = true
    @State private var pageDotsDismissToken = 0

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        dockBody
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, 4 + bottomInset)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 主体

    private var dockBody: some View {
        ZStack(alignment: .bottom) {
            // 落在木桌上的软投影：五款道具共用，切换时不跳。
            Ellipse()
                .fill(Theme.Scenery.desk.opacity(0.28))
                .frame(width: 112, height: 20)
                .blur(radius: 7)
                .offset(y: 5)

            deviceIcon
        }
        .frame(width: 132 * (is_iPad ? 2.0 : 1.0), height: 100 * (is_iPad ? 2.0 : 1.0))
        .overlay(alignment: .bottom) { pageDots }
        .overlay(alignment: .top) { nameBadge }
        // 命中区只覆盖道具本身，不把整条桌面都变成按钮。
        .contentShape(Rectangle())
        .onTapGesture { onSwitch() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(machine.displayName)，本批待删除 \(pendingCount) 张")
        .accessibilityHint("轻点切换到下一个销毁道具；下滑照片可\(machine.dropVerb)，任务结束时统一删除")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "切换道具") { onSwitch() }
        .onChange(of: switchToken) { _, newValue in
            guard newValue > 0 else { return }
            isNameVisible = true
            nameDismissToken += 1
            pageDotsVisible = true
            pageDotsDismissToken += 1
        }
        .task(id: nameDismissToken) {
            guard isNameVisible else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.25)) {
                isNameVisible = false
            }
        }
        .task(id: pageDotsDismissToken) {
            guard pageDotsVisible else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.25)) {
                pageDotsVisible = false
            }
        }
    }

    /// 道具本体：素材切换 + 切换弹跳 + 落入反馈三层叠加。
    private var deviceIcon: some View {
        Image(machine.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 96 * (is_iPad ? 2.0 : 1.0), height: 96 * (is_iPad ? 2.0 : 1.0))
            .shadow(color: Theme.Polaroid.shadow, radius: 9, x: 0, y: 6)
            .id(machine)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.72).combined(with: .opacity)
                        .combined(with: .move(edge: .bottom)),
                    removal: .scale(scale: 1.16).combined(with: .opacity)
                )
            )
            // 常驻微动画在素材之上，火星 / 纸屑才不会被 3D 图标盖住。
            .overlay { DeviceIdleEffect(machine: machine, reduceMotion: reduceMotion) }
            .animation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion), value: machine)
            .keyframeAnimator(
                initialValue: Impact(),
                trigger: shakeToken
            ) { content, value in
                content
                    .rotationEffect(.degrees(value.angle), anchor: .bottom)
                    .scaleEffect(x: value.scaleX, y: value.scaleY, anchor: .bottom)
                    .offset(y: value.offsetY)
                    .rotation3DEffect(
                        .degrees(value.hinge),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.35
                    )
                    .overlay {
                        DeviceImpactGlow(machine: machine)
                            .opacity(value.glow)
                            .allowsHitTesting(false)
                    }
            } keyframes: { _ in
                let profile = machine.impact
                KeyframeTrack(\.angle) {
                    CubicKeyframe(profile.angles[0], duration: 0.09)
                    CubicKeyframe(profile.angles[1], duration: 0.12)
                    CubicKeyframe(profile.angles[2], duration: 0.11)
                    CubicKeyframe(0, duration: 0.14)
                }
                KeyframeTrack(\.scaleY) {
                    CubicKeyframe(1 - profile.squash, duration: 0.09)
                    CubicKeyframe(1 + profile.squash * 0.35, duration: 0.12)
                    CubicKeyframe(1, duration: 0.25)
                }
                KeyframeTrack(\.scaleX) {
                    CubicKeyframe(1 + profile.squash * 0.5, duration: 0.09)
                    CubicKeyframe(1, duration: 0.37)
                }
                KeyframeTrack(\.offsetY) {
                    CubicKeyframe(profile.bounce, duration: 0.09)
                    CubicKeyframe(-profile.bounce * 0.35, duration: 0.12)
                    CubicKeyframe(0, duration: 0.25)
                }
                KeyframeTrack(\.hinge) {
                    CubicKeyframe(profile.hinge, duration: 0.12)
                    CubicKeyframe(profile.hinge * 0.35, duration: 0.16)
                    CubicKeyframe(0, duration: 0.18)
                }
                KeyframeTrack(\.glow) {
                    CubicKeyframe(profile.glow, duration: 0.10)
                    CubicKeyframe(profile.glow * 0.45, duration: 0.16)
                    CubicKeyframe(0, duration: 0.20)
                }
            }
            .keyframeAnimator(
                initialValue: SwitchPop(),
                trigger: switchToken
            ) { content, value in
                content
                    .scaleEffect(CGFloat(value.scale), anchor: .bottom)
                    .rotationEffect(.degrees(value.angle), anchor: .bottom)
                    .offset(y: CGFloat(value.lift))
            } keyframes: { _ in
                let amplitude = reduceMotion ? 0.0 : 1.0
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1 - 0.14 * amplitude, duration: 0.08)
                    CubicKeyframe(1 + 0.08 * amplitude, duration: 0.14)
                    CubicKeyframe(1, duration: 0.16)
                }
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-7 * amplitude, duration: 0.10)
                    CubicKeyframe(4 * amplitude, duration: 0.14)
                    CubicKeyframe(0, duration: 0.14)
                }
                KeyframeTrack(\.lift) {
                    CubicKeyframe(-6 * amplitude, duration: 0.10)
                    CubicKeyframe(0, duration: 0.28)
                }
            }
    }

    // MARK: - 指示器

    /// 底部五点序号：当前道具用自身识别色，其余为中性灰。
    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(MachineKind.allCases) { kind in
                Capsule()
                    .fill(kind == machine ? kind.tint : Theme.Text.tertiary.opacity(0.35))
                    .frame(width: kind == machine ? 12 : 5, height: 4)
                    .animation(Theme.Motion.animation(.fast, reduceMotion: reduceMotion), value: machine)
            }
        }
        // 指示器落在道具下方的桌面上，比素材底边低 10pt；
        // 走 overlay + offset，不占行高，DockHeightKey 仍量到 100pt。
        .offset(y: 10)
        .opacity(pageDotsVisible ? 1 : 0)
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.25), value: pageDotsVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 切换后短暂出现的名称牌，1.4s 自动淡出；静息时不占视觉。
    @ViewBuilder
    private var nameBadge: some View {
        if isNameVisible {
            Text(machine.displayName)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Text.onWhite)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.Surface.pill.opacity(0.94)))
                .shadow(color: Theme.Polaroid.shadow.opacity(0.28), radius: 5, y: 2)
                .offset(y: -22)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 关键帧状态

    /// 落入反馈的可动画字段；五款道具只改幅度，轨迹结构共用。
    private struct Impact {
        var angle: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var offsetY: CGFloat = 0
        var hinge: Double = 0
        var glow: Double = 0
    }

    private struct SwitchPop {
        var scale: Double = 1
        var angle: Double = 0
        var lift: Double = 0
    }
}

// MARK: - 每款道具的落入幅度

private struct ImpactProfile {
    let angles: [Double]
    let squash: CGFloat
    let bounce: CGFloat
    let hinge: Double
    let glow: Double
}

private extension MachineKind {
    /// 废纸篓左右晃、碎纸机压一下、壁炉火光暴涨、邮筒投递回弹、任意门开门。
    var impact: ImpactProfile {
        switch self {
        case .wasteBasket:
            ImpactProfile(angles: [-9, 7, -4], squash: 0, bounce: 0, hinge: 0, glow: 0)
        case .shredder:
            ImpactProfile(angles: [-2, 1.5, -1], squash: 0.10, bounce: 3, hinge: 0, glow: 0.55)
        case .fireplace:
            ImpactProfile(angles: [0, 0, 0], squash: 0, bounce: 0, hinge: 0, glow: 1.0)
        case .mailbox:
            ImpactProfile(angles: [-4, 3, -2], squash: 0.06, bounce: -6, hinge: 0, glow: 0.45)
        case .anyDoor:
            ImpactProfile(angles: [0, 0, 0], squash: 0, bounce: 0, hinge: -38, glow: 0.9)
        }
    }
}

// MARK: - 落入瞬间的辉光

private struct DeviceImpactGlow: View {
    let machine: MachineKind

    var body: some View {
        ZStack {
            switch machine {
            case .fireplace:
                RadialGradient(
                    colors: [Theme.Accent.fire.opacity(0.85), .clear],
                    center: .bottom, startRadius: 2, endRadius: 62
                )
            case .anyDoor:
                RadialGradient(
                    colors: [Theme.Device.door.opacity(0.9), .clear],
                    center: .center, startRadius: 4, endRadius: 62
                )
            case .shredder:
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 56, height: 5)
                    .offset(y: -8)
            case .mailbox:
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.85))
                    .frame(width: 42, height: 7)
                    .offset(y: -14)
            case .wasteBasket:
                EmptyView()
            }
        }
        .frame(width: 96, height: 96)
        .blendMode(.plusLighter)
    }
}

// MARK: - 常驻微动

/// 只在有「活动部件」的三款道具上跑 15fps 的轻量粒子；
/// 降低动效时 TimelineView 暂停，退化为一张静态画面。
private struct DeviceIdleEffect: View {
    let machine: MachineKind
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                switch machine {
                case .fireplace:
                    drawParticles(graphics: &graphics, size: size, time: time, count: 6) {
                        Theme.Accent.fire.opacity(0.75)
                    }
                case .shredder:
                    drawParticles(graphics: &graphics, size: size, time: time, count: 4) {
                        Theme.Device.shredder.opacity(0.6)
                    }
                case .anyDoor:
                    drawParticles(graphics: &graphics, size: size, time: time, count: 5) {
                        Theme.Device.door.opacity(0.75)
                    }
                case .mailbox, .wasteBasket:
                    break
                }
            }
            .frame(width: 96, height: 96)
        }
        .allowsHitTesting(false)
    }

    private func drawParticles(
        graphics: inout GraphicsContext,
        size: CGSize,
        time: Double,
        count: Int,
        color: () -> Color
    ) {
        for index in 0..<count {
            let seed = Double(index)
            let cycle = 1.1 + (seed * 0.37).truncatingRemainder(dividingBy: 1) * 0.8
            let life = (time / cycle + seed * 0.41).truncatingRemainder(dividingBy: 1)
            let x = size.width * (0.34 + 0.32 * (seed * 0.318).truncatingRemainder(dividingBy: 1))
            let y = size.height * (0.62 - life * 0.34)
            let radius = 1.1 + (1 - life) * 1.4
            graphics.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(color().opacity(1 - life))
            )
        }
    }
}

private struct DestroyDockPreviewHost: View {
    @State private var index = 0
    @State private var switchToken = 0
    @State private var shakeToken = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            HStack(spacing: 12) {
                ForEach(MachineKind.allCases.indices, id: \.self) { offset in
                    Image(MachineKind.allCases[offset].assetName)
                        .resizable().scaledToFit()
                        .frame(width: 52, height: 52)
                        .opacity(offset == index ? 1 : 0.45)
                }
            }
            DestroyDock(
                pendingCount: 12,
                shakeToken: shakeToken,
                machine: MachineKind.allCases[index],
                switchToken: switchToken,
                onSwitch: {
                    index = (index + 1) % MachineKind.allCases.count
                    switchToken += 1
                }
            )
            Button("模拟落入") { shakeToken += 1 }
                .buttonStyle(.bordered)
        }
        .background(Theme.Scenery.backdrop)
    }
}

#Preview("五款道具") {
    DestroyDockPreviewHost()
}
