import Foundation
import Photos
import UIKit

/// 照片库唯一查询入口：界面不得自行 fetch。
@MainActor
@Observable
final class LibraryService {
    private(set) var accessState: LibraryAccessState = .notDetermined
    private(set) var items: [PhotoItem] = []
    private(set) var isLoading = false
    private(set) var lastRefreshDuration: TimeInterval = 0
    /// 每次查询结果更新时递增，供舞台判断是否需要重载。
    private(set) var revision: Int = 0

    var filter: LibraryFilter = .all

    /// 保险箱内资产的 localIdentifier；查询时排除，避免和系统相簿重复。
    var excludedLocalIDs: Set<String> = []

    let authorization = AuthorizationService()
    let thumbnails = ThumbnailProvider()

    @ObservationIgnored private var changeObserver: PhotoLibraryChangeObserver?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    // MARK: - 生命周期

    func start() async {
        accessState = authorization.currentState()
        guard accessState.canBrowse else { return }
        registerChangeObserverIfNeeded()
        await refresh()
    }

    func requestAccess() async {
        accessState = await authorization.requestAccess()
        guard accessState.canBrowse else { return }
        registerChangeObserverIfNeeded()
        await refresh()
    }

    func refresh(activeFilter: LibraryFilter? = nil) async {
        guard accessState.canBrowse else {
            items = []
            return
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        isLoading = true
        defer { isLoading = false }

        let effectiveFilter = activeFilter ?? filter
        let result = fetchResult(for: effectiveFilter)

        var fetched: [PhotoItem] = []
        fetched.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetched.append(PhotoItem(asset: asset))
        }

        if !excludedLocalIDs.isEmpty {
            fetched.removeAll { excludedLocalIDs.contains($0.id) }
        }

        items = fetched
        revision += 1
        lastRefreshDuration = CFAbsoluteTimeGetCurrent() - startedAt
    }

    func setFilter(_ newFilter: LibraryFilter) async {
        filter = newFilter
        await refresh(activeFilter: newFilter)
    }

    /// 任务快照：按当前排序取前 `limit` 张，排除保险箱资产。
    func taskItems(albumLocalID: String?, limit: Int) -> [PhotoItem] {
        guard accessState.canBrowse, limit > 0 else { return [] }

        var taskFilter = LibraryFilter.all
        taskFilter.albumLocalID = albumLocalID
        let result = fetchResult(for: taskFilter)
        let excluded = excludedLocalIDs

        var fetched: [PhotoItem] = []
        fetched.reserveCapacity(min(limit, result.count))
        result.enumerateObjects { asset, _, stop in
            if fetched.count >= limit {
                stop.pointee = true
                return
            }
            guard !excluded.contains(asset.localIdentifier) else { return }
            fetched.append(PhotoItem(asset: asset))
        }
        return fetched
    }

    /// 未归类任务快照：照常按创建时间倒序取前 `limit` 张，
    /// 跳过任一用户相簿里的资产（集合由 `AlbumService` 在后台算好）。
    func uncategorizedTaskItems(skipping classifiedIDs: Set<String>, limit: Int) -> [PhotoItem] {
        guard accessState.canBrowse, limit > 0 else { return [] }

        let result = fetchResult(for: .all)
        let excluded = excludedLocalIDs

        var fetched: [PhotoItem] = []
        fetched.reserveCapacity(min(limit, result.count))
        result.enumerateObjects { asset, _, stop in
            if fetched.count >= limit {
                stop.pointee = true
                return
            }
            let id = asset.localIdentifier
            guard !classifiedIDs.contains(id), !excluded.contains(id) else { return }
            fetched.append(PhotoItem(asset: asset))
        }
        return fetched
    }

    /// 按给定顺序还原资产；系统里已不存在的资产会被跳过。
    static func items(for assetIDs: [String]) -> [PhotoItem] {
        guard !assetIDs.isEmpty else { return [] }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var map: [String: PhotoItem] = [:]
        map.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            map[asset.localIdentifier] = PhotoItem(asset: asset)
        }
        return assetIDs.compactMap { map[$0] }
    }

    /// 删除并刷新；整批一次 performChanges，系统只确认一次。
    @discardableResult
    func delete(localIDs: [String]) async throws -> DeleteOutcome {
        let outcome = try await DeleteService.delete(localIDs: localIDs)
        await refresh()
        return outcome
    }

    // MARK: - 查询

    #if DEBUG
    /// 模拟器回归用：没有相簿权限时也允许进入工作区，
    /// 舞台数据由 `HomeView` 的合成任务提供。
    func debugForceAuthorized() {
        accessState = .authorized
    }
    #endif

    private func fetchResult(for filter: LibraryFilter) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 尊重系统隐藏；保险箱资产另行排除。
        options.predicate = NSPredicate(format: "isHidden == NO")

        if let albumID = filter.albumLocalID,
           let collection = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [albumID],
               options: nil
           ).firstObject {
            return PHAsset.fetchAssets(in: collection, options: options)
        }

        return PHAsset.fetchAssets(with: options)
    }

    // MARK: - 变更观察

    private func registerChangeObserverIfNeeded() {
        guard changeObserver == nil else { return }
        let observer = PhotoLibraryChangeObserver { [weak self] in
            self?.scheduleRefreshAfterChange()
        }
        PHPhotoLibrary.shared().register(observer)
        changeObserver = observer
    }

    private func scheduleRefreshAfterChange() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - 授权辅助

    func openSettings() {
        authorization.openSettings()
    }

    func manageLimitedAccess() {
        authorization.presentLimitedLibraryPicker()
    }
}
