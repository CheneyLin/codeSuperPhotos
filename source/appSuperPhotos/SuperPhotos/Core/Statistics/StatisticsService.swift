import Foundation
import Observation
import Photos
import SwiftData

/// 统计的唯一写入入口。记录与聚合都在主线程；字节采样在后台读取 PhotoKit 资源。
@MainActor
@Observable
final class StatisticsService {
    private let container: ModelContainer
    private let context: ModelContext
    private var calendar: Calendar
    private let defaults: UserDefaults
    /// 每次写入递增，供观察者刷新聚合结果。
    private(set) var revision = 0

    /// 会话内浏览去重；同一资产同一天只计一次。
    @ObservationIgnored private var browsedKeys: Set<String> = []
    private static let browsedDefaultsPrefix = "stats.browsed."

    init(
        container: ModelContainer? = nil,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        let resolved = container ?? AppModelContainer.shared
        self.container = resolved
        self.context = resolved.mainContext
        self.calendar = calendar
        self.defaults = defaults
        compactIfNeeded()
    }

    // MARK: - 写入

    func recordBrowse(id: String, at date: Date = Date()) {
        let row = dayRow(for: date)
        let dedupeKey = "\(row.key)|\(id)"
        if browsedKeys.contains(dedupeKey) { return }

        // 跨启动也要保证“唯一资产”：按天把已浏览资产 ID 存到 UserDefaults。
        var persisted = Set(defaults.stringArray(forKey: Self.browsedDefaultsPrefix + row.key) ?? [])
        browsedKeys.insert(dedupeKey)
        guard !persisted.contains(id) else { return }
        persisted.insert(id)
        defaults.set(Array(persisted), forKey: Self.browsedDefaultsPrefix + row.key)

        row.browsed += 1
        save()
    }

    func recordDestroy(count: Int, sample: ByteSample, machine: MachineKind, at date: Date = Date()) {
        guard count > 0 else { return }
        let row = dayRow(for: date)
        row.destroyed += count
        row.destroyedBytes += max(sample.bytes, 0)
        row.bytesUnknown += max(sample.unknownCount, 0)
        switch machine {
        case .fireplace: row.fireplace += count
        case .shredder: row.shredder += count
        }
        save()
    }

    func recordImport(count: Int, at date: Date = Date()) {
        guard count > 0 else { return }
        let row = dayRow(for: date)
        row.imported += count
        save()
    }

    func recordRestore(count: Int, at date: Date = Date()) {
        guard count > 0 else { return }
        let row = dayRow(for: date)
        row.restored += count
        save()
    }

    func reset() {
        let rows = (try? context.fetch(FetchDescriptor<DayStat>())) ?? []
        for row in rows { context.delete(row) }
        browsedKeys.removeAll()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.browsedDefaultsPrefix) {
            defaults.removeObject(forKey: key)
        }
        save()
    }

    // MARK: - 聚合

    func summary(for period: StatPeriod, now: Date = Date()) -> StatSummary {
        _ = revision
        let rows = (try? context.fetch(FetchDescriptor<DayStat>())) ?? []
        let interval = dateInterval(for: period, now: now)
        var summary = StatSummary()
        for row in rows {
            if let interval, !interval.contains(row.dayStart) { continue }
            summary.merge(row)
        }
        return summary
    }

    /// 连续整理天数：销毁、入库或取出均算整理；今天还没整理时从昨天起算。
    func streak(now: Date = Date()) -> Int {
        _ = revision
        let rows = (try? context.fetch(FetchDescriptor<DayStat>())) ?? []
        let activeDays = Set(
            rows
                .filter { $0.destroyed + $0.imported + $0.restored > 0 }
                .map { calendar.startOfDay(for: $0.dayStart) }
        )
        guard !activeDays.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !activeDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while activeDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    // MARK: - 字节采样

    /// 销毁前读取本地资源大小；iCloud 未下载或读取失败计为未知。
    /// 只累加字节数，不保留数据，避免大视频占内存。
    nonisolated static func sampleBytes(localIDs: [String]) async -> ByteSample {
        guard !localIDs.isEmpty else { return ByteSample() }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return ByteSample() }

        var plans: [(assetID: String, resources: [PHAssetResource])] = []
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset).filter {
                $0.type == .photo || $0.type == .video || $0.type == .pairedVideo
            }
            plans.append((asset.localIdentifier, resources))
        }

        let totalResources = plans.reduce(0) { $0 + $1.resources.count }
        guard totalResources > 0 else {
            return ByteSample(
                bytes: 0,
                unknownCount: assets.count,
                bytesByID: [:],
                unknownIDs: Set(plans.map(\.assetID))
            )
        }

        return await withCheckedContinuation { continuation in
            let state = SampleState(
                assetIDs: plans.map(\.assetID),
                totalResources: totalResources,
                continuation: continuation
            )

            for plan in plans {
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = false

                for resource in plan.resources {
                    let counter = ByteCounter()
                    PHAssetResourceManager.default().requestData(
                        for: resource,
                        options: options,
                        dataReceivedHandler: { data in
                            counter.add(data.count)
                        },
                        completionHandler: { error in
                            state.finishResource(
                                assetID: plan.assetID,
                                bytes: error == nil ? counter.value : 0
                            )
                        }
                    )
                }
            }
        }
    }

    // MARK: - 内部

    private func dayRow(for date: Date) -> DayStat {
        let key = DayStat.makeKey(granularity: .day, date: date)
        let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let row = DayStat(
            granularity: .day,
            dayStart: calendar.startOfDay(for: date),
            key: key
        )
        context.insert(row)
        return row
    }

    private func dateInterval(for period: StatPeriod, now: Date) -> DateInterval? {
        switch period {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        case .all:
            return nil
        }
    }

    private func save() {
        try? context.save()
        revision += 1
    }

    /// 90 天前的日行并入月行，避免长期使用后行数膨胀。
    private func compactIfNeeded(now: Date = Date()) {
        guard let cutoff = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now)) else {
            return
        }
        let descriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.granularityRaw == "day" })
        guard let days = try? context.fetch(descriptor), !days.isEmpty else { return }

        var changed = false
        for row in days where row.dayStart < cutoff {
            let monthStart = calendar.dateInterval(of: .month, for: row.dayStart)?.start ?? row.dayStart
            let monthKey = DayStat.makeKey(granularity: .month, date: monthStart)
            let monthDescriptor = FetchDescriptor<DayStat>(predicate: #Predicate { $0.key == monthKey })
            let target: DayStat
            if let existing = try? context.fetch(monthDescriptor).first {
                target = existing
            } else {
                target = DayStat(granularity: .month, dayStart: monthStart, key: monthKey)
                context.insert(target)
            }
            target.add(row)
            context.delete(row)
            changed = true
        }
        if changed { save() }
    }
}

// MARK: - 采样并发状态

/// PhotoKit 回调来自任意队列，用锁保护累计值。
private final class SampleState: @unchecked Sendable {
    private let lock = NSLock()
    private let assetIDs: [String]
    private let totalResources: Int
    private var completedResources = 0
    private var bytesByAsset: [String: Int64] = [:]
    private let continuation: CheckedContinuation<ByteSample, Never>

    init(
        assetIDs: [String],
        totalResources: Int,
        continuation: CheckedContinuation<ByteSample, Never>
    ) {
        self.assetIDs = assetIDs
        self.totalResources = totalResources
        self.continuation = continuation
    }

    func finishResource(assetID: String, bytes: Int64) {
        lock.lock()
        completedResources += 1
        bytesByAsset[assetID, default: 0] += max(bytes, 0)
        let isLast = completedResources >= totalResources
        let bytes = bytesByAsset.values.reduce(0, +)
        let unknownIDs = Set(assetIDs.filter { (bytesByAsset[$0] ?? 0) == 0 })
        lock.unlock()

        guard isLast else { return }
        continuation.resume(returning: ByteSample(
            bytes: bytes,
            unknownCount: unknownIDs.count,
            bytesByID: bytesByAsset,
            unknownIDs: unknownIDs
        ))
    }
}

private final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total: Int64 = 0

    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return total
    }

    func add(_ count: Int) {
        lock.lock()
        total += Int64(max(count, 0))
        lock.unlock()
    }
}

#if DEBUG
extension StatisticsService {
    /// 三组固定样本：今日两行（合并）、100 天前一行（应并入月行）。
    /// 期望值：今日 5 件 / 50MB / 1 未知；累计 9 件 / 60MB / 3 未知。
    func seedSelfCheckSamples() {
        reset()
        let today = calendar.startOfDay(for: Date())
        let mb: Int64 = 1024 * 1024

        applySample(
            dayStart: today,
            browsed: 5, destroyed: 3, bytes: 30 * mb, unknown: 1,
            imported: 2, restored: 1, fireplace: 2, shredder: 1
        )
        applySample(
            dayStart: today,
            browsed: 3, destroyed: 2, bytes: 20 * mb, unknown: 0,
            imported: 0, restored: 0, fireplace: 0, shredder: 2
        )
        if let old = calendar.date(byAdding: .day, value: -100, to: today) {
            applySample(
                dayStart: old,
                browsed: 0, destroyed: 4, bytes: 10 * mb, unknown: 2,
                imported: 1, restored: 0, fireplace: 1, shredder: 3
            )
        }
        compactIfNeeded()
    }

    func selfCheckReport() -> String {
        let today = summary(for: .today)
        let all = summary(for: .all)
        let pass = today.destroyed == 5
            && today.destroyedBytes == 50 * 1024 * 1024
            && today.bytesUnknown == 1
            && all.destroyed == 9
            && all.destroyedBytes == 60 * 1024 * 1024
            && all.bytesUnknown == 3
            && all.imported == 3
            && all.restored == 1
            && all.browsed == 8

        return "统计自检 \(pass ? "PASS" : "FAIL")｜今日 \(today.destroyed)件/\(today.readableDestroyedBytes)/未知\(today.bytesUnknown)｜累计 \(all.destroyed)件/\(all.readableDestroyedBytes)/未知\(all.bytesUnknown)｜入库\(all.imported) 取出\(all.restored) 浏览\(all.browsed)"
    }

    private func applySample(
        dayStart: Date,
        browsed: Int,
        destroyed: Int,
        bytes: Int64,
        unknown: Int,
        imported: Int,
        restored: Int,
        fireplace: Int,
        shredder: Int
    ) {
        let row = dayRow(for: dayStart)
        row.browsed += browsed
        row.destroyed += destroyed
        row.destroyedBytes += bytes
        row.bytesUnknown += unknown
        row.imported += imported
        row.restored += restored
        row.fireplace += fireplace
        row.shredder += shredder
        save()
    }
}
#endif
