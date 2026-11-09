import SwiftUI

/// 右侧收藏夹区：上下滚动在“我的相簿”里选择默认收藏夹，照片右滑时存入。
struct FavoriteAlbumColumn: View {
    let width: CGFloat
    let albums: [AlbumItem]
    let selectedAlbumID: String?
    /// 一次飞入动作进行中，用于给选中的相簿一个强调脉冲。
    let isReceiving: Bool
    /// 延后中的照片数量，底部入口的角标。
    let snoozedCount: Int
    let onSelect: (AlbumItem) -> Void
    let onOpenAlbums: () -> Void
    let onOpenSnoozed: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }
    private var compact: Bool { width < 88 }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("收藏夹")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Text.tertiary)

            if albums.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(albums) { album in
                            row(album)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            Button {
                onOpenSnoozed()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                    if snoozedCount > 0 {
                        Text("\(snoozedCount)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                    }
                }
                .foregroundStyle(snoozedCount > 0 ? Theme.Accent.brass : Theme.Text.tertiary)
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snoozedCount > 0 ? "延后中 \(snoozedCount) 张" : "延后管理")

            Button {
                onOpenAlbums()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Text.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看全部相簿")
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.Text.tertiary)
            Text("没有相簿")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func row(_ album: AlbumItem) -> some View {
        let isSelected = album.id == selectedAlbumID

        return Button {
            onSelect(album)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Accent.brass : Theme.Text.secondary)

                Text(album.title)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text("\(album.count)")
                    .font(.system(size: 9, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.Text.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: compact ? 54 : 62)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.Accent.brass.opacity(0.16) : Theme.Surface.raised.opacity(0.6))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Accent.brass.opacity(0.85) : Theme.Shadow.raisedBorder.opacity(0.4),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isSelected && isReceiving ? 1.06 : 1)
            .shadow(
                color: isSelected && isReceiving ? Theme.Accent.brass.opacity(0.5) : .clear,
                radius: 8
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.7),
            value: isReceiving
        )
        .accessibilityLabel("\(album.title)，\(album.count) 张")
        .accessibilityHint(isSelected ? "当前默认收藏夹" : "点按设为默认收藏夹")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    FavoriteAlbumColumn(
        width: 78,
        albums: [
            AlbumItem(id: "1", title: "旅行", kind: .user, count: 32, symbolName: "folder"),
            AlbumItem(id: "2", title: "家人", kind: .user, count: 108, symbolName: "folder"),
            AlbumItem(id: "3", title: "截图整理", kind: .user, count: 12, symbolName: "folder")
        ],
        selectedAlbumID: "1",
        isReceiving: false,
        snoozedCount: 2,
        onSelect: { _ in },
        onOpenAlbums: {},
        onOpenSnoozed: {}
    )
    .frame(height: 360)
    .padding()
    .background(Theme.Surface.base)
}
