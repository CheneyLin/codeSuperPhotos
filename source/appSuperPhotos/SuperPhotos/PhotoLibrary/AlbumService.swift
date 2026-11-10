import Photos

struct AlbumItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case all
        case smart
        case user
    }

    let id: String
    let title: String
    let kind: Kind
    let count: Int
    let symbolName: String
}

enum AlbumEditError: LocalizedError {
    case albumMissing
    case assetsMissing
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .albumMissing: "目标相簿已不存在，请在右侧重新选择"
        case .assetsMissing: "照片已不在相簿中"
        case .notAuthorized: "需要相簿读写权限才能加入收藏夹"
        }
    }
}

/// 相簿与计数：抽屉 / Regular 右列的唯一数据来源。
@MainActor
@Observable
final class AlbumService {
    private(set) var allPhotoCount = 0
    private(set) var smartAlbums: [AlbumItem] = []
    private(set) var userAlbums: [AlbumItem] = []
    private(set) var isLoading = false

    /// 不在任何「用户自建相簿」里的可见照片数。
    /// 系统智能相簿与「最近项目」不算归类：它们无法被用户移出，
    /// 计入会让结果恒为 0。
    private(set) var uncategorizedCount = 0
    /// 首次计算完成前为 true，弹窗显示「计算中…」而不是 0。
    private(set) var isCountingUncategorized = false
    /// 已归入任一用户相簿的资产；未归类取图时直接跳过。
    private(set) var classifiedLocalIDs: Set<String> = []

    /// 保险箱资产不计入「未归类」；只影响这一项，不改动相簿原有计数。
    var excludedLocalIDs: Set<String> = []

    private var hasLoaded = false
    private var hasCountedUncategorized = false
    private var needsUncategorizedRecount = false

    /// 弹窗展示用：首次计算完成前为 nil（显示「计算中…」），
    /// 之后的刷新期间沿用上一次结果，避免数字闪烁。
    var uncategorizedDisplayCount: Int? {
        hasCountedUncategorized ? uncategorizedCount : nil
    }

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if hasLoaded && !force { return }
        isLoading = true
        defer { isLoading = false }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "isHidden == NO")

        allPhotoCount = PHAsset.fetchAssets(with: options).count

        smartAlbums = Self.smartDescriptors.compactMap { descriptor in
            guard let collection = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: descriptor.subtype,
                options: nil
            ).firstObject else { return nil }

            let count = PHAsset.fetchAssets(in: collection, options: options).count
            guard count > 0 else { return nil }

            return AlbumItem(
                id: collection.localIdentifier,
                title: descriptor.title,
                kind: .smart,
                count: count,
                symbolName: descriptor.symbolName
            )
        }

        var users: [AlbumItem] = []
        let userResult = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        userResult.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: options).count
            // 空相簿也要保留：右侧收藏夹允许把照片存进刚建好的空相簿。
            users.append(
                AlbumItem(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "未命名相簿",
                    kind: .user,
                    count: count,
                    symbolName: "folder"
                )
            )
        }
        userAlbums = users.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        hasLoaded = true
        await refreshUncategorized()
    }

    /// 重算「未归类照片」。
    ///
    /// - 差集在主线程外完成，启动期不占首帧。
    /// - 扫描期间又收到变更请求时只记一个标记，本轮结束后再合并重算一次，
    ///   不会并发跑多份全集遍历。
    /// - 新结果落盘前保留上一次的数字，弹窗不会闪 0。
    func refreshUncategorized() async {
        if isCountingUncategorized {
            needsUncategorizedRecount = true
            return
        }
        isCountingUncategorized = true
        repeat {
            needsUncategorizedRecount = false
            let excluded = excludedLocalIDs
            let result = await Task.detached(priority: .utility) {
                Self.computeUncategorized(excluding: excluded)
            }.value
            classifiedLocalIDs = result.classifiedIDs
            uncategorizedCount = result.count
            hasCountedUncategorized = true
        } while needsUncategorizedRecount
        isCountingUncategorized = false
    }

    /// 未归类判定：可见照片全集 − 用户自建相簿成员 − 保险箱资产。
    /// 智能相簿（收藏 / 视频 / 截图…）与「最近项目」不参与扣减。
    nonisolated private static func computeUncategorized(
        excluding excluded: Set<String>
    ) -> UncategorizedResult {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "isHidden == NO")

        let all = PHAsset.fetchAssets(with: options)
        var remaining = Set<String>()
        remaining.reserveCapacity(all.count)
        all.enumerateObjects { asset, _, _ in
            remaining.insert(asset.localIdentifier)
        }
        if !excluded.isEmpty { remaining.subtract(excluded) }

        var classified: Set<String> = []
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        collections.enumerateObjects { collection, _, _ in
            guard !remaining.isEmpty else { return }
            PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                if remaining.remove(id) != nil {
                    classified.insert(id)
                }
            }
        }

        return UncategorizedResult(
            classifiedIDs: classified,
            count: remaining.count
        )
    }

    private struct UncategorizedResult: Sendable {
        let classifiedIDs: Set<String>
        let count: Int
    }

    /// 把照片加入用户相簿（不复制、不删除，只建立归属）。
    func addAssets(_ localIDs: [String], toAlbum albumID: String) async throws {
        guard !localIDs.isEmpty else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw AlbumEditError.notAuthorized
        }
        guard let album = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumID],
            options: nil
        ).firstObject else {
            throw AlbumEditError.albumMissing
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        guard assets.count > 0 else { throw AlbumEditError.assetsMissing }

        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            request.addAssets(assets)
        }
    }

    private struct SmartDescriptor {
        let subtype: PHAssetCollectionSubtype
        let title: String
        let symbolName: String
    }

    private static let smartDescriptors: [SmartDescriptor] = [
        .init(subtype: .smartAlbumFavorites, title: "收藏", symbolName: "heart"),
        .init(subtype: .smartAlbumVideos, title: "视频", symbolName: "video"),
        .init(subtype: .smartAlbumLivePhotos, title: "实况照片", symbolName: "livephoto"),
        .init(subtype: .smartAlbumScreenshots, title: "截图", symbolName: "camera.viewfinder"),
        .init(subtype: .smartAlbumPanoramas, title: "全景照片", symbolName: "pano")
    ]
}
