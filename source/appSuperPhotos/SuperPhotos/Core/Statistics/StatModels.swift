import Foundation
import SwiftData

/// 统计行粒度。超过 90 天的日行会并入月行，控制行数。
enum StatGranularity: String, Sendable {
    case day
    case month
}

/// 已浏览按唯一资产计；已销毁按机器计；字节数只统计能读到的本地资源。
@Model
final class DayStat {
    /// "day:2026-11-08" / "month:2026-11"，唯一约束保证同一粒度只有一行。
    @Attribute(.unique) var key: String
    var granularityRaw: String
    var dayStart: Date

    var browsed: Int
    var destroyed: Int
    var destroyedBytes: Int64
    /// 取不到本地资源大小的销毁件数（iCloud 未下载等）。
    var bytesUnknown: Int
    var imported: Int
    var restored: Int
    var fireplace: Int
    var shredder: Int

    init(
        granularity: StatGranularity,
        dayStart: Date,
        key: String? = nil,
        browsed: Int = 0,
        destroyed: Int = 0,
        destroyedBytes: Int64 = 0,
        bytesUnknown: Int = 0,
        imported: Int = 0,
        restored: Int = 0,
        fireplace: Int = 0,
        shredder: Int = 0
    ) {
        self.granularityRaw = granularity.rawValue
        self.dayStart = dayStart
        self.key = key ?? Self.makeKey(granularity: granularity, date: dayStart)
        self.browsed = browsed
        self.destroyed = destroyed
        self.destroyedBytes = destroyedBytes
        self.bytesUnknown = bytesUnknown
        self.imported = imported
        self.restored = restored
        self.fireplace = fireplace
        self.shredder = shredder
    }

    var granularity: StatGranularity {
        StatGranularity(rawValue: granularityRaw) ?? .day
    }

    func add(_ other: DayStat) {
        browsed += other.browsed
        destroyed += other.destroyed
        destroyedBytes += other.destroyedBytes
        bytesUnknown += other.bytesUnknown
        imported += other.imported
        restored += other.restored
        fireplace += other.fireplace
        shredder += other.shredder
    }

    static func makeKey(granularity: StatGranularity, date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        switch granularity {
        case .day:
            return String(format: "day:%04d-%02d-%02d", year, month, day)
        case .month:
            return String(format: "month:%04d-%02d", year, month)
        }
    }
}

enum StatPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .week: "本周"
        case .month: "本月"
        case .all: "累计"
        }
    }

    /// 一期免费只到今日/本周/累计；本月与方式偏好归 VIP。
    var requiresVIP: Bool { self == .month }
}

/// 聚合结果；`destroyedBytes` 只含可读到的本地资源。
struct StatSummary: Equatable, Sendable {
    var browsed = 0
    var destroyed = 0
    var destroyedBytes: Int64 = 0
    var bytesUnknown = 0
    var imported = 0
    var restored = 0
    var fireplace = 0
    var shredder = 0

    var isEmpty: Bool {
        browsed == 0 && destroyed == 0 && imported == 0 && restored == 0
    }

    var readableDestroyedBytes: String {
        destroyedBytes > 0 ? VaultLimits.readableBytes(destroyedBytes) : "—"
    }

    mutating func merge(_ row: DayStat) {
        browsed += row.browsed
        destroyed += row.destroyed
        destroyedBytes += row.destroyedBytes
        bytesUnknown += row.bytesUnknown
        imported += row.imported
        restored += row.restored
        fireplace += row.fireplace
        shredder += row.shredder
    }
}

/// 销毁前采样的字节结果。
struct ByteSample: Equatable, Sendable {
    var bytes: Int64 = 0
    var unknownCount: Int = 0
    var bytesByID: [String: Int64] = [:]
    var unknownIDs: Set<String> = []

    /// 只保留实际删除成功的资产，避免部分失败时高估释放空间。
    func scoped(to ids: [String]) -> ByteSample {
        guard !bytesByID.isEmpty || !unknownIDs.isEmpty else { return self }
        let idSet = Set(ids)
        let scopedBytes = bytesByID
            .filter { idSet.contains($0.key) }
            .values
            .reduce(0, +)
        let scopedUnknown = unknownIDs.intersection(idSet).count
        return ByteSample(bytes: scopedBytes, unknownCount: scopedUnknown)
    }
}
