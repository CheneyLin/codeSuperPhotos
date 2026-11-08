import SwiftUI

/// 顶部筛选条：类型 chip + 相簿 chip。
struct FilterBar: View {
    let selectedKind: MediaKind?
    let albumTitle: String
    let showsAlbumButton: Bool
    let onSelectKind: (MediaKind?) -> Void
    let onOpenAlbums: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Menu {
                Button("全部类型") { onSelectKind(nil) }
                ForEach(MediaKind.allCases) { kind in
                    Button(kind.displayName) { onSelectKind(kind) }
                }
            } label: {
                chip(
                    title: selectedKind?.displayName ?? "全部类型",
                    icon: "line.3.horizontal.decrease",
                    highlighted: selectedKind != nil
                )
            }

            if showsAlbumButton {
                Button {
                    onOpenAlbums()
                } label: {
                    chip(
                        title: albumTitle,
                        icon: "rectangle.stack",
                        chevron: true
                    )
                }
                .accessibilityLabel("相簿：\(albumTitle)")
            } else {
                chip(title: albumTitle, icon: "rectangle.stack")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func chip(
        title: String,
        icon: String,
        chevron: Bool = false,
        highlighted: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(Theme.Typography.caption.weight(.semibold))
                .lineLimit(1)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(highlighted ? Theme.Accent.fire : Theme.Text.primary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 32)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 0) {
        FilterBar(
            selectedKind: nil,
            albumTitle: "全部照片",
            showsAlbumButton: true,
            onSelectKind: { _ in },
            onOpenAlbums: {}
        )
        FilterBar(
            selectedKind: .livePhoto,
            albumTitle: "相机胶卷",
            showsAlbumButton: false,
            onSelectKind: { _ in },
            onOpenAlbums: {}
        )
    }
    .background(Theme.Surface.base)
}
