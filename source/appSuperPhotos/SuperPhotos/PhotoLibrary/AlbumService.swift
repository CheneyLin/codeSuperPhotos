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

    private var hasLoaded = false

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
