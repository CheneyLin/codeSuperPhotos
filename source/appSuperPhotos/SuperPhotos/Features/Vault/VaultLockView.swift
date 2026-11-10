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
            let dialDiameter = min(
                (proxy.size.width - Theme.Spacing.page * 2 - Theme.Spacing.lg) / 2,
                172
            )

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    dials(diameter: dialDiameter)
                    statusArea
                    actionArea
                    footnote
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.xxl)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Theme.Surface.raised)
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.Shadow.dark.opacity(0.8), radius: 8, x: 5, y: 5)
                    .shadow(color: Theme.Shadow.highlight, radius: 8, x: -5, y: -5)
                Image(systemName: "lock.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Theme.Accent.brass)
            }

            Text(titleText)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Text.primary)

            Text(subtitleText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func dials(diameter: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            DialView(
                label: "左盘 A · 0–\(VaultCredentials.maxDialValue)",
                count: VaultCredentials.dialCount,
                value: $left,
                isEnabled: dialsEnabled,
                diameter: diameter
            ) {
                errorText = nil
            }

            DialView(
                label: "右盘 B · 0–\(VaultCredentials.maxDialValue)",
                count: VaultCredentials.dialCount,
                value: $right,
                isEnabled: dialsEnabled,
                diameter: diameter
            ) {
                errorText = nil
            }
        }
    }

    private var statusArea: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if isLocked {
                Text("已锁定，请在 \(countdownText) 后重试")
                    .font(Theme.Typography.headline.monospacedDigit())
                    .foregroundStyle(Theme.State.danger)
            } else if isVerifying {
                Text("正在核对组合…")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.secondary)
            } else if let errorText {
                Text(errorText)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.State.danger)
                    .multilineTextAlignment(.center)
            } else {
                Text(mode == .setupConfirm ? "请再转一次相同的组合" : "转好两个盘后点「开门」")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .neuSurface(.inset, cornerRadius: Theme.Radius.card)
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
                NeuButtonStyle(
                    variant: .raised,
                    tint: canPressDoor ? Theme.Accent.brass : Theme.Text.tertiary,
                    horizontalPadding: Theme.Spacing.xxl
                )
            )
            .opacity(canPressDoor ? 1 : 0.7)
            // 只有点这里才比对：两盘停稳不触发校验。
            // 0/0 也是合法组合，所以不要求“两盘都动过”才可点。
            .disabled(!canPressDoor)
            .accessibilityLabel("开门")
            .accessibilityHint("用左盘 \(left) 和右盘 \(right) 的当前读数尝试解锁")

        case .setupFirst:
            Button {
                setupFirstCombo = (left, right)
                mode = .setupConfirm
                left = 0
                right = 0
                errorText = "再转一次相同组合，确认你记住了"
            } label: {
                Label("下一步", systemImage: "arrow.right")
            }
            .buttonStyle(
                NeuButtonStyle(
                    variant: .raised,
                    tint: Theme.Accent.brass,
                    horizontalPadding: Theme.Spacing.xxl
                )
            )

        case .setupConfirm:
            HStack(spacing: Theme.Spacing.md) {
                Button("重来") {
                    mode = .setupFirst
                    setupFirstCombo = nil
                    left = 0
                    right = 0
                    errorText = nil
                }
                .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.chip))

                Button {
                    confirmSetup()
                } label: {
                    Label("确认保存", systemImage: "checkmark")
                }
                .buttonStyle(
                    NeuButtonStyle(
                        variant: .raised,
                        tint: Theme.Accent.brass,
                        horizontalPadding: Theme.Spacing.lg
                    )
                )
            }
        }
    }

    private var footnote: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("40 × 40 = 1600 种组合。忘记密码后无法找回，请先记下再继续。")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
            Text("内容仅存于本机；卸载 App 会一并删除。")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - 状态

    private var dialsEnabled: Bool {
        !isLocked && !isVerifying
    }

    /// 开门按钮只在锁定倒计时或核对中禁用；0/0 是合法组合，不要求先动过盘。
    private var canPressDoor: Bool {
        !isLocked && !isVerifying
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
