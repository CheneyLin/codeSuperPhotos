import Foundation
import Photos

/// 相册变更监听：任意线程回调 → 主线程去抖 → 交给 LibraryService。
final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let handler: @MainActor @Sendable () -> Void

    init(handler: @escaping @MainActor @Sendable () -> Void) {
        self.handler = handler
        super.init()
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            handler()
        }
    }
}
