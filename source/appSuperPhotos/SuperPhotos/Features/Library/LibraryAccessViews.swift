import SwiftUI

/// 受限访问提示条：部分照片不可见时提供管理入口。
struct LimitedAccessBanner: View {
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "eye.slash")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Accent.brass)

            Text("仅能浏览你选中的照片".localized)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)

            Spacer(minLength: Theme.Spacing.sm)

            Button("管理".localized, action: onManage)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Accent.brass)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.card)
    }
}
