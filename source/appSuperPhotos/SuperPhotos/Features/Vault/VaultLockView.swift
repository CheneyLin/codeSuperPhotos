import SwiftUI
import UIKit

/// 全屏密码盘锁屏。未设置密码时进入“设置密码”流程。
struct VaultLockView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    private enum Mode: Equatable {
        case unlock
        case setupFirst
        case setupConfirm
    }

    @State private var left = 0
    @State private var right = 0
    @State private var mode: Mode = .unlock
    @State private var errorText: String?
    @State private var isVerifying = false
    @State private var shakeOffset: CGFloat = 0

    @State private var isLocked = false
    @State private var remainingSeconds = 0

    @State private var setupFirstCombo: (a: Int, b: Int)?
    @State private var pendingCombo: (a: Int, b: Int)?
    @State private var showComboAck = false

    @State private var isRoomOpen = false
    @State private var contentScale: CGFloat = 1
    @State private var contentOpacity: Double = 1

    var body: some View {
        ZStack {
            Theme.Surface.base.ignoresSafeArea()

            if isRoomOpen {
                VaultRoomView()
                    .transition(.opacity)
            } else {
                lockContent
                    .scaleEffect(contentScale)
                    .opacity(contentOpacity)
                    .offset(x: shakeOffset)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isRoomOpen {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.neuIcon)
                .accessibilityLabel("关闭保险箱")
                .padding(.trailing, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: vault.isUnlocked) { _, unlocked in
            guard !unlocked, isRoomOpen else { return }
            isRoomOpen = false
            left = 0
            right = 0
            errorText = nil
            refreshLockState()
        }
        #if DEBUG
        .task {
            // "1" = 正确组合；"wrong" = 错误组合。两者都必须显式按一次「开门」。
            let hook = ProcessInfo.processInfo.environment["UI_TEST_VAULT_AUTOUNLOCK"]
            guard hook == "1" || hook == "wrong" else { return }
            guard mode == .unlock else { return }
            try? await Task.sleep(for: .milliseconds(900))
            left = hook == "wrong" ? 3 : 7
            right = hook == "wrong" ? 3 : 23
            try? await Task.sleep(for: .milliseconds(300))
            attemptUnlock()
        }
        #endif
        .task {
            while !Task.isCancelled {
                refreshLockState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("密码已设置", isPresented: $showComboAck) {
            Button("我记下了") {
                isRoomOpen = true
            }
        } message: {
            Text("你的组合是：左盘 \(pendingCombo?.a ?? 0) / 右盘 \(pendingCombo?.b ?? 0)。忘记后无法找回，请立即记下。")
        }
    }

    // MARK: - 主体

    private var lockContent: some View {
        GeometryReader { proxy in
            // 左盘（小）直径按可用宽度收敛，右盘（大）放大到 150%。
            let small = min(
                (proxy.size.width - Theme.Spacing.page * 2) / 2.4,
                150
            )
            let large = small * 1.5
            // 图标随可用宽度自适应并放大到 150%，约束在合理区间以适配不同设备。
            let iconSize = min(max(proxy.size.width * 0.15, 52), 84) * 1.5

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: Theme.Spacing.lg)   // 顶部图标上方留白

                    // 上区：图标 + 标题（无 tips）
                    VStack(spacing: Theme.Spacing.md) {
                        headerIcon(iconSize)
                        Text(titleText)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Text.primary)
                    }

                    Spacer(minLength: Theme.Spacing.lg)

                    // 中区：密码盘
                    dials(small: small, large: large)

                    Spacer(minLength: Theme.Spacing.lg)

                    // 下区：提示条（共用 tips 与错误，常驻）+ 主按钮 + 预留的“重新来过”文字按钮
                    VStack(spacing: Theme.Spacing.lg) {
                        hintBar
                        actionArea
                        redoSlot
                    }

                    Spacer(minLength: Theme.Spacing.lg)   // 按钮下方留白
                }
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// 上区图标：直接展示 icon_vault，无圆框。
    private func headerIcon(_ size: CGFloat) -> some View {
        Image("icon_vault")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// 按钮上方常驻提示条：默认显示 tips；出错 / 锁定 / 核对中时切换为对应提示；
    /// 当两盘均为 0 时给出「0+0 不可作密码」的警示。复用原内嵌（inset）样式与 44 高度。
    private var hintBar: some View {
        let message: String?
        let tone: Color

        if isLocked {
            message = "已锁定，请在 \(countdownText) 后重试"
            tone = Theme.State.danger
        } else if isVerifying {
            message = "正在核对组合…"
            tone = Theme.State.danger
        } else if let errorText {
            message = errorText
            tone = Theme.State.danger
        } else if left == 0, right == 0 {
            message = "0 + 0 不可作为密码，请转动密码盘设置组合"
            tone = Theme.State.warning
        } else {
            message = nil
            tone = Theme.Text.secondary
        }

        let text = message ?? subtitleText

        return Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(tone)
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .neuSurface(.inset, cornerRadius: Theme.Radius.card)
    }

    /// 错落双盘：左盘（小）居左上、右盘（大，150%）居右下，水平交叠形成错落。
    private func dials(small: CGFloat, large: CGFloat) -> some View {
        let overlap = small * 0.30
        let drop = (large - small) * 0.6 + 80

        return HStack(alignment: .top, spacing: -overlap) {
            DialView(
                label: "左盘 A · 0–\(VaultCredentials.leftMaxDialValue)",
                count: VaultCredentials.leftDialCount,
                value: $left,
                isEnabled: dialsEnabled,
                diameter: small
            ) {
                errorText = nil
            }

            DialView(
                label: "右盘 B · 0–\(VaultCredentials.rightMaxDialValue)",
                count: VaultCredentials.rightDialCount,
                value: $right,
                isEnabled: dialsEnabled,
                diameter: large
            ) {
                errorText = nil
            }
            .offset(y: drop)
        }
        .padding(.bottom, drop)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch mode {
        case .unlock:
            Button {
                attemptUnlock()
            } label: {
                Label("开门", systemImage: "door.left.hand.open")
            }
            .buttonStyle(
                NeuPillButtonStyle(
                    horizontalPadding: Theme.Spacing.xxl
                )
            )
            .opacity(canPressDoor ? 1 : 0.7)
            // 只有点这里才比对：两盘停稳不触发校验。
            // 0/0 视为非法组合，已在 canPressDoor 中禁用。
            .disabled(!canPressDoor)
            .accessibilityLabel("开门")
            .accessibilityHint("用左盘 \(left) 和右盘 \(right) 的当前读数尝试解锁")

        case .setupFirst:
            Button {
                guard !(left == 0 && right == 0) else {
                    errorText = "密码不能是 0 + 0，请先转动密码盘设置组合"
                    return
                }
                setupFirstCombo = (left, right)
                mode = .setupConfirm
                left = 0
                right = 0
                errorText = "再转一次相同组合，确认你记住了"
            } label: {
                Label("下一步", systemImage: "arrow.right")
            }
            .buttonStyle(
                NeuPillButtonStyle(
                    horizontalPadding: Theme.Spacing.xxl
                )
            )
            .disabled(left == 0 && right == 0)

        case .setupConfirm:
            Button {
                confirmSetup()
            } label: {
                Label("确认保存", systemImage: "checkmark")
            }
            .buttonStyle(
                NeuPillButtonStyle(
                    horizontalPadding: Theme.Spacing.lg
                )
            )
            .disabled(left == 0 && right == 0)
        }
    }

    /// 主按钮下方预留的「重新来过」文字按钮槽位：固定高度，所有模式都占位，
    /// 仅设置密码二次确认（setupConfirm）时填入按钮，避免主按钮位置随模式跳动。
    private var redoSlot: some View {
        VStack(spacing: 0) {
            if mode == .setupConfirm {
                Button {
                    redoSetup()
                } label: {
                    Label("重新来过", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(NeuTextButtonStyle())
            }
        }
        .frame(height: 48)
    }

    // MARK: - 状态

    private var dialsEnabled: Bool {
        !isLocked && !isVerifying
    }

    /// 开门按钮在锁定倒计时或核对中禁用；0/0 视为非法组合，不允许直接开门。
    private var canPressDoor: Bool {
        !isLocked && !isVerifying && !(left == 0 && right == 0)
    }

    private var titleText: String {
        switch mode {
        case .unlock: "私密保险箱"
        case .setupFirst: "设置保险箱密码"
        case .setupConfirm: "确认你的组合"
        }
    }

    private var subtitleText: String {
        switch mode {
        case .unlock: "转动两个密码盘，再点「开门」"
        case .setupFirst: "选择任意组合，设置后无法找回"
        case .setupConfirm: "再输入一次，确保组合无误"
        }
    }

    private var countdownText: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    // MARK: - 动作

    private func prepare() {
        if vault.isUnlocked {
            isRoomOpen = true
            return
        }
        mode = vault.isConfigured ? .unlock : .setupFirst
        refreshLockState()
    }

    private func refreshLockState() {
        let status = VaultLockPolicy.status()
        isLocked = status.isLocked()
        remainingSeconds = status.remainingSeconds()
        if !isLocked, errorText?.hasPrefix("已锁定") == true {
            errorText = nil
        }
    }

    private func attemptUnlock() {
        guard !isVerifying, !isLocked else { return }
        isVerifying = true
        let currentLeft = left
        let currentRight = right

        Task {
            let result = await vault.unlock(a: currentLeft, b: currentRight)
            isVerifying = false

            switch result {
            case .success:
                openDoor()
            case .wrong(let remaining):
                fail("密码不对，还剩 \(remaining) 次")
            case .locked(let seconds):
                refreshLockState()
                errorText = "已锁定，请等待倒计时结束"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                AccessibilityNotification.Announcement(
                    "尝试次数过多，已锁定，请在 \(seconds) 秒后重试"
                ).post()
            case .notConfigured:
                mode = .setupFirst
            }
        }
    }

    private func confirmSetup() {
        guard let first = setupFirstCombo else {
            mode = .setupFirst
            return
        }
        guard !(first.a == 0 && first.b == 0) else {
            mode = .setupFirst
            setupFirstCombo = nil
            left = 0
            right = 0
            errorText = "密码不能是 0 + 0，请重新设置"
            return
        }
        guard first.a == left, first.b == right else {
            mode = .setupFirst
            setupFirstCombo = nil
            left = 0
            right = 0
            fail("两次组合不一致，请重新设置")
            return
        }

        do {
            try vault.configure(a: first.a, b: first.b)
            pendingCombo = first
            showComboAck = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 设置密码二次确认时「重新来过」：回到首次设置，清空已输入组合。
    private func redoSetup() {
        mode = .setupFirst
        setupFirstCombo = nil
        left = 0
        right = 0
        errorText = nil
    }

    private func fail(_ message: String) {
        errorText = message
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        // 失败反馈除颜色与抖动外，必须有一条独立的语音播报。
        AccessibilityNotification.Announcement(message).post()

        withAnimation(.linear(duration: 0.06).repeatCount(3, autoreverses: true)) {
            shakeOffset = 8
        }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeOut(duration: 0.2)) {
                shakeOffset = 0
                // 失败后两盘回到 0：避免原样再按一次重复消耗失败次数。
                left = 0
                right = 0
            }
        }
    }

    private func openDoor() {
        errorText = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { isRoomOpen = true }
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            contentScale = 0.94
            contentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.24)) {
                isRoomOpen = true
                contentScale = 1
                contentOpacity = 1
            }
        }
    }
}

#Preview {
    VaultLockView()
        .environment(VaultStore())
}
