import Foundation

/// 保险箱的免费额度与门禁规则，集中在一处，避免散落在页面里。
enum VaultLimits {
    static let freeItemLimit = 60
    static let freeByteLimit: Int64 = 2 * 1024 * 1024 * 1024
    /// 入库前的磁盘安全余量（写副本还需要临时空间）。
    static let diskSafetyMargin: Int64 = 200 * 1024 * 1024

    static func mediaGate(for kind: MediaKind, tier: EntitlementTier) -> GateResult {
        guard tier == .free, !kind.isStillImage else { return .allowed }
        return .requiresVIP("\(kind.displayName)需要 VIP；免费版保险箱只支持静态图片")
    }

    static func quotaGate(
        usedItems: Int,
        usedBytes: Int64,
        additionalItems: Int = 1,
        additionalBytes: Int64 = 0,
        tier: EntitlementTier
    ) -> GateResult {
        guard tier == .free else { return .allowed }

        let projectedItems = usedItems + additionalItems
        if projectedItems > freeItemLimit {
            return .quotaExceeded("免费版保险箱最多 \(freeItemLimit) 件，当前已用 \(usedItems) 件")
        }

        let projectedBytes = usedBytes + additionalBytes
        if projectedBytes > freeByteLimit {
            return .quotaExceeded(
                "免费版保险箱最多 2GB，当前已用 \(readableBytes(usedBytes))"
            )
        }
        return .allowed
    }

    static func readableBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }
}
