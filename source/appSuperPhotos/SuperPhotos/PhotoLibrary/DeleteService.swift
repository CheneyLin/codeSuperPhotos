import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case emptySelection
    case deleteCancelled
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "没有可删除的照片"
        case .deleteCancelled:
            return "已取消删除"
        case .deleteFailed(let detail):
            return "删除失败：\(detail)"
        }
    }
}

/// 一次删除的结果：区分“确实删掉”和“早就不在相册里”的资产。
/// 后者的存在（例如任务进行中被其它 App 删除）不应让整批提交失败。
struct DeleteOutcome: Sendable, Equatable {
    var deletedIDs: [String] = []
    var missingIDs: [String] = []

    var handledCount: Int { deletedIDs.count + missingIDs.count }
}

/// 删除写入：一次 performChanges 只弹一次系统确认。
/// 整批提交（不分批），单张资产缺失会被提前剔除，不会拖垮整批。
enum DeleteService {
    @discardableResult
    static func delete(localIDs: [String]) async throws -> DeleteOutcome {
        var seen = Set<String>()
        let uniqueIDs = localIDs.filter { seen.insert($0).inserted }
        guard !uniqueIDs.isEmpty else { throw PhotoLibraryError.emptySelection }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: uniqueIDs, options: nil)
        var assetList: [PHAsset] = []
        assetList.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in assetList.append(asset) }

        // 已被其它途径删除的资产直接记为已处理，不进入删除请求。
        var outcome = DeleteOutcome()
        let existingIDs = Set(assetList.map(\.localIdentifier))
        outcome.missingIDs = uniqueIDs.filter { !existingIDs.contains($0) }

        guard !assetList.isEmpty else { return outcome }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            if isUserCancelled(error) {
                throw PhotoLibraryError.deleteCancelled
            }
            throw PhotoLibraryError.deleteFailed(error.localizedDescription)
        }

        outcome.deletedIDs = assetList.map(\.localIdentifier)
        return outcome
    }

    /// 识别系统确认框里的“取消”。
    /// PhotoKit 在用户取消时以 PHPhotosError.userCancelled 抛出；不同系统版本也可能
    /// 以 NSError 或底层错误抛出，因此逐层判断。
    static func isUserCancelled(_ error: Error) -> Bool {
        if let photosError = error as? PHPhotosError,
           photosError.code == .userCancelled {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.Code.userCancelled.rawValue {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           isUserCancelled(underlying) {
            return true
        }

        let description = nsError.localizedDescription.lowercased()
        return description.contains("cancel") || description.contains("取消")
    }
}
