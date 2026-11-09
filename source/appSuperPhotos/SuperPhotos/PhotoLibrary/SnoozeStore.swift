import Foundation
import Observation

/// 一条延后记录：资产 id + 到期时间。
struct SnoozeRecord: Identifiable, Hashable, Sendable {
    let id: String
    let until: Date
}

/// 延后存储：assetID → 到期时间，写 UserDefaults，重启后仍生效。
/// 到期项在被读取或定时清理时移除，照片自动回到处理流。
@MainActor
@Observable
final class SnoozeStore {
    private enum Keys {
        static let expiries = "snooze.expiries"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private(set) var expiries: [String: Date] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: Keys.expiries),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            self.expiries = decoded
        } else {
            self.expiries = [:]
        }
        purgeExpired()
    }

    // MARK: - 读取

    var count: Int { expiries.count }

    var activeIDs: Set<String> { Set(expiries.keys) }

    /// 按到期时间升序，最先回到舞台的排在前面。
    var records: [SnoozeRecord] {
        expiries
            .map { SnoozeRecord(id: $0.key, until: $0.value) }
            .sorted { $0.until < $1.until }
    }

    func isSnoozed(_ id: String, now: Date = .now) -> Bool {
        guard let until = expiries[id] else { return false }
        return until > now
    }

    /// 剩余天数（向上取整，至少 1 天）。
    func remainingDays(for record: SnoozeRecord, now: Date = .now) -> Int {
        let seconds = record.until.timeIntervalSince(now)
        let days = Int(ceil(seconds / 86_400))
        return max(1, days)
    }

    // MARK: - 写入

    func snooze(id: String, days: Int, now: Date = .now) {
        let clamped = min(SnoozePolicy.maxDays, max(SnoozePolicy.minDays, days))
        let until = calendar.date(byAdding: .day, value: clamped, to: now) ?? now
        expiries[id] = until
    }

    func unsnooze(id: String) {
        expiries.removeValue(forKey: id)
    }

    func wakeAll() {
        expiries.removeAll()
    }

    /// 移除已到期项；返回是否有变化。
    @discardableResult
    func purgeExpired(now: Date = .now) -> Bool {
        let expired = expiries.filter { $0.value <= now }.map(\.key)
        guard !expired.isEmpty else { return false }
        for id in expired {
            expiries.removeValue(forKey: id)
        }
        return true
    }

    // MARK: - 持久化

    private func persist() {
        guard let data = try? JSONEncoder().encode(expiries) else { return }
        defaults.set(data, forKey: Keys.expiries)
    }
}
