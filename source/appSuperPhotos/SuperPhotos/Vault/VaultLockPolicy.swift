import Foundation

/// 锁定状态：失败次数 + 截止时间 + 30 分钟窗口内的失败时间点。
struct VaultLockStatus: Codable, Equatable {
    var failures: Int = 0
    var lockUntil: Date?
    var recentFailures: [Date] = []

    func isLocked(now: Date = Date()) -> Bool {
        guard let lockUntil else { return false }
        return lockUntil > now
    }

    func remainingSeconds(now: Date = Date()) -> Int {
        guard let lockUntil, lockUntil > now else { return 0 }
        return max(0, Int(lockUntil.timeIntervalSince(now).rounded(.up)))
    }

    static let empty = VaultLockStatus()
}

/// 阶梯锁定策略，状态存 Keychain，杀进程不重置。
enum VaultLockPolicy {
    private static let account = "lockState"
    private static let recentWindow: TimeInterval = 30 * 60

    static func status(now: Date = Date()) -> VaultLockStatus {
        guard let data = KeychainStore.data(service: VaultCredentials.service, account: account),
              var stored = try? JSONDecoder().decode(VaultLockStatus.self, from: data) else {
            return .empty
        }
        stored.recentFailures = pruned(stored.recentFailures, now: now)
        return stored
    }

    static func isLocked(now: Date = Date()) -> Bool {
        status(now: now).isLocked(now: now)
    }

    static func remainingSeconds(now: Date = Date()) -> Int {
        status(now: now).remainingSeconds(now: now)
    }

    /// 记录一次失败，返回更新后的状态（含本轮处罚）。
    @discardableResult
    static func registerFailure(now: Date = Date()) -> VaultLockStatus {
        var stored = status(now: now)
        stored.failures += 1
        stored.recentFailures = pruned(stored.recentFailures, now: now) + [now]

        if let duration = lockDuration(
            failures: stored.failures,
            recentCount: stored.recentFailures.count
        ) {
            stored.lockUntil = now.addingTimeInterval(duration)
        } else {
            stored.lockUntil = nil
        }

        persist(stored)
        return stored
    }

    static func registerSuccess() {
        persist(.empty)
    }

    static func reset() {
        KeychainStore.delete(service: VaultCredentials.service, account: account)
    }

    static func lockDuration(failures: Int, recentCount: Int) -> TimeInterval? {
        if recentCount >= 10 { return 30 * 60 }
        guard failures >= 5 else { return nil }
        let exponent = failures - 5
        let seconds = 60 * pow(2, Double(exponent))
        return min(seconds, 900)
    }

    // MARK: - 内部

    private static func pruned(_ dates: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-recentWindow)
        return dates.filter { $0 > cutoff }
    }

    private static func persist(_ status: VaultLockStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? KeychainStore.set(data, service: VaultCredentials.service, account: account)
    }
}
