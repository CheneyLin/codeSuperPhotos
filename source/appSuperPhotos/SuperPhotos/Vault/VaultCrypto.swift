import CryptoKit
import Foundation
import Security

/// 保险箱内容保护档位。
///
/// - `standard`：文件原样放在沙盒，只依赖 iOS 沙盒与系统文件保护（默认）。
/// - `strong`：应用层 AES-GCM 加密，密钥只存本机 Keychain。
///
/// 开发期不做兼容：切换档位只影响之后写入的文件，已有条目不再保证可读。
enum VaultEncryptionMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "标准"
        case .strong: "强加密"
        }
    }

    var detailText: String {
        switch self {
        case .standard:
            "文件以普通格式存放在 App 沙盒，受 iOS 沙盒与系统文件保护。App 密码只保护界面访问；开启 iCloud 同步后，此档内容会同步到你的 iCloud 私有数据库。"
        case .strong:
            "文件使用 AES-GCM 与仅存本机的 Keychain 内容密钥加密。App 密码仍只负责界面解锁；密钥不出本机，此档内容不参与 iCloud 同步。"
        }
    }

    static let defaultsKey = "vault.encryptionMode"

    static var current: VaultEncryptionMode {
        VaultEncryptionMode(
            rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        ) ?? .standard
    }
}

enum VaultCryptoError: LocalizedError {
    case keyUnavailable
    case fileMissing
    case malformedFile
    case authenticationFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .keyUnavailable: "内容密钥不可用"
        case .fileMissing: "保险箱文件不存在"
        case .malformedFile: "文件格式无法识别"
        case .authenticationFailed: "文件校验失败，可能已损坏"
        case .writeFailed: "写入文件失败"
        }
    }
}

/// 保险箱文件的内容保护。
///
/// 强加密使用分块 AES-GCM：每块 4 MB，各自带认证标签，
/// 避免为了加密/解密一段大视频把整个文件读进内存。
enum VaultCrypto {
    private static let keychainService = "com.gpwzw.appSuperPhotos.vault"
    private static let keychainAccount = "content.key"

    private static let magic = Data([0x53, 0x50, 0x56, 0x31]) // "SPV1"
    private static let version: UInt8 = 1
    private static let chunkSize = 4 * 1024 * 1024

    /// 按文件头识别强加密文件。同步层据此跳过密文，读取层据此决定是否解密，
    /// 不再依赖「当前选择的档位」这个全局状态。
    static func isEncryptedFile(at url: URL) -> Bool {
        guard let input = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? input.close() }
        guard let header = try? input.read(upToCount: magic.count) else { return false }
        return header == magic
    }

    /// 取出或生成内容密钥。只有强加密档会创建。
    static func contentKey(createIfNeeded: Bool = true) throws -> SymmetricKey {
        if let data = KeychainStore.data(service: keychainService, account: keychainAccount),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard createIfNeeded else { throw VaultCryptoError.keyUnavailable }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw VaultCryptoError.keyUnavailable }
        let data = Data(bytes)
        try KeychainStore.set(data, service: keychainService, account: keychainAccount)
        return SymmetricKey(data: data)
    }

    // MARK: - 文件加密

    /// 原地加密：先写临时文件，成功后原子替换原文件；失败时原文件保持不变。
    static func encryptFile(at url: URL, key: SymmetricKey) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultCryptoError.fileMissing
        }

        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(UUID().uuidString).enc")

        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        guard let input = try? FileHandle(forReadingFrom: url),
              let output = try? FileHandle(forWritingTo: temporaryURL) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw VaultCryptoError.writeFailed
        }
        defer {
            try? input.close()
            try? output.close()
        }

        do {
            var baseNonce = [UInt8](repeating: 0, count: 12)
            let status = SecRandomCopyBytes(kSecRandomDefault, baseNonce.count, &baseNonce)
            guard status == errSecSuccess else { throw VaultCryptoError.keyUnavailable }

            var header = magic
            header.append(version)
            header.append(contentsOf: [0, 0, 0])
            header.append(contentsOf: bigEndianBytes(UInt32(chunkSize)))
            header.append(contentsOf: baseNonce)
            try output.write(contentsOf: header)

            var index: UInt32 = 0
            while true {
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else {
                    break
                }
                let sealed = try AES.GCM.seal(
                    chunk,
                    using: key,
                    nonce: try nonce(base: baseNonce, index: index),
                    authenticating: aad(index: index)
                )
                guard let combined = sealed.combined else {
                    throw VaultCryptoError.writeFailed
                }
                var length = bigEndianBytes(UInt32(combined.count))
                length.append(contentsOf: combined)
                try output.write(contentsOf: length)
                index += 1
            }

            try output.synchronize()
            try output.close()
            try input.close()

            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            Paths.applyVaultFileAttributes(to: url)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
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

    private static func nonce(base: [UInt8], index: UInt32) throws -> AES.GCM.Nonce {
        var bytes = base
        bytes.replaceSubrange(8..<12, with: bigEndianBytes(index))
        return try AES.GCM.Nonce(data: bytes)
    }

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
