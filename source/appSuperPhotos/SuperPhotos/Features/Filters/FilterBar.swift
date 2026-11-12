import SwiftUI

/// 顶部筛选条：只保留相簿维度，chip 同时显示相簿名与当前张数。
struct FilterBar: View {
    let albumTitle: String
    let photoCount: Int
    let onOpenAlbums: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                onOpenAlbums()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 11, weight: .semibold))

                    Text(albumTitle)
                        .font(Theme.Typography.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("%@ 张".localized(photoCount.formatted()))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(minHeight: 20)
                        .background(Theme.Surface.sunken, in: Capsule())

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.Text.primary)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: 34)
                .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("相簿：%@，%@ 张照片".localized(albumTitle, photoCount))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

#Preview {
    VStack(spacing: 0) {
        FilterBar(
            albumTitle: "全部照片",
            photoCount: 20318,
            onOpenAlbums: {}
        )
        FilterBar(
            albumTitle: "相机胶卷",
            photoCount: 128,
            onOpenAlbums: {}
        )
    }
    .background(Theme.Surface.base)
}
