import SwiftUI

/// 重置保险箱：输入「重置」两个动作，文案如实说明不可恢复。
struct VaultResetView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var didReset = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if didReset {
                    Label("保险箱已重置".localized, systemImage: "checkmark.seal.fill")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.State.success)
                } else {
                    Text("此操作不可恢复".localized)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.State.danger)

                    Text("将清空 App 内的所有保险箱副本、密码与锁定计数。\n原件已在入库时进入系统『最近删除』，本操作不会影响它们；如需找回原件，请到照片 App 检查『最近删除』。".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("输入「重置」以确认：".localized)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)

                    TextField("重置".localized, text: $input)
                        .textFieldStyle(.plain)
                        .padding(Theme.Spacing.md)
                        .neuSurface(.inset, cornerRadius: Theme.Radius.card)

                    Button(role: .destructive) {
                        vault.resetAll()
                        didReset = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Text("永久清空保险箱".localized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeuButtonStyle(variant: .raised, tint: Theme.State.danger))
                    .disabled(input != "重置".localized)
                    .opacity(input == "重置".localized ? 1 : 0.45)
                }

                Spacer()
            }
            .padding(Theme.Spacing.page)
            .background(Theme.Surface.base.ignoresSafeArea())
            .navigationTitle("重置保险箱".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(didReset ? "完成".localized : "取消".localized) { dismiss() }
                }
            }
        }
    }
}

#Preview {
    VaultResetView()
        .environment(VaultStore())
}
