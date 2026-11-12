import CryptoKit
import Foundation
import ImageIO
import Photos
import SwiftData
import SwiftUI
import UIKit

/// 读取保险箱内容后交给界面使用的本地文件。
/// 标准档直接指向原文件；强加密档指向解密出的临时文件，用完必须 `cleanup()`。
struct VaultPreparedMedia {
    let imageURL: URL
    let videoURL: URL?
    let temporaryDirectory: URL?

    var isTemporary: Bool { temporaryDirectory != nil }

    func cleanup() {
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

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

    /// 只写入加密副本的阶段结果；不包含任何删除动作。
    /// 原件删除由任务结算把保险箱与废纸篓合并后一次提交（系统只确认一次）。
    struct StagedImport {
        var records: [VaultRecord] = []
        var failed = 0
        var messages: [String] = []

        var imported: Int { records.count }
        var isSuccess: Bool { !records.isEmpty }
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

    @ObservationIgnored private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // 只保留一屏附近够用的缩略图；按字节成本自动淘汰，避免上千项时内存失控。
        cache.countLimit = 300
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    @ObservationIgnored private var autoLockTask: Task<Void, Never>?
    /// iCloud 同步引擎挂在这里：写入后择机同步、删除时记录墓碑。
    /// 用轻量钩子而不是直接引用引擎，存储层不反向依赖同步层类型。
    @ObservationIgnored var syncHooks = VaultSyncHooks()

    init(container: ModelContainer? = nil) {
        let resolvedContainer = container ?? AppModelContainer.shared
        self.container = resolvedContainer
        self.context = resolvedContainer.mainContext
        Self.purgePreviewDirectory()
        reload()
    }

    /// 当前内容保护档位；只影响之后写入的文件。
    var encryptionMode: VaultEncryptionMode { VaultEncryptionMode.current }

    // MARK: - 清单

    func reload() {
        let descriptor = FetchDescriptor<VaultRecord>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        records = (try? context.fetch(descriptor)) ?? []
        totalBytes = records.reduce(0) { $0 + $1.byteSize }
        revision += 1
        syncHooks.onRecordsChanged?()
    }

    var usedItems: Int { records.count }

    var originLocalIDs: Set<String> {
        Set(records.compactMap(\.originLocalID))
    }

    var isConfigured: Bool { VaultCredentials.isConfigured }

    func lockStatus() -> VaultLockStatus {
        VaultLockPolicy.status()
    }

    /// 按当前存储模式取缩略图：标准档直接解码，强加密档先解密到临时文件再解码。
    func thumbnailAsync(for record: VaultRecord, maxPixel: CGFloat = 240) async -> UIImage? {
        let key = record.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        guard let media = try? await prepareMedia(for: record) else { return nil }
        defer { if media.isTemporary { media.cleanup() } }

        guard let image = await Task.detached(priority: .utility, operation: {
            Self.makeThumbnail(url: media.imageURL, maxPixel: maxPixel)
        }).value else { return nil }

        let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        thumbnailCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 统一读取路径：网格与全屏都拿到可直接交给 ImageIO / AVPlayer 的本地 URL。
    /// 强加密档返回解密出的临时文件，调用方用完必须 `cleanup()`。
    func prepareMedia(for record: VaultRecord) async throws -> VaultPreparedMedia {
        let primaryURL = Paths.vaultFileURL(relativePath: record.relativePath)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            throw VaultCryptoError.fileMissing
        }
        let pairedURL = record.pairedVideoPath.map { Paths.vaultFileURL(relativePath: $0) }

        // 按文件头判断，而不是按「当前档位」：切换过内容保护档位、或从另一台
        // 设备同步下来的标准档明文文件，都能被正确读取，不会被误当成密文解密。
        guard VaultCrypto.isEncryptedFile(at: primaryURL) else {
            return VaultPreparedMedia(
                imageURL: primaryURL,
                videoURL: pairedURL,
                temporaryDirectory: nil
            )
        }

        let key: SymmetricKey
        do {
            key = try VaultCrypto.contentKey(createIfNeeded: false)
        } catch {
            throw VaultCryptoError.keyUnavailable
        }

        let directory = Self.previewDirectory().appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let decrypted = try await Task.detached(priority: .userInitiated) { () -> (URL, URL?) in
                let imageURL = directory.appendingPathComponent(primaryURL.lastPathComponent)
                try VaultCrypto.decryptFile(at: primaryURL, to: imageURL, key: key)
                let videoURL = try pairedURL.map { source -> URL in
                    let destination = directory.appendingPathComponent(source.lastPathComponent)
                    try VaultCrypto.decryptFile(at: source, to: destination, key: key)
                    return destination
                }
                return (imageURL, videoURL)
            }.value
            return VaultPreparedMedia(
                imageURL: decrypted.0,
                videoURL: decrypted.1,
                temporaryDirectory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
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

    /// 只写加密副本，不删除原件。返回本次成功写入的记录，供任务结算统一提交删除。
    func stageAssets(
        localIDs: [String],
        kinds: [String: MediaKind],
        entitlements: EntitlementStore
    ) async -> StagedImport {
        var staged = StagedImport()
        guard !localIDs.isEmpty else { return staged }
        guard !isBusy else {
            staged.messages.append("上一批入库还在进行中")
            return staged
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
            staged.messages.append("剩余磁盘空间不足，请先清理后再试")
            return staged
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in fetchedAssets.append(asset) }

        for (index, asset) in fetchedAssets.enumerated() {
            defer { importProgress = Double(index + 1) / Double(max(fetchedAssets.count, 1)) }

            let assetID = asset.localIdentifier
            let kind = kinds[assetID] ?? MediaKind.from(asset: asset)

            if records.contains(where: { $0.originLocalID == assetID }) {
                staged.messages.append("已在保险箱：\(kind.displayName)")
                staged.failed += 1
                continue
            }

            let mediaGate = entitlements.canImport(
                kind: kind,
                byteSize: 0,
                usedItems: records.count,
                usedBytes: totalBytes
            )
            guard mediaGate.isAllowed else {
                staged.messages.append(mediaGate.message ?? "未通过权益校验")
                staged.failed += 1
                continue
            }

            let copied: VaultImporter.CopyResult
            do {
                copied = try await VaultImporter.copy(asset: asset, kind: kind)
            } catch {
                // 单张复制失败只跳过该张，不影响同批其它照片。
                staged.messages.append(error.localizedDescription)
                staged.failed += 1
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
                staged.messages.append(quota.message ?? "超出保险箱额度")
                staged.failed += 1
                continue
            }

            // 强加密档：文件落盘后立刻原地加密；失败则整条回滚，不留下半加密文件。
            if encryptionMode == .strong {
                do {
                    let key = try VaultCrypto.contentKey()
                    let primaryURL = Paths.vaultFileURL(relativePath: copied.relativePath)
                    let pairedURL = copied.pairedVideoPath.map { Paths.vaultFileURL(relativePath: $0) }
                    try await Task.detached(priority: .userInitiated) {
                        try VaultCrypto.encryptFile(at: primaryURL, key: key)
                        if let pairedURL {
                            try VaultCrypto.encryptFile(at: pairedURL, key: key)
                        }
                    }.value
                } catch {
                    Paths.removeFile(atRelativePath: copied.relativePath)
                    if let paired = copied.pairedVideoPath {
                        Paths.removeFile(atRelativePath: paired)
                    }
                    staged.messages.append("强加密失败：\(error.localizedDescription)")
                    staged.failed += 1
                    continue
                }
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
            staged.records.append(record)
        }

        return staged
    }

    /// 系统确认成功后提交：副本保持有效，队列清空。
    func commitStaged(_ stagedRecords: [VaultRecord]) {
        guard !stagedRecords.isEmpty else { return }
        for record in stagedRecords {
            record.pendingRemoval = false
        }
        try? context.save()
        reload()
    }

    /// 系统确认取消后回滚：删除本次写入的副本文件、缩略图缓存与 SwiftData 记录，
    /// 避免留下“系统相册原图 + 保险箱副本”的重复。返回回滚数量。
    @discardableResult
    func rollbackStaged(_ stagedRecords: [VaultRecord]) -> Int {
        guard !stagedRecords.isEmpty else { return 0 }
        return rollback(stagedRecords)
    }

    /// 非取消失败：副本保留，标记为待移出原件，供保险箱里手动重试。
    func markPendingRemoval(_ stagedRecords: [VaultRecord]) {
        guard !stagedRecords.isEmpty else { return }
        for record in stagedRecords {
            record.pendingRemoval = true
        }
        try? context.save()
        reload()
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
        var deletedIDs: [UUID] = []
        defer {
            isBusy = false
            if !deletedIDs.isEmpty { syncHooks.onRecordsDeleted?(deletedIDs) }
            reload()
        }

        let targets = records.filter { ids.contains($0.id) }
        for record in targets {
            do {
                let media = try await prepareMedia(for: record)
                defer { if media.isTemporary { media.cleanup() } }
                try await VaultRestorer.restore(record, media: media)
                removeFiles(for: record)
                context.delete(record)
                try? context.save()
                thumbnailCache.removeObject(forKey: record.id.uuidString as NSString)
                deletedIDs.append(record.id)
                summary.restored += 1
            } catch {
                record.state = .broken
                try? context.save()
                summary.failed += 1
            }
        }
        return summary
    }

    /// 导出：强加密档导出解密后的临时副本；返回的目录由调用方在分享结束后清理。
    func exportURLs(ids: [UUID]) async -> (urls: [URL], temporaryDirectories: [URL]) {
        var urls: [URL] = []
        var directories: [URL] = []
        for record in records where ids.contains(record.id) {
            guard let media = try? await prepareMedia(for: record) else { continue }
            urls.append(media.imageURL)
            if let videoURL = media.videoURL {
                urls.append(videoURL)
            }
            if let directory = media.temporaryDirectory {
                directories.append(directory)
            }
        }
        return (urls, directories)
    }

    func permanentDelete(ids: [UUID]) {
        var deletedIDs: [UUID] = []
        for record in records where ids.contains(record.id) {
            removeFiles(for: record)
            thumbnailCache.removeObject(forKey: record.id.uuidString as NSString)
            context.delete(record)
            deletedIDs.append(record.id)
        }
        try? context.save()
        if !deletedIDs.isEmpty { syncHooks.onRecordsDeleted?(deletedIDs) }
        reload()
    }

    func resetAll() {
        let descriptor = FetchDescriptor<VaultRecord>()
        var deletedIDs: [UUID] = []
        if let all = try? context.fetch(descriptor) {
            for record in all {
                removeFiles(for: record)
                context.delete(record)
                deletedIDs.append(record.id)
            }
        }
        try? context.save()
        if !deletedIDs.isEmpty { syncHooks.onRecordsDeleted?(deletedIDs) }

        try? FileManager.default.removeItem(at: Paths.vaultDirectory)
        Paths.ensureVaultDirectory()

        VaultCredentials.resetAll()
        VaultLockPolicy.reset()
        thumbnailCache.removeAllObjects()
        isUnlocked = false
        reload()
    }

    // MARK: - iCloud 同步接口

    /// 本机清单里是否已有该条目（云端记录以 UUID 为唯一键）。
    func containsRecord(id: UUID) -> Bool {
        records.contains { $0.id == id }
    }

    /// 可上传的条目：文件存在、且是标准档明文。
    /// 强加密文件的内容密钥只在本机 Keychain，其它设备拿到也无法解密，直接跳过。
    func syncableItems() -> [VaultSyncItem] {
        records.compactMap { record in
            let url = Paths.vaultFileURL(relativePath: record.relativePath)
            guard FileManager.default.fileExists(atPath: url.path),
                  !VaultCrypto.isEncryptedFile(at: url) else { return nil }
            return VaultSyncItem(
                id: record.id,
                fileName: record.fileName,
                mediaKindRaw: record.mediaKindRaw,
                byteSize: record.byteSize,
                capturedAt: record.capturedAt,
                addedAt: record.addedAt,
                albumNames: record.albumNames,
                hasPairedVideo: record.pairedVideoPath != nil,
                mediaURL: url,
                pairedVideoURL: record.pairedVideoPath.map {
                    Paths.vaultFileURL(relativePath: $0)
                }
            )
        }
    }

    /// 云端新增条目落地：把 CKAsset 复制到本机 Vault 目录（沿用相对路径规则），
    /// 再插入清单。远端条目没有本机系统资产 id，`originLocalID` 留空。
    func applyRemoteUpsert(
        _ item: VaultRemoteItem,
        mediaURL: URL,
        pairedVideoURL: URL?
    ) async throws {
        guard !containsRecord(id: item.id) else { return }
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            throw VaultCryptoError.fileMissing
        }

        let relativePath = Paths.makeRelativePath(fileName: item.fileName)
        let videoRelativePath: String? = (item.hasPairedVideo && pairedVideoURL != nil)
            ? Paths.makeRelativePath(fileName: Self.videoFileName(from: item.fileName))
            : nil
        let primaryURL = Paths.vaultFileURL(relativePath: relativePath)
        let videoDestURL = videoRelativePath.map { Paths.vaultFileURL(relativePath: $0) }
        _ = Paths.ensureVaultDirectory()

        do {
            // CloudKit 的 CKAsset.fileURL 只在本次 record 生命周期内有效，必须先复制走。
            try await Task.detached(priority: .utility) {
                try FileManager.default.copyItem(at: mediaURL, to: primaryURL)
                if let pairedVideoURL, let videoDestURL {
                    try FileManager.default.copyItem(at: pairedVideoURL, to: videoDestURL)
                }
            }.value
        } catch {
            try? FileManager.default.removeItem(at: primaryURL)
            if let videoDestURL { try? FileManager.default.removeItem(at: videoDestURL) }
            throw error
        }

        Paths.applyVaultFileAttributes(to: primaryURL)
        if let videoDestURL { Paths.applyVaultFileAttributes(to: videoDestURL) }

        let record = VaultRecord(
            id: item.id,
            originLocalID: nil,
            fileName: item.fileName,
            mediaKind: MediaKind(rawValue: item.mediaKindRaw) ?? .photo,
            byteSize: item.byteSize,
            capturedAt: item.capturedAt,
            addedAt: item.addedAt,
            albumNames: item.albumNames,
            relativePath: relativePath,
            pairedVideoPath: videoRelativePath
        )
        context.insert(record)
        try? context.save()
        // 批量同步时逐条全表 fetch 会是 O(n²)：这里只增量更新内存清单，
        // 由引擎在整轮 pull 结束后统一 reload() 一次。
        records.insert(record, at: 0)
        totalBytes += record.byteSize
        revision += 1
    }

    /// 云端删除墓碑落地：删本机副本与清单，不再回写墓碑（避免自我放大）。
    func applyRemoteDeletion(ids: [UUID]) {
        let targets = records.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }
        for record in targets {
            removeFiles(for: record)
            thumbnailCache.removeObject(forKey: record.id.uuidString as NSString)
            context.delete(record)
        }
        try? context.save()
        records.removeAll { ids.contains($0.id) }
        totalBytes = records.reduce(0) { $0 + $1.byteSize }
        revision += 1
    }

    private static func videoFileName(from fileName: String) -> String {
        (fileName as NSString).deletingPathExtension + ".mov"
    }

    // MARK: - 内部

    /// 系统确认取消：删除刚写入的加密副本并清掉对应记录。
    @discardableResult
    private func rollback(_ copiedRecords: [VaultRecord]) -> Int {
        guard !copiedRecords.isEmpty else { return 0 }

        let ids = Set(copiedRecords.map(\.id))
        for record in copiedRecords {
            removeFiles(for: record)
            thumbnailCache.removeObject(forKey: record.id.uuidString as NSString)
            context.delete(record)
        }
        try? context.save()

        records.removeAll { ids.contains($0.id) }
        totalBytes = records.reduce(0) { $0 + $1.byteSize }
        syncHooks.onRecordsDeleted?(Array(ids))
        syncHooks.onRecordsChanged?()
        return copiedRecords.count
    }

    private func removeFiles(for record: VaultRecord) {
        Paths.removeFile(atRelativePath: record.relativePath)
        if let paired = record.pairedVideoPath {
            Paths.removeFile(atRelativePath: paired)
        }
    }

    private static func previewDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VaultPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 启动时清掉上次会话遗留的解密临时文件。
    private static func purgePreviewDirectory() {
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("VaultPreview")
        )
    }

    nonisolated private static func makeThumbnail(url: URL, maxPixel: CGFloat) -> UIImage? {
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
