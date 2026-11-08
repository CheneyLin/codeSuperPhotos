import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case emptySelection
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "没有可删除的照片"
        case .deleteFailed(let detail):
            return "删除失败：\(detail)"
        }
    }
}

/// 删除写入：一次 performChanges 只弹一次系统确认。
enum DeleteService {
    static func delete(localIDs: [String]) async throws {
        guard !localIDs.isEmpty else { throw PhotoLibraryError.emptySelection }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        guard assets.count > 0 else { throw PhotoLibraryError.emptySelection }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            throw PhotoLibraryError.deleteFailed(error.localizedDescription)
        }
    }
}
