import Foundation

enum EntitlementTier: String, CaseIterable, Codable, Sendable, Identifiable {
    case free
    case vip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free: "免费版"
        case .vip: "VIP"
        }
    }
}

/// 权益来源。唯一来源为 StoreKit 2 的真实交易（一次性购买 / 恢复购买）。
enum EntitlementSource: String, Codable, Sendable {
    case storeKit
}

/// 非消耗型商品一次购买永久有效，因此快照里没有到期日、周期或续订状态。
struct EntitlementSnapshot: Equatable, Sendable {
    var tier: EntitlementTier
    var source: EntitlementSource

    static let free = EntitlementSnapshot(tier: .free, source: .storeKit)

    static func storeKit(tier: EntitlementTier) -> EntitlementSnapshot {
        EntitlementSnapshot(tier: tier, source: .storeKit)
    }
}
