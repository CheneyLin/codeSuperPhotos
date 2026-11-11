import SwiftUI

/// 保险箱预览抽屉：上锁态展示容量、解锁入口、存入当前照片。
/// Compact 下作为覆盖抽屉，Regular 下作为固定左列。
struct VaultPreviewDrawer: View {
    @Environment(VaultStore.self) private var vault

    let isVIP: Bool
    let currentItem: PhotoItem?
    let thumbnails: ThumbnailProvider
    let showsCloseButton: Bool
    let onUnlock: () -> Void
    let onStoreCurrent: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Text("私密保险箱")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)

                Spacer()

                if showsCloseButton {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.neuIcon)
                    .accessibilityLabel("关闭保险箱预览")
                }
            }

            doorGraphic

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("已存 \(vault.records.count) 件")
                    .font(Theme.Typography.headline.monospacedDigit())
                    .foregroundStyle(Theme.Text.primary)

                Text("占用 \(VaultLimits.readableBytes(vault.totalBytes))")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)

                if isVIP {
                    Text("VIP：不限容量，支持实况照片与视频")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Accent.fire)
                } else {
                    Text("免费版：最多 60 件 / 2GB，仅静态图片")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                }

                let pending = vault.records.filter(\.pendingRemoval).count
                if pending > 0 {
                    Text("有 \(pending) 件原件仍在系统相簿，可在房间内重试移出")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.State.danger)
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    onUnlock()
                } label: {
                    Label(vault.isConfigured ? "解锁并查看" : "设置密码", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeuPillButtonStyle())

                Button {
                    onStoreCurrent()
                } label: {
                    Label("存入当前照片", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.card))
                .disabled(currentItem == nil)
                .opacity(currentItem == nil ? 0.5 : 1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("入库 = 复制到 App 保险箱 + 移出系统相簿")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
                Text("原件会进入系统『最近删除』，保留 30 天。密码忘记后无法找回。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.Surface.base)
    }

    private var doorGraphic: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Surface.sunken)
                .frame(height: 132)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Shadow.insetBorder, lineWidth: 1)
                }

            ZStack {
                Circle()
                    .fill(Theme.Surface.raised)
                    .frame(width: 68, height: 68)
                    .shadow(color: Theme.Shadow.dark.opacity(0.85), radius: 6, x: 4, y: 4)
                    .shadow(color: Theme.Shadow.highlight, radius: 6, x: -4, y: -4)

                Circle()
                    .strokeBorder(Theme.Accent.brass.opacity(0.7), lineWidth: 2)
                    .frame(width: 52, height: 52)

                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Accent.brass)

                HStack(spacing: 58) {
                    Circle()
                        .fill(Theme.Accent.brass.opacity(0.55))
                        .frame(width: 7, height: 7)
                    Circle()
                        .fill(Theme.Accent.brass.opacity(0.55))
                        .frame(width: 7, height: 7)
                }
                .offset(y: -34)
            }
        }
    }
}

#Preview {
    VaultPreviewDrawer(
        isVIP: false,
        currentItem: nil,
        thumbnails: ThumbnailProvider(),
        showsCloseButton: true,
        onUnlock: {},
        onStoreCurrent: {},
        onClose: {}
    )
    .frame(width: 300)
    .environment(VaultStore())
}
