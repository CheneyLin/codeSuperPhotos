import SwiftUI
import UIKit

/// 保险箱房间：解锁后的内容区。
struct VaultRoomView: View {
    @Environment(VaultStore.self) private var vault
    @Environment(StatisticsService.self) private var statistics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var selectedIDs: Set<UUID> = []
    @State private var fullscreenRequest: VaultFullscreenRequest?
    @State private var exportRequest: VaultExportRequest?
    @State private var exportTemporaryDirectories: [URL] = []
    @State private var isDeleteConfirmPresented = false
    @State private var toastMessage: ToastMessage?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 0),
        count: Theme.VaultGrid.columnCount
    )

    var body: some View {
        VStack(spacing: 0) {
            header

            if pendingRemovalCount > 0 {
                pendingBanner
            }

            if vault.records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(vault.records) { record in
                            gridItem(record)
                        }
                    }
                    .overlay {
                        VaultGridSeparators(itemCount: vault.records.count)
                    }
                }
            }

            if !selectedIDs.isEmpty {
                selectionToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .fullScreenCover(item: $fullscreenRequest) { request in
            VaultFullscreenView(
                records: vault.records,
                startID: request.id,
                onClose: { fullscreenRequest = nil }
            )
        }
        .sheet(item: $exportRequest, onDismiss: {
            cleanupExportTemporaries()
        }) { request in
            ShareSheet(items: request.urls)
        }
        .alert("永久删除保险箱副本？".localized, isPresented: $isDeleteConfirmPresented) {
            Button("取消".localized, role: .cancel) {}
            Button("永久删除".localized, role: .destructive) {
                vault.permanentDelete(ids: Array(selectedIDs))
                selectedIDs.removeAll()
                toastMessage = ToastMessage(
                    text: "已永久删除保险箱副本，系统『最近删除』不受影响".localized,
                    kind: .warning
                )
            }
        } message: {
            Text("只删除 App 内的副本与清单，不触碰系统相簿。原件已在入库时移入系统『最近删除』。".localized)
        }
        .toast($toastMessage, topPadding: 72)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("私密保险箱".localized)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)
                Text("%@ 件 · %@".localized(vault.records.count, VaultLimits.readableBytes(vault.totalBytes)))
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)
            }

            Spacer()

            if !vault.records.isEmpty {
                Button(selectedIDs.isEmpty ? "全选".localized : "取消选择".localized) {
                    withAnimation(Theme.Motion.animation(.fast, reduceMotion: reduceMotion)) {
                        if selectedIDs.isEmpty {
                            selectedIDs = Set(vault.records.map(\.id))
                        } else {
                            selectedIDs.removeAll()
                        }
                    }
                }
                .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.chip))
            }

            Button {
                vault.lock()
                dismiss()
            } label: {
                Image(systemName: "lock.fill")
            }
            .buttonStyle(.neuIcon)
            .accessibilityLabel("锁上并退出".localized)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Surface.base)
    }

    // MARK: - 内容

    private var pendingRemovalCount: Int {
        vault.records.filter(\.pendingRemoval).count
    }

    private var pendingBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.State.danger)

            Text("有 %@ 件原件仍在系统相簿".localized(pendingRemovalCount))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.primary)

            Spacer()

            Button("重试移出".localized) {
                Task {
                    let count = await vault.retryPendingRemoval()
                    if count > 0 {
                        toastMessage = ToastMessage(text: "已移出 %@ 件原件".localized(count), kind: .success)
                    } else {
                        toastMessage = ToastMessage(text: "仍未移出，请稍后再试".localized, kind: .warning)
                    }
                }
            }
            .buttonStyle(NeuTextButtonStyle(font: Theme.Typography.caption.weight(.semibold)))
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Surface.sunken)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "shippingbox")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.Text.tertiary)
            Text("保险箱还是空的".localized)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)
            Text("在首页把照片存入保险箱，原件会从系统相簿移入『最近删除』。".localized)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gridItem(_ record: VaultRecord) -> some View {
        let isSelected = selectedIDs.contains(record.id)

        return Button {
            if selectedIDs.isEmpty {
                fullscreenRequest = VaultFullscreenRequest(id: record.id)
            } else {
                toggleSelection(record.id)
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VaultThumbnailView(record: record)
                }
                .clipped()
                .overlay {
                    if isSelected {
                        Rectangle()
                            .strokeBorder(Theme.Accent.brass, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                restore(ids: [record.id])
            } label: {
                Label("取出到相册".localized, systemImage: "arrow.up.forward.app")
            }
            Button {
                export(ids: [record.id])
            } label: {
                Label("导出".localized, systemImage: "square.and.arrow.up")
            }
            Button {
                selectedIDs.insert(record.id)
            } label: {
                Label("选择".localized, systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                selectedIDs = [record.id]
                isDeleteConfirmPresented = true
            } label: {
                Label("永久删除副本".localized, systemImage: "trash")
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("已选 %@ 件".localized(selectedIDs.count))
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(Theme.Text.primary)

            Spacer()

            Button {
                restore(ids: selectedIDs)
            } label: {
                Label("取出".localized, systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(
                NeuPillButtonStyle(
                    horizontalPadding: Theme.Spacing.md
                )
            )

            Button {
                export(ids: Array(selectedIDs))
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.neuIcon)
            .accessibilityLabel("导出".localized)

            Button {
                isDeleteConfirmPresented = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(NeuIconButtonStyle(tint: Theme.State.danger))
            .accessibilityLabel("永久删除".localized)
        }
        .padding(Theme.Spacing.md)
        .neuSurface(.raised, cornerRadius: Theme.Radius.dock)
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - 动作

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func restore(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        Task {
            let summary = await vault.restore(ids: Array(ids))
            selectedIDs.removeAll()
            if summary.restored > 0 {
                statistics.recordRestore(count: summary.restored)
            }

            if summary.failed == 0 {
                toastMessage = ToastMessage(
                    text: "已取出 %@ 件并放回相册".localized(summary.restored),
                    kind: .success
                )
            } else {
                toastMessage = ToastMessage(
                    text: "取出 %@ 件，失败 %@ 件（副本已保留）".localized(summary.restored, summary.failed),
                    kind: .warning
                )
            }
        }
    }

    private func export(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        Task {
            let result = await vault.exportURLs(ids: ids)
            guard !result.urls.isEmpty else {
                toastMessage = ToastMessage(text: "没有可导出的文件".localized, kind: .warning)
                return
            }
            exportRequest = VaultExportRequest(
                urls: result.urls,
                temporaryDirectories: result.temporaryDirectories
            )
            exportTemporaryDirectories = result.temporaryDirectories
        }
    }

    private func cleanupExportTemporaries() {
        for directory in exportTemporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        exportTemporaryDirectories.removeAll()
        exportRequest = nil
    }
}

// MARK: - 缩略图

struct VaultThumbnailView: View {
    let record: VaultRecord
    @Environment(VaultStore.self) private var vault
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.Surface.sunken

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: record.id) {
            image = nil
            let columnWidth = UIScreen.main.bounds.width / CGFloat(Theme.VaultGrid.columnCount)
            let maxPixel = max(320, columnWidth * UIScreen.main.scale)
            image = await vault.thumbnailAsync(for: record, maxPixel: maxPixel)
        }
    }
}

// MARK: - 分隔线

/// 只画内部网格线：贴合单元格边界，不占布局空间、不产生间隙。
private struct VaultGridSeparators: View {
    let itemCount: Int

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width / CGFloat(Theme.VaultGrid.columnCount)
            let rows = max(1, Int(ceil(Double(itemCount) / Double(Theme.VaultGrid.columnCount))))
            let columns = Theme.VaultGrid.columnCount

            Canvas { context, _ in
                var path = Path()
                if columns > 1 {
                    for column in 1..<columns {
                        let x = side * CGFloat(column)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: side * CGFloat(rows)))
                    }
                }
                if rows > 1 {
                    for row in 1..<rows {
                        let y = side * CGFloat(row)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                context.stroke(
                    path,
                    with: .color(Theme.VaultGrid.separator),
                    lineWidth: Theme.VaultGrid.lineWidth
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 分享

struct VaultExportRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
    /// 导出旧版加密文件时产生的解密临时目录，分享结束后删除。
    let temporaryDirectories: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
