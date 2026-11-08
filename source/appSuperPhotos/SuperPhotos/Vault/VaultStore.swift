import Foundation
import ImageIO
import Photos
import SwiftData
import SwiftUI
import UIKit

/// 保险箱的唯一状态入口：清单、文件、解锁会话、入库/取出编排都在这里。
@MainActor
@Observable
final class VaultStore {
    enum UnlockResult: Equatable {
        case success
        case wrong(remaining: Int)
        case locked(seconds: Int)
        case notConfigured
    }

    struct ImportSummary {
        var imported = 0
        var failed = 0
        var messages: [String] = []
        var removalPending = false

        var isSuccess: Bool { imported > 0 }
    }

    struct RestoreSummary {
        var restored = 0
        var failed = 0
    }

    private let container: ModelContainer
    private let context: ModelContext

    private(set) var records: [VaultRecord] = []
    private(set) var totalBytes: Int64 = 0
    private(set) var isBusy = false
    private(set) var isUnlocked = false
    private(set) var revision = 0
    /// 批量入库进度（0...1）；nil 表示未在执行。
    private(set) var importProgress: Double?

    @ObservationIgnored private var thumbnailCache: [UUID: UIImage] = [:]
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?

    init(container: ModelContainer? = nil) {
        let resolvedContainer = container ?? AppModelContainer.shared
        self.container = resolvedContainer
        self.context = resolvedContainer.mainContext
        reload()
    }

    // MARK: - 清单

    func reload() {
        let descriptor = FetchDescriptor<VaultRecord>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        records = (try? context.fetch(descriptor)) ?? []
        totalBytes = records.reduce(0) { $0 + $1.byteSize }
        revision += 1
    }

    var usedItems: Int { records.count }

    var originLocalIDs: Set<String> {
        Set(records.compactMap(\.originLocalID))
    }

    var isConfigured: Bool { VaultCredentials.isConfigured }

    func lockStatus() -> VaultLockStatus {
        VaultLockPolicy.status()
    }

    func thumbnail(for record: VaultRecord, maxPixel: CGFloat = 240) -> UIImage? {
        if let cached = thumbnailCache[record.id] { return cached }
        let url = Paths.vaultFileURL(relativePath: record.relativePath)
        guard let image = Self.makeThumbnail(url: url, maxPixel: maxPixel) else { return nil }
        thumbnailCache[record.id] = image
        return image
    }

    func fullImage(for record: VaultRecord) -> UIImage? {
        let url = Paths.vaultFileURL(relativePath: record.relativePath)
        return Self.makeThumbnail(url: url, maxPixel: 2048)
    }

    // MARK: - 解锁

    func configure(a: Int, b: Int) throws {
        try VaultCredentials.setPassword(a: a, b: b)
        VaultLockPolicy.registerSuccess()
        isUnlocked = true
    }

    func unlock(a: Int, b: Int) async -> UnlockResult {
        guard VaultCredentials.isConfigured,
              let material = VaultCredentials.verificationMaterial() else {
            return .notConfigured
        }

        let status = VaultLockPolicy.status()
        if status.isLocked() {
            return .locked(seconds: status.remainingSeconds())
        }

        // PBKDF2 120,000 次放到后台，避免阻塞主线程。
        let isValid = await Task.detached(priority: .userInitiated) {
            VaultCredentials.matches(a: a, b: b, salt: material.salt, verifier: material.verifier)
        }.value

        if isValid {
            VaultLockPolicy.registerSuccess()
            isUnlocked = true
            return .success
        }

        let updated = VaultLockPolicy.registerFailure()
        if updated.isLocked() {
            return .locked(seconds: updated.remainingSeconds())
        }
        return .wrong(remaining: max(0, 5 - updated.failures))
    }

    func verifyOnly(a: Int, b: Int) -> Bool {
        VaultCredentials.verify(a: a, b: b)
    }

    enum VerificationResult: Equatable {
        case success
        case wrong(remaining: Int)
        case locked(seconds: Int)
    }

    /// 设置页校验旧密码：与解锁共用锁定策略，避免绕过阶梯锁定。
    func verifyPassword(a: Int, b: Int) -> VerificationResult {
        let status = VaultLockPolicy.status()
        if status.isLocked() {
            return .locked(seconds: status.remainingSeconds())
        }
        if VaultCredentials.verify(a: a, b: b) {
            VaultLockPolicy.registerSuccess()
            return .success
        }
        let updated = VaultLockPolicy.registerFailure()
        if updated.isLocked() {
            return .locked(seconds: updated.remainingSeconds())
        }
        return .wrong(remaining: max(0, 5 - updated.failures))
    }

    func lock() {
        isUnlocked = false
    }

    /// 后台自动锁定：立即 / 30s / 60s。
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            let delay = VaultAutoLock.currentDelay
            if delay == 0 {
                lock()
            } else {
                autoLockTask?.cancel()
                autoLockTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.lock()
                }
            }
        case .active:
            autoLockTask?.cancel()
            autoLockTask = nil
        default:
            break
        }
    }

    // MARK: - 入库

    func importAssets(
        localIDs: [String],
        kinds: [String: MediaKind],
        entitlements: EntitlementStore,
        simulateRemoval: Bool = false
    ) async -> ImportSummary {
        var summary = ImportSummary()
        guard !localIDs.isEmpty else { return summary }
        guard !isBusy else {
            summary.messages.append("上一批入库还在进行中")
            return summary
        }

        isBusy = true
        importProgress = 0
        defer {
            isBusy = false
            importProgress = nil
            reload()
        }

        if Paths.availableCapacity() > 0,
           Paths.availableCapacity() <= VaultLimits.diskSafetyMargin {
            summary.messages.append("剩余磁盘空间不足，请先清理后再试")
            return summary
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in fetchedAssets.append(asset) }

        var copiedRecords: [VaultRecord] = []

        for (index, asset) in fetchedAssets.enumerated() {
            defer { importProgress = Double(index + 1) / Double(max(fetchedAssets.count, 1)) }

            let assetID = asset.localIdentifier
            let kind = kinds[assetID] ?? MediaKind.from(asset: asset)

            if records.contains(where: { $0.originLocalID == assetID }) {
                summary.messages.append("已在保险箱：\(kind.displayName)")
                summary.failed += 1
                continue
            }

            let mediaGate = entitlements.canImport(
                kind: kind,
                byteSize: 0,
                usedItems: records.count,
                usedBytes: totalBytes
            )
            guard mediaGate.isAllowed else {
                summary.messages.append(mediaGate.message ?? "未通过权益校验")
                summary.failed += 1
                continue
            }

            let copied: VaultImporter.CopyResult
            do {
                copied = try await VaultImporter.copy(asset: asset, kind: kind)
            } catch {
                summary.messages.append(error.localizedDescription)
                summary.failed += 1
                continue
            }

            let quota = VaultLimits.quotaGate(
                usedItems: records.count,
                usedBytes: totalBytes,
                additionalItems: 1,
                additionalBytes: copied.byteSize,
                tier: entitlements.tier
            )
            guard quota.isAllowed else {
                Paths.removeFile(atRelativePath: copied.relativePath)
                if let paired = copied.pairedVideoPath {
                    Paths.removeFile(atRelativePath: paired)
                }
                summary.messages.append(quota.message ?? "超出保险箱额度")
                summary.failed += 1
                continue
            }

            let record = VaultRecord(
                originLocalID: assetID,
                fileName: copied.fileName,
                mediaKind: kind,
                byteSize: copied.byteSize,
                capturedAt: asset.creationDate,
                albumNames: copied.albumNames,
                relativePath: copied.relativePath,
                pairedVideoPath: copied.pairedVideoPath
            )
            context.insert(record)
            try? context.save()

            records.insert(record, at: 0)
            totalBytes += copied.byteSize
            copiedRecords.append(record)
            summary.imported += 1
        }

        // 删除原件是整个流程的最后一步，整批只弹一次系统确认。
        if !copiedRecords.isEmpty {
            if simulateRemoval {
                summary.messages.append("已模拟移出系统相簿（Debug）")
            } else {
                do {
                    try await DeleteService.delete(localIDs: copiedRecords.compactMap(\.originLocalID))
                } catch {
                    for record in copiedRecords {
                        record.pendingRemoval = true
                    }
                    try? context.save()
                    summary.removalPending = true
                    summary.messages.append("副本已保存，但原件未能移出相簿：\(error.localizedDescription)")
                }
            }
        }

        return summary
    }

    /// 重试“移出相簿”。
    func retryPendingRemoval() async -> Int {
        let pending = records.filter(\.pendingRemoval)
        guard !pending.isEmpty else { return 0 }

        do {
            try await DeleteService.delete(localIDs: pending.compactMap(\.originLocalID))
            for record in pending { record.pendingRemoval = false }
            try? context.save()
            reload()
            return pending.count
        } catch {
            return 0
        }
    }

    // MARK: - 取出 / 导出 / 永久删除

    func restore(ids: [UUID]) async -> RestoreSummary {
        var summary = RestoreSummary()
        guard !isBusy else { return summary }

        isBusy = true
        defer {
            isBusy = false
            reload()
        }

        let targets = records.filter { ids.contains($0.id) }
        for record in targets {
            do {
                try await VaultRestorer.restore(record)
                removeFiles(for: record)
                context.delete(record)
                try? context.save()
                thumbnailCache.removeValue(forKey: record.id)
                summary.restored += 1
            } catch {
                record.state = .broken
                try? context.save()
                summary.failed += 1
            }
        }
        return summary
    }

    func exportURLs(ids: [UUID]) -> [URL] {
        records
            .filter { ids.contains($0.id) }
            .flatMap { record -> [URL] in
                var urls = [Paths.vaultFileURL(relativePath: record.relativePath)]
                if let paired = record.pairedVideoPath {
                    urls.append(Paths.vaultFileURL(relativePath: paired))
                }
                return urls
            }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func permanentDelete(ids: [UUID]) {
        for record in records where ids.contains(record.id) {
            removeFiles(for: record)
            thumbnailCache.removeValue(forKey: record.id)
            context.delete(record)
        }
        try? context.save()
        reload()
    }

    func resetAll() {
        let descriptor = FetchDescriptor<VaultRecord>()
        if let all = try? context.fetch(descriptor) {
            for record in all {
                removeFiles(for: record)
                context.delete(record)
            }
        }
        try? context.save()

        try? FileManager.default.removeItem(at: Paths.vaultDirectory)
        Paths.ensureVaultDirectory()

        VaultCredentials.resetAll()
        VaultLockPolicy.reset()
        thumbnailCache.removeAll()
        isUnlocked = false
        reload()
    }

    // MARK: - 内部

    private func removeFiles(for record: VaultRecord) {
        Paths.removeFile(atRelativePath: record.relativePath)
        if let paired = record.pairedVideoPath {
            Paths.removeFile(atRelativePath: paired)
        }
    }

    private static func makeThumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

/// 自动锁定时长；默认“立即”。
enum VaultAutoLock: Int, CaseIterable, Identifiable {
    case immediate = 0
    case thirtySeconds = 30
    case oneMinute = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediate: "立即"
        case .thirtySeconds: "30 秒"
        case .oneMinute: "1 分钟"
        }
    }

    static let defaultsKey = "vault.autoLockSeconds"

    static var current: VaultAutoLock {
        let stored = UserDefaults.standard.integer(forKey: defaultsKey)
        return VaultAutoLock(rawValue: stored) ?? .immediate
    }

    static var currentDelay: TimeInterval {
        TimeInterval(current.rawValue)
    }
}
