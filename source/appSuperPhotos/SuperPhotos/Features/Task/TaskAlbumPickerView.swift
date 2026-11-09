import SwiftUI

/// 开始任务前选择相簿：全部照片 + 我的所有相簿。
struct TaskAlbumPickerView: View {
    let allPhotoCount: Int
    let albums: [AlbumItem]
    let onSelect: (AlbumItem?) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    row(
                        title: "全部照片",
                        count: allPhotoCount,
                        symbolName: "photo.on.rectangle.angled",
                        tint: Theme.Accent.brass
                    ) {
                        onSelect(nil)
                    }

                    if albums.isEmpty {
                        Text("还没有可整理的自建相簿")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Text.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xl)
                    } else {
                        ForEach(albums) { album in
                            row(
                                title: album.title,
                                count: album.count,
                                symbolName: album.symbolName,
                                tint: Theme.Text.secondary
                            ) {
                                onSelect(album)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.Surface.base)
            .navigationTitle("选择相簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消", action: onClose)
                        .foregroundStyle(Theme.Text.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(
        title: String,
        count: Int,
        symbolName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Text.primary)
                        .lineLimit(1)

                    Text("\(count.formatted()) 张")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Text.tertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 58)
            .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 张")
    }
}

#Preview {
    TaskAlbumPickerView(
        allPhotoCount: 20318,
        albums: [
            AlbumItem(id: "1", title: "旅行", kind: .user, count: 128, symbolName: "folder"),
            AlbumItem(id: "2", title: "家人", kind: .user, count: 64, symbolName: "folder")
        ],
        onSelect: { _ in },
        onClose: {}
    )
    .background(Theme.Surface.base)
}
