import CryptoKit
import Foundation

enum VaultCryptoError: LocalizedError {
    case keyUnavailable
    case fileMissing
    case malformedFile
    case authenticationFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .keyUnavailable: "内容密钥不可用".localized
        case .fileMissing: "保险箱文件不存在".localized
        case .malformedFile: "文件格式无法识别".localized
        case .authenticationFailed: "文件校验失败，可能已损坏".localized
        case .writeFailed: "写入文件失败".localized
        }
    }
}

/// 读取旧版本创建的 AES-GCM 文件。
enum VaultCrypto {
    private static let keychainService = "com.gpwzw.appSuperPhotos.vault"
    private static let keychainAccount = "content.key"

    private static let magic = Data([0x53, 0x50, 0x56, 0x31]) // "SPV1"
    private static let chunkSize = 4 * 1024 * 1024

    /// 按文件头识别旧版本加密文件。
    static func isEncryptedFile(at url: URL) -> Bool {
        guard let input = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? input.close() }
        guard let header = try? input.read(upToCount: magic.count) else { return false }
        return header == magic
    }

    /// 取出旧版本加密文件所需的本机内容密钥。
    static func contentKey() throws -> SymmetricKey {
        if let data = KeychainStore.data(service: keychainService, account: keychainAccount),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        throw VaultCryptoError.keyUnavailable
    }

    // MARK: - 文件解密

    /// 解密到指定目标文件；失败时删除半成品，不留下可被误读的部分明文。
    static func decryptFile(at url: URL, to destination: URL, key: SymmetricKey) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultCryptoError.fileMissing
        }

        guard let input = try? FileHandle(forReadingFrom: url) else {
            throw VaultCryptoError.fileMissing
        }
        defer { try? input.close() }

        let headerLength = 4 + 1 + 3 + 4 + 12
        guard let header = try input.read(upToCount: headerLength),
              header.count == headerLength,
              header.prefix(4) == magic else {
            throw VaultCryptoError.malformedFile
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: destination) else {
            throw VaultCryptoError.writeFailed
        }

        do {
            var index: UInt32 = 0
            while true {
                guard let lengthData = try input.read(upToCount: 4), lengthData.count == 4 else {
                    break
                }
                let length = lengthData.withUnsafeBytes {
                    UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
                }
                // combined = 12 字节 nonce + 密文 + 16 字节认证标签。
                guard length > 28, length <= UInt32(chunkSize + 28) else {
                    throw VaultCryptoError.malformedFile
                }
                guard let combined = try input.read(upToCount: Int(length)),
                      combined.count == Int(length) else {
                    throw VaultCryptoError.malformedFile
                }

                let box = try AES.GCM.SealedBox(combined: combined)
                let plaintext: Data
                do {
                    plaintext = try AES.GCM.open(
                        box,
                        using: key,
                        authenticating: aad(index: index)
                    )
                } catch {
                    throw VaultCryptoError.authenticationFailed
                }
                try output.write(contentsOf: plaintext)
                index += 1
            }

            try output.synchronize()
            try output.close()
            Paths.applyVaultFileAttributes(to: destination)
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    // MARK: - 内部

    private static func aad(index: UInt32) -> Data {
        var data = magic
        data.append(contentsOf: bigEndianBytes(index))
        return data
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
