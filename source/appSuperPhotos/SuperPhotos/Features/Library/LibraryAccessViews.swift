import SwiftUI

/// 首次启动的权限预热页。
struct PermissionIntroView: View {
    let isRequesting: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(Theme.Text.secondary)
                .frame(width: 96, height: 96)
                .neuSurface(.inset, cornerRadius: Theme.Radius.stage)

            VStack(spacing: Theme.Spacing.sm) {
                Text("SuperPhotos 需要读取相簿".localized)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)
                Text("只在本机浏览与整理照片，不上传、不联网。".localized)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                onRequest()
            } label: {
                if isRequesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("允许访问相簿".localized)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.neuPill)
            .disabled(isRequesting)
        }
        .padding(Theme.Spacing.page)
    }
}

/// 权限被拒绝后的围栏页。
struct PermissionDeniedView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "lock.slash")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Text.secondary)
                .frame(width: 96, height: 96)
                .neuSurface(.inset, cornerRadius: Theme.Radius.stage)

            VStack(spacing: Theme.Spacing.sm) {
                Text("没有访问相簿的权限".localized)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)
                Text("请在系统设置中允许 SuperPhotos 访问照片，之后回到这里即可继续。".localized)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                onOpenSettings()
            } label: {
                Text("去系统设置".localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.neuPill)
        }
        .padding(Theme.Spacing.page)
    }
}

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

#Preview("权限页") {
    VStack(spacing: 0) {
        PermissionIntroView(isRequesting: false) {}
        Divider()
        PermissionDeniedView {}
    }
    .background(Theme.Surface.base)
}
