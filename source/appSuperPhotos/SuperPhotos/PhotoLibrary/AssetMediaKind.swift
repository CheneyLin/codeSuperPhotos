import Photos

extension MediaKind {
    /// 从 PHAsset 归类到界面使用的 6 种类型。
    static func from(asset: PHAsset) -> MediaKind {
        guard asset.mediaType == .image else {
            return asset.mediaType == .video ? .video : .photo
        }

        if asset.mediaSubtypes.contains(.photoLive) { return .livePhoto }
        if asset.playbackStyle == .imageAnimated { return .animated }
        if asset.mediaSubtypes.contains(.photoPanorama) { return .panorama }
        if asset.mediaSubtypes.contains(.photoScreenshot) { return .screenshot }
        return .photo
    }
}

extension PhotoItem {
    init(asset: PHAsset) {
        self.init(
            id: asset.localIdentifier,
            kind: .from(asset: asset),
            pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
            duration: asset.duration,
            createdAt: asset.creationDate,
            isHidden: asset.isHidden
        )
    }
}
