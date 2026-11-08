import SwiftUI

/// 切后台/多任务快照的隐私遮罩：不显示任何相册或保险箱内容。
struct VaultPrivacyShield: View {
    var body: some View {
        ZStack {
            Theme.Surface.base.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.Accent.brass)
                Text("SuperPhotos")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Text.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VaultPrivacyShield()
}
