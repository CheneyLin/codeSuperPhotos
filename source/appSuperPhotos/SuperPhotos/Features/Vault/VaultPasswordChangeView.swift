import SwiftUI

/// 设置页的修改密码流程：旧密码 → 新组合 → 再次输入新组合。
struct VaultPasswordChangeView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int {
        case verifyOld
        case newCombo
        case confirmNew
        case done
    }

    @State private var step: Step = .verifyOld
    @State private var left = 0
    @State private var right = 0
    @State private var newCombo: (a: Int, b: Int)?
    @State private var errorText: String?
    @State private var lockedSeconds = 0

    var body: some View {
        GeometryReader { proxy in
            let small = min((proxy.size.width - Theme.Spacing.page * 2) / 2.4, 140)
            let large = small * 1.5

            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    header
                    dials(small: small, large: large)
                    status
                    action
                }
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.lg)
            }
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .navigationTitle("修改密码".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            lockedSeconds = VaultLockPolicy.remainingSeconds()
        }
        .task {
            while !Task.isCancelled {
                lockedSeconds = VaultLockPolicy.remainingSeconds()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: step == .done ? "checkmark.seal.fill" : "key.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(step == .done ? Theme.State.success : Theme.Accent.brass)

            Text(titleText)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Text.primary)

            Text(subtitleText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// 错落双盘：左盘（小）居左上、右盘（大，150%）居右下，水平交叠形成错落。
    private func dials(small: CGFloat, large: CGFloat) -> some View {
        let overlap = small * 0.30
        let drop = (large - small) * 0.6

        return HStack(alignment: .top, spacing: -overlap) {
            DialView(
                label: "左盘 A · 0–%@".localized(VaultCredentials.leftMaxDialValue),
                count: VaultCredentials.leftDialCount,
                value: $left,
                isEnabled: step != .done && lockedSeconds == 0,
                diameter: small
            ) {
                errorText = nil
            }

            DialView(
                label: "右盘 B · 0–%@".localized(VaultCredentials.rightMaxDialValue),
                count: VaultCredentials.rightDialCount,
                value: $right,
                isEnabled: step != .done && lockedSeconds == 0,
                diameter: large
            ) {
                errorText = nil
            }
            .offset(y: drop)
        }
        .padding(.bottom, drop)
    }

    @ViewBuilder
    private var status: some View {
        if step == .done {
            Text("新密码为：左盘 %@ / 右盘 %@。请立即记下。".localized(newCombo?.a ?? 0, newCombo?.b ?? 0))
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(Theme.Text.primary)
                .multilineTextAlignment(.center)
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
                .neuSurface(.inset, cornerRadius: Theme.Radius.card)
        } else if lockedSeconds > 0 {
            Text("已锁定，请在 %@ 后重试".localized(lockedText))
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(Theme.State.danger)
        } else if let errorText {
            Text(errorText)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.State.danger)
                .multilineTextAlignment(.center)
        } else {
            Text("组合空间 30 × 60 = 1800 种。忘记后无法找回。".localized)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch step {
        case .verifyOld:
            Button {
                verifyOld()
            } label: {
                Label("验证旧密码".localized, systemImage: "lock.open")
            }
            .buttonStyle(NeuPillButtonStyle())
            .disabled(lockedSeconds > 0)

        case .newCombo:
            Button {
                newCombo = (left, right)
                step = .confirmNew
                left = 0
                right = 0
                errorText = nil
            } label: {
                Label("下一步".localized, systemImage: "arrow.right")
            }
            .buttonStyle(NeuPillButtonStyle())

        case .confirmNew:
            HStack(spacing: Theme.Spacing.md) {
                Button("重来".localized) {
                    step = .newCombo
                    newCombo = nil
                    left = 0
                    right = 0
                    errorText = nil
                }
                .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.chip))

                Button {
                    confirmNew()
                } label: {
                    Label("保存新密码".localized, systemImage: "checkmark")
                }
                .buttonStyle(NeuPillButtonStyle())
            }

        case .done:
            Button("完成".localized) { dismiss() }
                .buttonStyle(NeuPillButtonStyle())
        }
    }

    // MARK: - 文案

    private var titleText: String {
        switch step {
        case .verifyOld: "验证旧密码".localized
        case .newCombo, .confirmNew: "设置新密码".localized
        case .done: "密码已更新".localized
        }
    }

    private var subtitleText: String {
        switch step {
        case .verifyOld: "先输入当前两个密码盘的位置".localized
        case .newCombo: "选择新的组合".localized
        case .confirmNew: "再输入一次新组合".localized
        case .done: "旧组合已失效".localized
        }
    }

    private var lockedText: String {
        String(format: "%02d:%02d", lockedSeconds / 60, lockedSeconds % 60)
    }

    // MARK: - 动作

    private func verifyOld() {
        switch vault.verifyPassword(a: left, b: right) {
        case .success:
            step = .newCombo
            left = 0
            right = 0
            errorText = nil
        case .wrong(let remaining):
            errorText = "密码不对，还剩 %@ 次".localized(remaining)
            left = 0
            right = 0
        case .locked(let seconds):
            lockedSeconds = seconds
            errorText = nil
            left = 0
            right = 0
        }
    }

    private func confirmNew() {
        guard let newCombo else {
            step = .newCombo
            return
        }
        guard newCombo.a == left, newCombo.b == right else {
            errorText = "两次组合不一致，请重新设置".localized
            step = .newCombo
            self.newCombo = nil
            left = 0
            right = 0
            return
        }
        guard vault.verifyOnly(a: newCombo.a, b: newCombo.b) == false else {
            errorText = "新组合不能与旧密码相同".localized
            step = .newCombo
            self.newCombo = nil
            left = 0
            right = 0
            return
        }

        do {
            try vault.configure(a: newCombo.a, b: newCombo.b)
            step = .done
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        VaultPasswordChangeView()
            .environment(VaultStore())
    }
}
