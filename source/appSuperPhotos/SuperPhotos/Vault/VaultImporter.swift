import Foundation
import Photos

enum VaultImportError: LocalizedError {
    case missingResource
    case diskInsufficient
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "找不到可复制的原始资源".localized
        case .diskInsufficient:
            return "剩余磁盘空间不足，请先清理后再试".localized
        case .writeFailed(let detail):
            return "写入保险箱失败：%@".localized(detail)
        }
    }
}

/// 入库第一步：把 PhotoKit 的原始资源复制到沙盒。
/// 只负责“复制”，删除原件与清单写入由 `VaultStore` 统一编排。
enum VaultImporter {
    struct CopyResult {
        let fileName: String
        let relativePath: String
        let pairedVideoPath: String?
        let byteSize: Int64
        let albumNames: [String]
    }

    static func copy(asset: PHAsset, kind: MediaKind) async throws -> CopyResult {
        let available = Paths.availableCapacity()
        guard available == 0 || available > VaultLimits.diskSafetyMargin else {
            throw VaultImportError.diskInsufficient
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = primaryResource(in: resources, kind: kind) else {
            throw VaultImportError.missingResource
        }

        Paths.ensureVaultDirectory()
        Paths.applyVaultDirectoryAttributes()

        let fileName = primary.originalFilename
        let relativePath = Paths.makeRelativePath(fileName: fileName)
        let destination = Paths.vaultFileURL(relativePath: relativePath)

        do {
            try await write(resource: primary, to: destination)
            Paths.applyVaultFileAttributes(to: destination)
        } catch {
            Paths.removeFile(atRelativePath: relativePath)
            throw VaultImportError.writeFailed(error.localizedDescription)
        }

        var byteSize = Paths.fileSize(atRelativePath: relativePath)
        var pairedRelativePath: String?

        if kind == .livePhoto,
           let paired = pairedVideoResource(in: resources) {
            let pairedRelative = Paths.makeRelativePath(fileName: paired.originalFilename)
            let pairedURL = Paths.vaultFileURL(relativePath: pairedRelative)
            do {
                try await write(resource: paired, to: pairedURL)
                Paths.applyVaultFileAttributes(to: pairedURL)
                byteSize += Paths.fileSize(atRelativePath: pairedRelative)
                pairedRelativePath = pairedRelative
            } catch {
                Paths.removeFile(atRelativePath: relativePath)
                Paths.removeFile(atRelativePath: pairedRelative)
                throw VaultImportError.writeFailed(error.localizedDescription)
            }
        }

        return CopyResult(
            fileName: fileName,
            relativePath: relativePath,
            pairedVideoPath: pairedRelativePath,
            byteSize: byteSize,
            albumNames: albumTitles(for: asset)
        )
    }

    // MARK: - 资源选择

    private static func primaryResource(in resources: [PHAssetResource], kind: MediaKind) -> PHAssetResource? {
        if kind == .video {
            return resources.first { $0.type == .fullSizeVideo }
                ?? resources.first { $0.type == .video }
        }
        return resources.first { $0.type == .photo }
            ?? resources.first { $0.type == .fullSizePhoto }
    }

    private static func pairedVideoResource(in resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { $0.type == .pairedVideo }
            ?? resources.first { $0.type == .fullSizePairedVideo }
    }

    /// 只记录用户相簿，不记录智能相簿，便于取出时按名称加回。
    private static func albumTitles(for asset: PHAsset) -> [String] {
        var titles: [String] = []
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        collections.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle, !titles.contains(title) else { return }
            titles.append(title)
        }
        return titles
    }

    // MARK: - 写入

    private static func write(resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
