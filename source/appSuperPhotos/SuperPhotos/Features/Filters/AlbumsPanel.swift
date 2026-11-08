import SwiftUI

/// 相簿面板：Compact 下作为右侧抽屉，Regular 下作为常驻右列。
struct AlbumsPanel: View {
    let albums: AlbumService
    let selectedAlbumID: String?
    let showsCloseButton: Bool
    let onSelect: (AlbumItem?) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    allPhotosRow

                    if !albums.smartAlbums.isEmpty {
                        section("智能相簿", items: albums.smartAlbums)
                    }

                    if !albums.userAlbums.isEmpty {
                        section("我的相簿", items: albums.userAlbums)
                    }

                    if albums.isLoading && albums.smartAlbums.isEmpty && albums.userAlbums.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.Surface.base)
    }

    private var header: some View {
        HStack {
            Text("相簿")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Text.primary)

            Spacer()

            if showsCloseButton {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(NeuIconButtonStyle(diameter: 36))
                .accessibilityLabel("关闭相簿")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var allPhotosRow: some View {
        row(
            AlbumItem(id: "all", title: "全部照片", kind: .all, count: albums.allPhotoCount, symbolName: "photo.on.rectangle"),
            isSelected: selectedAlbumID == nil
        )
    }

    private func section(_ title: String, items: [AlbumItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Text.tertiary)
                .padding(.horizontal, Theme.Spacing.md)

            ForEach(items) { item in
                row(item, isSelected: selectedAlbumID == item.id)
            }
        }
    }

    private func row(_ item: AlbumItem, isSelected: Bool) -> some View {
        Button {
            onSelect(item.kind == .all ? nil : item)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Accent.brass : Theme.Text.secondary)
                    .frame(width: 22)

                Text(item.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.primary)
                    .lineLimit(1)

                Spacer(minLength: Theme.Spacing.sm)

                // 智能相簿的集合计数包含系统隐藏资产，与舞台口径不一致，故只在“全部照片”和“我的相簿”展示数量。
                if item.kind != .smart {
                    Text("\(item.count)")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Metrics.minTouchTarget)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Accent.brass.opacity(0.12))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AlbumsPanel(
        albums: AlbumService(),
        selectedAlbumID: nil,
        showsCloseButton: true,
        onSelect: { _ in },
        onClose: {}
    )
    .frame(width: 320)
    .background(Theme.Surface.base)
}
