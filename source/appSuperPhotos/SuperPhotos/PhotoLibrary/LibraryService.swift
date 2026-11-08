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
            let item = PhotoItem(asset: asset)
            if effectiveFilter.mediaKind == nil || item.kind == effectiveFilter.mediaKind {
                fetched.append(item)
            }
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

    /// 删除并刷新；系统确认由 performChanges 触发一次。
    func delete(localIDs: [String]) async throws {
        try await DeleteService.delete(localIDs: localIDs)
        await refresh()
    }

    // MARK: - 查询

    private func fetchResult(for filter: LibraryFilter) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 尊重系统隐藏；保险箱资产另行排除。
        options.predicate = NSPredicate(format: "isHidden == NO")

        if let mediaKind = filter.mediaKind {
            switch mediaKind {
            case .video:
                options.predicate = NSPredicate(format: "isHidden == NO AND mediaType == %d", PHAssetMediaType.video.rawValue)
            case .photo, .livePhoto, .screenshot, .panorama, .animated:
                options.predicate = NSPredicate(format: "isHidden == NO AND mediaType == %d", PHAssetMediaType.image.rawValue)
            }
        }

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
