import CloudKit
import Foundation
import Observation
import UIKit

/// 私密保险箱的 iCloud 同步引擎（CloudKit 私有数据库）。
///
/// 设计边界（与产品决策一致）：
/// - SwiftData 清单仍是本机唯一真相，不把 `ModelContainer` 改成 CloudKit 容器，
///   避免 `DayStat` 统计被一起同步、也避免本机语义字段（`originLocalID` 等）跨域冲突。
/// - 只有普通明文文件参与同步；旧版本加密文件的 AES-GCM 密钥只在本机 Keychain，
///   上传后其它设备无法解密，因此继续跳过。密码 verifier、锁定状态同样不上云，
///   每台设备各自设一次密码。
/// - 删除用 `isDeleted` 墓碑传播，不做 CloudKit 硬删除：本机删掉一条后仍能把
///   「删除」这件事传到其它设备，新设备也不会把云端条目误当成新增。
/// - 不依赖静默推送订阅：App 启动、回到前台、本机清单变更、手动点击「立即同步」
///   都会触发；另一台设备切到前台即可收敛，无需后台推送能力。
@MainActor
@Observable
final class VaultSyncEngine {
    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }

    private(set) var phase: VaultSyncPhase = .off
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var syncedItemCount = 0
    private(set) var pendingItemCount = 0
    /// 被跳过的旧版加密条目数。
    private(set) var skippedLegacyEncryptedItemCount = 0
    private(set) var errorMessage: String?

    @ObservationIgnored private weak var vault: VaultStore?
    @ObservationIgnored private weak var entitlements: EntitlementStore?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var syncRequestedWhileRunning = false

    init() {
        container = CKContainer(identifier: VaultSyncField.containerIdentifier)
        lastSyncDate = UserDefaults.standard.object(forKey: VaultSyncPreference.lastSyncKey) as? Date
    }

    // MARK: - 生命周期

    /// 由 App 入口调用一次：绑定存储层与权益源，并挂上变更钩子。
    func start(vault: VaultStore, entitlements: EntitlementStore) {
        guard !didStart else { return }
        didStart = true
        self.vault = vault
        self.entitlements = entitlements

        vault.syncHooks.onRecordsChanged = { [weak self] in self?.scheduleSync() }
        vault.syncHooks.onRecordsDeleted = { [weak self] ids in self?.noteLocalDeletion(ids) }

        refreshGate()
        if VaultSyncPreference.isEnabled { scheduleSync(delay: .seconds(1)) }
    }

    /// 设置页开关变化 / VIP 状态变化后调用。
    func syncEnabledDidChange() {
        debounceTask?.cancel()
        syncTask?.cancel()
        // 不强制改 isSyncing：正在进行的 CloudKit 调用会自行收尾，
        // 各循环入口检查开关 / 取消状态后立即停止上传下载。
        refreshGate()
        guard VaultSyncPreference.isEnabled, phase == .ready else { return }
        scheduleSync(delay: .milliseconds(400))
    }

    /// App 回到前台：拉一次其它设备的变更。
    func didEnterForeground() {
        guard VaultSyncPreference.isEnabled, entitlements?.isVIP == true else {
            refreshGate()
            return
        }
        scheduleSync(delay: .milliseconds(600))
    }

    /// 设置页「立即同步」按钮。
    func syncNow() {
        guard VaultSyncPreference.isEnabled else { refreshGate(); return }
        guard entitlements?.isVIP == true else { phase = .vipRequired; return }
        if isSyncing {
            syncRequestedWhileRunning = true
            return
        }
        debounceTask?.cancel()
        syncTask?.cancel()
        syncTask = Task { [weak self] in await self?.runSync() }
    }

    // MARK: - 状态展示

    var statusText: String {
        switch phase {
        case .off:
            "未开启".localized
        case .vipRequired:
            "VIP 专属，升级后可用".localized
        case .ready:
            if let lastSyncDate {
                "已同步 %@ 项 · 上次 %@".localized(syncedItemCount, Self.timeFormatter.string(from: lastSyncDate))
            } else {
                "等待首次同步".localized
            }
        case .syncing:
            "正在同步…".localized
        case .noAccount:
            "请先在系统设置登录 iCloud".localized
        case .restricted:
            "此设备的 iCloud 访问受限".localized
        case .failure(let message):
            message
        }
    }

    var detailText: String {
        var text = "保险箱普通文件同步到你的 iCloud 私有数据库；密码与锁定状态始终只留在本机，每台设备各自设置密码。".localized
        if skippedLegacyEncryptedItemCount > 0 {
            text += " 当前有 %@ 项旧版加密内容未上传。".localized(skippedLegacyEncryptedItemCount)
        }
        return text
    }

    var canSyncNow: Bool {
        VaultSyncPreference.isEnabled && entitlements?.isVIP == true && !isSyncing
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - 触发

    private func refreshGate() {
        guard !isSyncing else { return }
        guard VaultSyncPreference.isEnabled else { phase = .off; return }
        guard entitlements?.isVIP == true else { phase = .vipRequired; return }
        phase = .ready
    }

    private func scheduleSync(delay: Duration = .seconds(1.2)) {
        guard VaultSyncPreference.isEnabled, entitlements?.isVIP == true else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.runSync()
        }
    }

    private func noteLocalDeletion(_ ids: [UUID]) {
        guard VaultSyncPreference.isEnabled, !ids.isEmpty else { return }
        var pending = tombstoneSet
        for id in ids { pending.insert(id.uuidString) }
        tombstoneSet = pending
        scheduleSync()
    }

    private var tombstoneSet: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: VaultSyncPreference.tombstonesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: VaultSyncPreference.tombstonesKey) }
    }

    // MARK: - 同步主流程

    private func runSync() async {
        guard VaultSyncPreference.isEnabled else { refreshGate(); return }
        guard entitlements?.isVIP == true else { phase = .vipRequired; return }
        guard !isSyncing else {
            syncRequestedWhileRunning = true
            return
        }
        guard let vault else { return }

        isSyncing = true
        phase = .syncing
        errorMessage = nil
        defer {
            isSyncing = false
            if syncRequestedWhileRunning {
                syncRequestedWhileRunning = false
                scheduleSync(delay: .milliseconds(0))
            }
        }

        do {
            switch try await fetchAccountStatus() {
            case .available:
                break
            case .noAccount:
                phase = .noAccount
                return
            case .restricted:
                phase = .restricted
                return
            default:
                phase = .failure("暂时无法确认 iCloud 账号状态，请稍后重试。".localized)
                return
            }

            let tombstonesBefore = tombstoneSet
            var remote = try await fetchRemoteMetadata()
            try await applyTombstones(to: &remote)

            // 墓碑标记直接改了 CKRecord 对象，这里重新解析，保证 isDeleted 是最新的。
            let remoteItems = remote.compactMap { VaultRemoteItem(record: $0) }
            let remoteByID = Dictionary(
                remote.map { ($0.recordID.recordName, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            try await pull(remoteItems, tombstones: tombstonesBefore, vault: vault)
            // 整轮远端写入结束后统一刷新一次清单（排序、totalBytes、revision）。
            vault.reload(notifySync: false)

            let localItems = vault.syncableItems()
            skippedLegacyEncryptedItemCount = vault.legacyEncryptedItemCount
            pendingItemCount = localItems.filter {
                remoteByID[VaultSyncField.recordName(for: $0.id)] == nil
            }.count
            let uploaded = try await push(localItems, remoteByID: remoteByID)

            syncedItemCount = remoteItems.filter { !$0.isDeleted }.count + uploaded
            pendingItemCount = 0
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: VaultSyncPreference.lastSyncKey)
            phase = VaultSyncPreference.isEnabled ? .ready : .off
        } catch is CancellationError {
            phase = VaultSyncPreference.isEnabled ? .ready : .off
        } catch {
            let message = Self.describe(error)
            errorMessage = message
            phase = .failure(message)
        }
    }

    private func fetchAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    /// 拉取云端全部元数据（不含 CKAsset）。首次同步时记录类型还不存在，
    /// CloudKit 会返回 unknownItem，此时按「空库」处理，随后由 push 创建。
    private func fetchRemoteMetadata() async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: VaultSyncField.recordType,
            predicate: NSPredicate(value: true)
        )
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        var pageCount = 0

        do {
            repeat {
                let page: (
                    matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
                    queryCursor: CKQueryOperation.Cursor?
                )
                if let cursor {
                    page = try await database.records(
                        continuingMatchFrom: cursor,
                        desiredKeys: VaultSyncField.metadataKeys,
                        resultsLimit: VaultSyncField.pageSize
                    )
                } else {
                    page = try await database.records(
                        matching: query,
                        inZoneWith: nil,
                        desiredKeys: VaultSyncField.metadataKeys,
                        resultsLimit: VaultSyncField.pageSize
                    )
                }
                for (_, result) in page.matchResults {
                    if case .success(let record) = result { all.append(record) }
                }
                cursor = page.queryCursor
                pageCount += 1
            } while cursor != nil && pageCount < 50
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
        return all
    }

    /// 本机删除过的条目：把云端对应记录标为已删除，成功后清掉本地墓碑。
    /// 用软删除而不是 `deleteRecord`，新设备才不会把「云端缺一条」理解成首次同步。
    private func applyTombstones(to remote: inout [CKRecord]) async throws {
        let pending = tombstoneSet
        guard !pending.isEmpty else { return }

        let byName = Dictionary(
            remote.map { ($0.recordID.recordName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var remaining = pending

        for name in pending {
            guard VaultSyncPreference.isEnabled, !Task.isCancelled else { break }
            guard let record = byName[VaultSyncField.recordName(forUUIDString: name)] else {
                // 云端本来就没有这条，无需传播。
                remaining.remove(name)
                continue
            }
            if (record[VaultSyncField.isDeleted] as? NSNumber)?.boolValue == true {
                remaining.remove(name)
                continue
            }
            record[VaultSyncField.isDeleted] = NSNumber(value: true)
            record[VaultSyncField.modifiedAt] = NSDate()
            do {
                _ = try await database.save(record)
                remaining.remove(name)
            } catch {
                // 保留墓碑，下次同步重试；单条失败不中断整轮。
            }
        }
        tombstoneSet = remaining
    }

    /// 云端 → 本机：删除墓碑落地，新条目按需下载 CKAsset 并写入本机清单。
    private func pull(
        _ items: [VaultRemoteItem],
        tombstones: Set<String>,
        vault: VaultStore
    ) async throws {
        for item in items where item.schemaVersion <= VaultSyncField.schemaVersion {
            guard VaultSyncPreference.isEnabled, !Task.isCancelled else { break }
            if item.isDeleted {
                if vault.containsRecord(id: item.id) {
                    vault.applyRemoteDeletion(ids: [item.id])
                }
                continue
            }
            // 本机刚删过、但云端墓碑还没标成功的条目，不能又下载回来。
            guard !tombstones.contains(item.id.uuidString),
                  !vault.containsRecord(id: item.id) else { continue }

            let recordID = CKRecord.ID(recordName: item.recordName)
            let results = try await database.records(for: [recordID], desiredKeys: nil)
            guard let result = results[recordID],
                  case .success(let full) = result,
                  let asset = full[VaultSyncField.media] as? CKAsset,
                  let mediaURL = asset.fileURL else { continue }
            let videoURL = (full[VaultSyncField.pairedVideo] as? CKAsset)?.fileURL

            // 单条下载失败只跳过这一条，不影响后面的条目。
            try? await vault.applyRemoteUpsert(item, mediaURL: mediaURL, pairedVideoURL: videoURL)
        }
    }

    /// 本机 → 云端：只上传标准档明文文件；云端已有则跳过。
    private func push(_ items: [VaultSyncItem], remoteByID: [String: CKRecord]) async throws -> Int {
        var uploaded = 0
        for item in items {
            guard VaultSyncPreference.isEnabled, !Task.isCancelled else { break }
            let name = VaultSyncField.recordName(for: item.id)
            if let existing = remoteByID[name] {
                let deleted = (existing[VaultSyncField.isDeleted] as? NSNumber)?.boolValue ?? false
                // 同一 id 在本机重新出现（极少见）：复活这条云端记录。
                guard deleted else { continue }
                let record = Self.makeRecord(for: item, existing: existing)
                _ = try await database.save(record)
                uploaded += 1
                continue
            }
            let record = Self.makeRecord(for: item, existing: nil)
            _ = try await database.save(record)
            uploaded += 1
        }
        return uploaded
    }

    private static func makeRecord(for item: VaultSyncItem, existing: CKRecord?) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: VaultSyncField.recordType,
            recordID: CKRecord.ID(recordName: VaultSyncField.recordName(for: item.id))
        )
        record[VaultSyncField.itemID] = item.id.uuidString as NSString
        record[VaultSyncField.fileName] = item.fileName as NSString
        record[VaultSyncField.mediaKindRaw] = item.mediaKindRaw as NSString
        record[VaultSyncField.byteSize] = NSNumber(value: item.byteSize)
        record[VaultSyncField.capturedAt] = item.capturedAt.map { $0 as NSDate }
        record[VaultSyncField.addedAt] = item.addedAt as NSDate
        record[VaultSyncField.albumNames] = item.albumNames as NSArray
        record[VaultSyncField.hasPairedVideo] = NSNumber(value: item.hasPairedVideo)
        record[VaultSyncField.isDeleted] = NSNumber(value: false)
        record[VaultSyncField.schemaVersionKey] = NSNumber(value: schemaVersion)
        record[VaultSyncField.modifiedAt] = NSDate()
        record[VaultSyncField.originDevice] = deviceName as NSString
        record[VaultSyncField.media] = CKAsset(fileURL: item.mediaURL)
        if let videoURL = item.pairedVideoURL {
            record[VaultSyncField.pairedVideo] = CKAsset(fileURL: videoURL)
        }
        return record
    }

    private static var schemaVersion: Int { VaultSyncField.schemaVersion }

    private static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "unknown"
        #endif
    }

    private static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "同步失败：%@".localized(error.localizedDescription)
        }
        switch ckError.code {
        case .notAuthenticated:
            return "尚未登录 iCloud，请在系统设置登录 Apple ID。".localized
        case .networkUnavailable, .networkFailure:
            return "网络不可用，请联网后重试。".localized
        case .quotaExceeded:
            return "iCloud 储存空间不足，请清理后重试。".localized
        case .permissionFailure, .invalidArguments:
            return "iCloud 权限未就绪：请在 App Store Connect 为 App ID 启用 iCloud / CloudKit 能力。".localized
        case .unknownItem:
            return "CloudKit 容器尚未就绪，请确认 iCloud.com.gpwzw.appSuperPhotos 已创建。".localized
        case .serviceUnavailable, .zoneBusy, .requestRateLimited:
            return "iCloud 暂时繁忙，请稍后重试。".localized
        default:
            return "同步失败：%@".localized(error.localizedDescription)
        }
    }
}
