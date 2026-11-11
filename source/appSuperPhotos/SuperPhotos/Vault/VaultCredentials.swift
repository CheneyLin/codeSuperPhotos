import CommonCrypto
import Foundation
import Security

/// 保险箱凭据：PBKDF2-SHA256(120,000 次) 派生验证值，只存验证值与盐。
/// 组合 `L=07|R=23` 只在内存中出现，不写 UserDefaults、不打日志。
enum VaultCredentials {
    static let service = "dev.superphotos.vault"
    /// 左盘刻度：0...29（30 档）。
    static let leftDialCount = 30
    static let leftMaxDialValue = leftDialCount - 1
    /// 右盘刻度：0...59（60 档）。
    static let rightDialCount = 60
    static let rightMaxDialValue = rightDialCount - 1
    /// 组合空间：30 × 60 = 1800 种。
    static var combinationSpace: Int { leftDialCount * rightDialCount }
    private static let account = "credentials"
    nonisolated private static let iterations: UInt32 = 120_000
    nonisolated private static let keyLength = 32
    nonisolated private static let saltLength = 32

    struct Payload: Codable {
        var version: Int
        var salt: Data
        var verifier: Data
    }

    struct VerificationMaterial: Sendable {
        let salt: Data
        let verifier: Data
    }

    static var isConfigured: Bool {
        loadPayload() != nil
    }

    /// 组合归一化：`L=07|R=23`。
    nonisolated static func normalized(a: Int, b: Int) -> String {
        String(format: "L=%02d|R=%02d", a, b)
    }

    static func setPassword(a: Int, b: Int) throws {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw KeychainStore.Error.status(status)
        }

        let verifier = derive(password: normalized(a: a, b: b), salt: salt)
        let payload = Payload(version: 1, salt: salt, verifier: verifier)
        let data = try JSONEncoder().encode(payload)
        try KeychainStore.set(data, service: service, account: account)
    }

    static func verify(a: Int, b: Int) -> Bool {
        guard let payload = loadPayload() else { return false }
        return matches(a: a, b: b, salt: payload.salt, verifier: payload.verifier)
    }

    /// 供后台线程使用：材料在主线程读出，计算在后台完成。
    static func verificationMaterial() -> VerificationMaterial? {
        guard let payload = loadPayload() else { return nil }
        return VerificationMaterial(salt: payload.salt, verifier: payload.verifier)
    }

    nonisolated static func matches(a: Int, b: Int, salt: Data, verifier: Data) -> Bool {
        let candidate = derive(password: normalized(a: a, b: b), salt: salt)
        return KeychainStore.constantTimeEquals(candidate, verifier)
    }

    /// 旧组合正确时才写入新组合。
    static func changePassword(oldA: Int, oldB: Int, newA: Int, newB: Int) -> Bool {
        guard verify(a: oldA, b: oldB) else { return false }
        try? setPassword(a: newA, b: newB)
        return true
    }

    static func resetAll() {
        KeychainStore.delete(service: service, account: account)
    }

    /// 随机生成一组组合，供设置页的“随机组合”提示使用。
    static func randomCombination() -> (a: Int, b: Int) {
        (Int.random(in: 0...leftMaxDialValue), Int.random(in: 0...rightMaxDialValue))
    }

    #if DEBUG
    static func debugSetPassword(a: Int, b: Int) {
        try? setPassword(a: a, b: b)
    }

    static func debugReset() {
        resetAll()
    }
    #endif

    // MARK: - 内部

    private static func loadPayload() -> Payload? {
        guard let data = KeychainStore.data(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    nonisolated private static func derive(password: String, salt: Data) -> Data {
        let passwordData = Data(password.utf8)
        var derived = Data(count: keyLength)

        let status = derived.withUnsafeMutableBytes { derivedBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordData.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { return Data() }
        return derived
    }
}
