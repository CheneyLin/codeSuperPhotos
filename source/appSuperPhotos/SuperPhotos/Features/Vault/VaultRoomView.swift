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
    @State private var detailRecord: VaultRecord?
    @State private var exportRequest: VaultExportRequest?
    @State private var isDeleteConfirmPresented = false
    @State private var toastMessage: ToastMessage?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Theme.Spacing.md)]

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
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(vault.records) { record in
                            gridItem(record)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.vertical, Theme.Spacing.md)
                }
            }

            if !selectedIDs.isEmpty {
                selectionToolbar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .sheet(item: $detailRecord) { record in
            VaultItemDetail(
                record: record,
                onRestore: {
                    detailRecord = nil
                    restore(ids: [record.id])
                },
                onDelete: {
                    detailRecord = nil
                    vault.permanentDelete(ids: [record.id])
                    toastMessage = ToastMessage(text: "已永久删除保险箱副本", kind: .warning)
                }
            )
            .environment(vault)
        }
        .sheet(item: $exportRequest) { request in
            ShareSheet(items: request.urls)
        }
        .alert("永久删除保险箱副本？", isPresented: $isDeleteConfirmPresented) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) {
                vault.permanentDelete(ids: Array(selectedIDs))
                selectedIDs.removeAll()
                toastMessage = ToastMessage(
                    text: "已永久删除保险箱副本，系统『最近删除』不受影响",
                    kind: .warning
                )
            }
        } message: {
            Text("只删除 App 内的副本与清单，不触碰系统相簿。原件已在入库时移入系统『最近删除』。")
        }
        .toast($toastMessage, topPadding: 72)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("私密保险箱")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)
                Text("\(vault.records.count) 件 · \(VaultLimits.readableBytes(vault.totalBytes))")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)
            }

            Spacer()

            if !vault.records.isEmpty {
                Button(selectedIDs.isEmpty ? "全选" : "取消选择") {
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
            .accessibilityLabel("锁上并退出")
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

            Text("有 \(pendingRemovalCount) 件原件仍在系统相簿")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.primary)

            Spacer()

            Button("重试移出") {
                Task {
                    let count = await vault.retryPendingRemoval()
                    if count > 0 {
                        toastMessage = ToastMessage(text: "已移出 \(count) 件原件", kind: .success)
                    } else {
                        toastMessage = ToastMessage(text: "仍未移出，请稍后再试", kind: .warning)
                    }
                }
            }
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(Theme.Accent.brass)
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
            Text("保险箱还是空的")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)
            Text("在首页把照片存入保险箱，原件会从系统相簿移入『最近删除』。")
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
            toggleSelection(record.id)
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                VaultThumbnailView(record: record)
                    .frame(height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(
                                isSelected ? Theme.Accent.brass : Theme.Shadow.insetBorder.opacity(0.4),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.Accent.brass)
                                .padding(6)
                        }
                    }

                Text(record.displayDateText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.35) {
            detailRecord = record
        }
        .contextMenu {
            Button {
                restore(ids: [record.id])
            } label: {
                Label("取出到相册", systemImage: "arrow.up.forward.app")
            }
            Button {
                exportRequest = VaultExportRequest(urls: vault.exportURLs(ids: [record.id]))
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                selectedIDs = [record.id]
                isDeleteConfirmPresented = true
            } label: {
                Label("永久删除副本", systemImage: "trash")
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("已选 \(selectedIDs.count) 件")
                .font(Theme.Typography.headline.monospacedDigit())
                .foregroundStyle(Theme.Text.primary)

            Spacer()

            Button {
                restore(ids: selectedIDs)
            } label: {
                Label("取出", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(
                NeuButtonStyle(
                    variant: .raised,
                    tint: Theme.Accent.brass,
                    horizontalPadding: Theme.Spacing.md,
                    verticalPadding: Theme.Spacing.sm
                )
            )

            Button {
                exportRequest = VaultExportRequest(urls: vault.exportURLs(ids: Array(selectedIDs)))
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.neuIcon)
            .accessibilityLabel("导出")

            Button {
                isDeleteConfirmPresented = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(NeuIconButtonStyle(tint: Theme.State.danger))
            .accessibilityLabel("永久删除")
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
                    text: "已取出 \(summary.restored) 件并放回相册",
                    kind: .success
                )
            } else {
                toastMessage = ToastMessage(
                    text: "取出 \(summary.restored) 件，失败 \(summary.failed) 件（副本已保留）",
                    kind: .warning
                )
            }
        }
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
            } else {
                Image(systemName: record.mediaKind == .video ? "play.rectangle" : "photo")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.Text.tertiary)
            }
        }
        .clipped()
        .task(id: record.id) {
            image = vault.thumbnail(for: record)
        }
    }
}

// MARK: - 详情

struct VaultItemDetail: View {
    let record: VaultRecord
    let onRestore: () -> Void
    let onDelete: () -> Void

    @Environment(VaultStore.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isDeleteConfirmPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.stage, style: .continuous)
                            .fill(Theme.Surface.sunken)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(Theme.Spacing.sm)
                        } else {
                            Image(systemName: record.mediaKind == .video ? "play.rectangle" : "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.Text.tertiary)
                        }
                    }
                    .frame(maxHeight: 420)

                    VStack(spacing: 0) {
                        infoRow("类型", record.mediaKind.displayName)
                        infoRow("拍摄日期", record.displayDateText)
                        infoRow("大小", VaultLimits.readableBytes(record.byteSize))
                        infoRow("入库时间", record.addedAt.formatted(date: .numeric, time: .shortened))
                        if record.pendingRemoval {
                            infoRow("原件状态", "仍在系统相簿")
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .neuSurface(.inset, cornerRadius: Theme.Radius.card)

                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            onRestore()
                            dismiss()
                        } label: {
                            Label("取出到相册", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(
                            NeuButtonStyle(variant: .raised, tint: Theme.Accent.brass)
                        )

                        Button(role: .destructive) {
                            isDeleteConfirmPresented = true
                        } label: {
                            Label("永久删除", systemImage: "trash")
                        }
                        .buttonStyle(NeuButtonStyle(variant: .inset, tint: Theme.State.danger))
                    }
                }
                .padding(Theme.Spacing.page)
            }
            .background(Theme.Surface.base.ignoresSafeArea())
            .navigationTitle("保险箱条目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: record.id) {
                image = vault.fullImage(for: record)
            }
            .alert("永久删除保险箱副本？", isPresented: $isDeleteConfirmPresented) {
                Button("取消", role: .cancel) {}
                Button("永久删除", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("只删除 App 内的副本与清单，不触碰系统相簿。")
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.Text.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Text.primary)
                .multilineTextAlignment(.trailing)
        }
        .font(Theme.Typography.body)
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - 分享

struct VaultExportRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
