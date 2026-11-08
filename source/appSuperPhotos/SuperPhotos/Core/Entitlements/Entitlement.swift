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

/// 权益来源。一期只有 mock；二期由 StoreKit 2 提供真实来源。
enum EntitlementSource: String, Codable, Sendable {
    case mock
    case storeKit
    case promotional
}

struct EntitlementSnapshot: Equatable, Sendable {
    var tier: EntitlementTier
    var source: EntitlementSource
    var isMock: Bool

    static func mock(tier: EntitlementTier) -> EntitlementSnapshot {
        EntitlementSnapshot(tier: tier, source: .mock, isMock: true)
    }
}
