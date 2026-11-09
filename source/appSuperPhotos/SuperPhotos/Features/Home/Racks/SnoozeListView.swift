import SwiftUI

/// 延后管理：查看延后中的照片与剩余天数，可单张恢复或全部恢复。
/// 入口在右侧收藏夹列底部。
struct SnoozeListView: View {
    let records: [SnoozeRecord]
    let thumbnails: ThumbnailProvider
    let onWake: (String) -> Void
    let onWakeAll: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            header

            if records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(records) { record in
                            row(record)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            if records.count > 1 {
                Button {
                    onWakeAll()
                } label: {
                    Text("全部恢复（\(records.count) 张）")
                }
                .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.chip))
            }
        }
        .padding(Theme.Spacing.page)
        .background(Theme.Surface.base)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("延后中")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Text.primary)
                Text("到期前不会出现在舞台，随时可以恢复")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Text.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Text.tertiary)
            Text("没有延后中的照片")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Text.secondary)
            Text("舞台上滑即可延后 1–30 天")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ record: SnoozeRecord) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            SnoozeThumbnail(id: record.id, thumbnails: thumbnails)

            VStack(alignment: .leading, spacing: 3) {
                Text(untilText(record.until))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.primary)
                    .lineLimit(1)

                Text("还有 \(remainingDays(record)) 天")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                onWake(record.id)
            } label: {
                Text("恢复")
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Accent.brass)
                    .padding(.horizontal, Theme.Spacing.md)
                    .frame(minHeight: 30)
                    .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("恢复这张照片")
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Surface.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func remainingDays(_ record: SnoozeRecord) -> Int {
        max(1, Int(ceil(record.until.timeIntervalSinceNow / 86_400)))
    }

    private func untilText(_ date: Date) -> String {
        Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm 回到舞台"
        return formatter
    }()
}

/// 延后项的缩略图：只按 assetID 取图，不依赖当前筛选范围。
private struct SnoozeThumbnail: View {
    let id: String
    let thumbnails: ThumbnailProvider

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.Surface.sunken)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .task(id: id) {
            image = await thumbnails.image(
                for: id,
                targetSize: CGSize(width: 48 * UIScreen.main.scale, height: 48 * UIScreen.main.scale)
            )
        }
    }
}

#Preview {
    SnoozeListView(
        records: [
            SnoozeRecord(id: "a", until: Date().addingTimeInterval(86_400 * 3)),
            SnoozeRecord(id: "b", until: Date().addingTimeInterval(86_400 * 12))
        ],
        thumbnails: ThumbnailProvider(),
        onWake: { _ in },
        onWakeAll: {},
        onClose: {}
    )
}
