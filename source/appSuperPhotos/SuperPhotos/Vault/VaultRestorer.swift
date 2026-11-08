import Foundation
import Photos

enum VaultRestoreError: LocalizedError {
    case missingFile
    case writeFailed(String)
    case assetMissing

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "保险箱文件缺失，无法取出"
        case .writeFailed(let detail):
            return "重建资产失败：\(detail)"
        case .assetMissing:
            return "重建后的资产找不到"
        }
    }
}

/// 取出：原件已在入库时删除，因此一律用 `PHAssetCreationRequest` 重建。
enum VaultRestorer {
    static func restore(_ record: VaultRecord) async throws {
        let primaryURL = Paths.vaultFileURL(relativePath: record.relativePath)
        guard FileManager.default.fileExists(atPath: primaryURL.path) else {
            throw VaultRestoreError.missingFile
        }

        var createdLocalID: String?

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = record.capturedAt

                let options = PHAssetResourceCreationOptions()
                options.originalFilename = record.fileName

                if record.mediaKind == .video {
                    request.addResource(with: .video, fileURL: primaryURL, options: options)
                } else {
                    request.addResource(with: .photo, fileURL: primaryURL, options: options)

                    if let pairedPath = record.pairedVideoPath {
                        let pairedURL = Paths.vaultFileURL(relativePath: pairedPath)
                        if FileManager.default.fileExists(atPath: pairedURL.path) {
                            let pairedOptions = PHAssetResourceCreationOptions()
                            pairedOptions.originalFilename = pairedFileName(for: record.fileName)
                            request.addResource(with: .pairedVideo, fileURL: pairedURL, options: pairedOptions)
                        }
                    }
                }

                createdLocalID = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw VaultRestoreError.writeFailed(error.localizedDescription)
        }

        guard let createdLocalID else { throw VaultRestoreError.assetMissing }
        await addToAlbumsIfPossible(localID: createdLocalID, titles: record.albumNames)
    }

    // MARK: - 相簿回填

    private static func addToAlbumsIfPossible(localID: String, titles: [String]) async {
        guard !titles.isEmpty else { return }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject else {
            return
        }

        let collections = matchingAlbums(titles: titles)
        guard !collections.isEmpty else { return }

        try? await PHPhotoLibrary.shared().performChanges {
            for collection in collections {
                PHAssetCollectionChangeRequest(for: collection)?.addAssets([asset] as NSArray)
            }
        }
    }

    private static func matchingAlbums(titles: [String]) -> [PHAssetCollection] {
        let fetched = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var result: [PHAssetCollection] = []
        fetched.enumerateObjects { collection, _, _ in
            guard let title = collection.localizedTitle, titles.contains(title) else { return }
            result.append(collection)
        }
        return result
    }

    private static func pairedFileName(for fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return base + ".mov"
    }
}
