import Photos
import UIKit

/// 缩略图加载与预热；舞台、抽屉与预览统一走这里。
@MainActor
final class ThumbnailProvider {
    private let manager = PHCachingImageManager()
    private var prefetchingIDs: [String] = []
    private var prefetchTargetSize: CGSize = .zero
    /// 已解码缩略图的内存缓存：滚动/切卡时同步命中，避免每次重建视图都先闪一帧占位。
    private let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 160
        return cache
    }()

    /// 请求单张缩略图；允许网络访问以支持 iCloud 资产。
    func image(for localID: String, targetSize: CGSize) async -> UIImage? {
        let key = Self.cacheKey(localID: localID, targetSize: targetSize)
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let asset = Self.asset(for: localID) else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let size = CGSize(
            width: max(targetSize.width, 1),
            height: max(targetSize.height, 1)
        )

        return await withCheckedContinuation { continuation in
            var didResume = false
            manager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                guard !didResume else { return }
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if cancelled { return }
                // 只接受最终质量；低清占位由 SwiftUI 的背景色兜底。
                guard !degraded else { return }
                didResume = true
                if let image {
                    self.imageCache.setObject(image, forKey: key)
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func cacheKey(localID: String, targetSize: CGSize) -> NSString {
        "\(localID)@\(Int(targetSize.width.rounded()))x\(Int(targetSize.height.rounded()))" as NSString
    }

    /// 按舞台尺寸预热前后几页。
    func startPrefetching(ids: [String], targetSize: CGSize) {
        guard !ids.isEmpty else { return }
        if ids == prefetchingIDs && targetSize == prefetchTargetSize { return }
        stopPrefetching()

        let assets = Self.assets(for: ids)
        guard !assets.isEmpty else { return }
        manager.startCachingImages(
            for: assets,
            targetSize: normalized(targetSize),
            contentMode: .aspectFill,
            options: prefetchOptions()
        )
        prefetchingIDs = ids
        prefetchTargetSize = targetSize
    }

    func stopPrefetching() {
        guard !prefetchingIDs.isEmpty else { return }
        let assets = Self.assets(for: prefetchingIDs)
        manager.stopCachingImages(
            for: assets,
            targetSize: normalized(prefetchTargetSize),
            contentMode: .aspectFill,
            options: nil
        )
        prefetchingIDs = []
        prefetchTargetSize = .zero
    }

    private func prefetchOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    private func normalized(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    private static func asset(for localID: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject
    }

    private static func assets(for localIDs: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
}
