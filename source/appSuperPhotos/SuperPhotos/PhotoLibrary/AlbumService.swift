import Photos

/// 一次「加入收藏夹」造成的相簿变更；撤销时据此把照片移出收藏夹并放回原处。
struct FavoriteMove: Codable, Equatable, Sendable {
    /// 移入的目标相簿。
    var targetAlbumID: String
    /// 移入前照片所属的用户自建相簿；撤销时按这份名单还原。
    var previousAlbumIDs: [String]?
}

/// 相簿写操作的串行队列。
///
/// 「移入收藏夹」与「撤销还原」都是对系统相簿的真实写操作，必须严格按提交顺序落地：
/// 如果还原先于移入执行，撤销看起来毫无效果，照片仍会留在收藏夹里。
/// 队列保证「先提交的写操作先完成」。
private actor AlbumWriteQueue {
    /// 当前队列尾；下一个写操作会等它结束再开始。
    private var tail: Task<Void, Never>?

    /// 把写操作排到队尾执行，并返回它的结果。
    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let handle = Task<T, Error> {
            if let previous {
                _ = await previous.result
            }
            return try await operation()
        }
        tail = Task { _ = await handle.result }
        return try await handle.value
    }
}

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
    /// 相簿封面（最新一张照片）的 localIdentifier；空相簿为 nil。
    /// 收藏夹选择器据此取 4:3 缩略图，其余相簿列表不消费这个字段。
    var coverLocalID: String? = nil
}

enum AlbumEditError: LocalizedError {
    case albumMissing
    case assetsMissing
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .albumMissing: "目标相簿已不存在，请在右侧重新选择".localized
        case .assetsMissing: "照片已不在相簿中".localized
        case .notAuthorized: "需要相簿读写权限才能加入收藏夹".localized
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

    /// 相簿写操作的串行队列；「移入收藏夹」与「撤销还原」都从这里排队，
    /// 保证还原一定发生在移入之后。
    private let writeQueue = AlbumWriteQueue()

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
                    title: collection.localizedTitle ?? "未命名相簿".localized,
                    kind: .user,
                    count: count,
                    symbolName: "folder",
                    // 封面取最新一张；空相簿保持 nil，选择器画占位底槽。
                    coverLocalID: Self.coverIdentifier(in: collection, predicate: options.predicate)
                )
            )
        }
        userAlbums = users.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

        hasLoaded = true
        await refreshUncategorized()
    }

    /// 相簿封面：按创建日期倒序取第一张可见照片，只回 ID 不解码图片。
    /// fetchLimit = 1，即使相簿里有几千张也只命中一行。
    private static func coverIdentifier(in collection: PHAssetCollection, predicate: NSPredicate?) -> String? {
        let options = PHFetchOptions()
        options.predicate = predicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(in: collection, options: options).firstObject?.localIdentifier
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
        try await writeQueue.run {
            try await Self._addAssets(localIDs, toAlbum: albumID)
        }
    }

    /// 把照片「移入」目标用户相簿：先从其它所有用户自建相簿里移除这些资产，
    /// 再加入目标相簿，确保它们在任意时刻只归属一个用户相簿。
    /// 系统智能相簿（收藏 / 视频 / 截图…）不参与清理，也无需清理。
    func moveAssets(_ localIDs: [String], toAlbum targetAlbumID: String) async throws {
        try await writeQueue.run {
            try await Self._moveAssets(localIDs, toAlbum: targetAlbumID)
        }
    }

    /// 加入收藏夹前，先同步采集「移入前照片所属的用户相簿」，
    /// 供撤销时还原。采集在移入「之前」完成，因此即便还原在移入仍未落地的
    /// 瞬间被触发，也能把照片正确送回原处。
    func favoriteMoveInfo(for localIDs: [String], targetAlbumID: String) -> FavoriteMove {
        FavoriteMove(
            targetAlbumID: targetAlbumID,
            previousAlbumIDs: Self.userAlbumMembership(for: localIDs)
        )
    }

    /// 走串行队列执行「加入收藏夹」的真实写操作（移入目标并清掉其它归属）。
    func performFavoriteMove(_ localIDs: [String], toAlbum targetAlbumID: String) async throws {
        try await writeQueue.run {
            try await Self._moveAssets(localIDs, toAlbum: targetAlbumID)
        }
    }

    /// 走串行队列撤销「加入收藏夹」：把照片移出目标相簿，并放回移入前所属的用户相簿。
    /// 由于经过同一串行队列，还原一定发生在「移入」之后，不会留下悬空归属。
    func revertFavoriteMove(_ move: FavoriteMove, assetIDs: [String]) async throws {
        try await writeQueue.run {
            try await Self._removeAssets(assetIDs, from: move.targetAlbumID)
            if let previous = move.previousAlbumIDs {
                for albumID in previous {
                    try await Self._addAssets(assetIDs, toAlbum: albumID)
                }
            }
        }
    }

    // MARK: - 非隔离写操作（只触碰 Photos 框架，不读写本类状态，可在写队列内并发调用）

    /// 采集每张资产当前所属的用户自建相簿（用于撤销还原）。
    nonisolated static func userAlbumMembership(for localIDs: [String]) -> [String] {
        guard !localIDs.isEmpty else { return [] }
        let predicate = NSPredicate(format: "localIdentifier IN %@", localIDs)
        var result: [String] = []
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        collections.enumerateObjects { collection, _, _ in
            let options = PHFetchOptions()
            options.predicate = predicate
            let contained = PHAsset.fetchAssets(in: collection, options: options)
            guard contained.count > 0 else { return }
            result.append(collection.localIdentifier)
        }
        return result
    }

    nonisolated static func _addAssets(_ localIDs: [String], toAlbum albumID: String) async throws {
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

    nonisolated static func _removeAssets(_ localIDs: [String], from albumID: String) async throws {
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
            request.removeAssets(assets)
        }
    }

    nonisolated static func _moveAssets(_ localIDs: [String], toAlbum targetAlbumID: String) async throws {
        guard !localIDs.isEmpty else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw AlbumEditError.notAuthorized
        }
        guard let target = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [targetAlbumID],
            options: nil
        ).firstObject else {
            throw AlbumEditError.albumMissing
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        guard assets.count > 0 else { throw AlbumEditError.assetsMissing }

        // 与 userAlbums 同口径：只处理用户自建相簿，跳过系统智能相簿。
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: nil
        )
        let matchPredicate = NSPredicate(format: "localIdentifier IN %@", localIDs)

        try await PHPhotoLibrary.shared().performChanges {
            // 1) 从其它用户相簿移除：只删本相簿里属于这批 localIDs 的资产。
            userAlbums.enumerateObjects { collection, _, _ in
                guard collection.localIdentifier != targetAlbumID else { return }
                let options = PHFetchOptions()
                options.predicate = matchPredicate
                let contained = PHAsset.fetchAssets(in: collection, options: options)
                guard contained.count > 0 else { return }
                guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
                request.removeAssets(contained)
            }
            // 2) 加入目标相簿（幂等：已在目标内不会重复加入）。
            guard let addRequest = PHAssetCollectionChangeRequest(for: target) else { return }
            addRequest.addAssets(assets)
        }
    }

    private struct SmartDescriptor {
        let subtype: PHAssetCollectionSubtype
        let title: String
        let symbolName: String
    }

    private static let smartDescriptors: [SmartDescriptor] = [
        .init(subtype: .smartAlbumFavorites, title: "收藏".localized, symbolName: "heart"),
        .init(subtype: .smartAlbumVideos, title: "视频".localized, symbolName: "video"),
        .init(subtype: .smartAlbumLivePhotos, title: "实况照片".localized, symbolName: "livephoto"),
        .init(subtype: .smartAlbumScreenshots, title: "截图".localized, symbolName: "camera.viewfinder"),
        .init(subtype: .smartAlbumPanoramas, title: "全景照片".localized, symbolName: "pano")
    ]
}
