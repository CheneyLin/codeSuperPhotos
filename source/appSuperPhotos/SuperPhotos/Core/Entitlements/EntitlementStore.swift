import Foundation
import Observation

/// 权益的唯一判定入口。
/// 一期来源为 mock（设置页开关），二期替换为 StoreKit 2 的 `Transaction.currentEntitlements`，
/// 调用点（入库、批量、统计、设置）不需要改动。
@MainActor
@Observable
final class EntitlementStore {
    private enum Keys {
        static let mockTier = "entitlement.mockTier"
    }

    private let defaults: UserDefaults
    private(set) var snapshot: EntitlementSnapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTier = defaults.string(forKey: Keys.mockTier).flatMap(EntitlementTier.init(rawValue:))
        self.snapshot = .mock(tier: storedTier ?? .free)
    }

    var tier: EntitlementTier { snapshot.tier }
    var isVIP: Bool { tier == .vip }

    /// 测试用：切换模拟档位并持久化，重启后保持。
    func setVIP(_ enabled: Bool) {
        let tier: EntitlementTier = enabled ? .vip : .free
        defaults.set(tier.rawValue, forKey: Keys.mockTier)
        snapshot = .mock(tier: tier)
    }

    /// 二期接 StoreKit 后由真实交易结果写入。
    func apply(_ newSnapshot: EntitlementSnapshot) {
        snapshot = newSnapshot
    }

    func isEnabled(_ feature: Feature) -> Bool {
        tier == .vip || feature.minimumTier == .free
    }

    /// 入库前的统一门禁：媒体类型 + 容量。
    func canImport(
        kind: MediaKind,
        byteSize: Int64,
        usedItems: Int,
        usedBytes: Int64
    ) -> GateResult {
        let media = VaultLimits.mediaGate(for: kind, tier: tier)
        guard media.isAllowed else { return media }

        return VaultLimits.quotaGate(
            usedItems: usedItems,
            usedBytes: usedBytes,
            additionalItems: 1,
            additionalBytes: max(byteSize, 0),
            tier: tier
        )
    }

    func quotaStatus(usedItems: Int, usedBytes: Int64) -> GateResult {
        VaultLimits.quotaGate(
            usedItems: usedItems,
            usedBytes: usedBytes,
            additionalItems: 0,
            tier: tier
        )
    }

    /// nil 表示不限。
    func remainingItemCount(usedItems: Int) -> Int? {
        guard tier == .free else { return nil }
        return max(VaultLimits.freeItemLimit - usedItems, 0)
    }

    /// nil 表示不限。
    func remainingBytes(usedBytes: Int64) -> Int64? {
        guard tier == .free else { return nil }
        return max(VaultLimits.freeByteLimit - usedBytes, 0)
    }
}
