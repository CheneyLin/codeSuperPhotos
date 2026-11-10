import SwiftUI

/// 任务取图范围。
enum AlbumPickerSelection {
    case all
    case uncategorized
    case album(AlbumItem)
}

/// 开始任务前选择相簿：全部照片 + 未归类照片 + 我的所有相簿。
struct TaskAlbumPickerView: View {
    let allPhotoCount: Int
    /// nil 表示首次差集还没算完，行内显示「计算中…」。
    let uncategorizedCount: Int?
    let albums: [AlbumItem]
    let onSelect: (AlbumPickerSelection) -> Void
    let onClose: () -> Void

    @AppStorage(TaskPolicy.batchSizeKey) private var batchSize = TaskPolicy.batchSize

    private var batchLimit: Int { TaskPolicy.clampedBatchSize(batchSize) }

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
                        onSelect(.all)
                    }

                    row(
                        title: "未归类照片",
                        count: uncategorizedCount,
                        symbolName: "folder.badge.questionmark",
                        tint: Theme.Text.secondary
                    ) {
                        onSelect(.uncategorized)
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
                                onSelect(.album(album))
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.page)

                Text("每批最多取 \(batchLimit) 张（设置里可改）。相簿张数不足时按实际张数开始。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.bottom, Theme.Spacing.page)
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
        count: Int?,
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

                    Text(count.map { "\($0.formatted()) 张" } ?? "计算中…")
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
        .accessibilityLabel(count.map { "\(title)，\($0) 张" } ?? "\(title)，正在计算")
    }
}

#Preview {
    TaskAlbumPickerView(
        allPhotoCount: 20318,
        uncategorizedCount: 4210,
        albums: [
            AlbumItem(id: "1", title: "旅行", kind: .user, count: 128, symbolName: "folder"),
            AlbumItem(id: "2", title: "家人", kind: .user, count: 64, symbolName: "folder")
        ],
        onSelect: { _ in },
        onClose: {}
    )
    .background(Theme.Surface.base)
}
