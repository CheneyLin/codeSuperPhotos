import Foundation

/// 任务内一张照片的最终去向。
enum TaskDecision: String, Codable, Sendable {
    case keep
    case snooze
    case vault
    case destroy
}

/// 一次整理任务的快照；全部字段可持久化，供中断后续跑。
struct CleaningTaskSnapshot: Codable, Equatable, Sendable {
    var albumLocalID: String?
    var albumTitle: String
    var assetIDs: [String]
    var kinds: [String: String]
    var decisions: [String: TaskDecision]
    var startedAt: Date
    /// 本批开始时的每批张数；进度分母与恢复都以它为准，不随设置改动。
    var batchSize: Int
    /// 决策写入顺序（旧 → 新）；撤销只回退最后一条。
    var decisionOrder: [String]

    func count(of decision: TaskDecision) -> Int {
        decisions.values.filter { $0 == decision }.count
    }
}

enum TaskPolicy {
    /// 一次任务最多处理的张数（默认值来源）。
    static let batchSize = 100
    /// 设置项：每批张数，范围 10–200、步长 10。
    static let batchSizeKey = "task.batchSize"
    static let batchSizeRange = 10...200
    static let batchSizeStep = 10

    /// 新建批次时读取的用户设置；未设置或越界时回落到默认值 / 合法区间。
    static var configuredBatchSize: Int {
        let stored = UserDefaults.standard.object(forKey: batchSizeKey) as? Int
        return clampedBatchSize(stored ?? batchSize)
    }

    static func clampedBatchSize(_ value: Int) -> Int {
        min(max(value, batchSizeRange.lowerBound), batchSizeRange.upperBound)
    }

    // 任务结束统一执行时不再分批：本批有多少张就一次提交，系统只弹一次确认。
    // 旧的 10 张中途执行阈值 `BatchPolicy.autoConfirmThreshold` 仍保留在
    // BatchPolicy 中供其它模块引用，但不再参与任务结算。
}

/// 任务式整理的状态与持久化。
/// 只有“已决定”的照片才计入进度；保险箱 / 废纸篓在任务结束前不执行任何不可逆操作。
@MainActor
@Observable
final class CleaningTaskStore {
    private enum Keys {
        static let current = "task.current"
    }

    private(set) var snapshot: CleaningTaskSnapshot?
    /// 当前任务的完整照片序列（按快照顺序还原，已删除的资产会被跳过）。
    private(set) var items: [PhotoItem] = []

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshot = Self.loadSnapshot(from: defaults)
    }

    // MARK: - 状态

    var isActive: Bool { snapshot != nil }
    var albumTitle: String { snapshot?.albumTitle ?? "" }
    var assetIDs: [String] { snapshot?.assetIDs ?? [] }
    var totalCount: Int { snapshot?.assetIDs.count ?? 0 }
    var processedCount: Int { snapshot?.decisions.count ?? 0 }
    /// 本批的每批张数：进行中只认快照记录的值，不跟随设置变化。
    var batchSize: Int { snapshot?.batchSize ?? TaskPolicy.configuredBatchSize }
    /// 是否还有可撤销的一步；最后一张决策后、结算执行前仍允许回退。
    var canUndo: Bool {
        isActive && !(snapshot?.decisionOrder.isEmpty ?? true)
    }

    var isFinished: Bool {
        isActive && totalCount > 0 && processedCount >= totalCount
    }

    /// 还没有决定去向的照片，按原顺序排列；舞台只展示这些。
    var remainingItems: [PhotoItem] {
        guard let snapshot else { return [] }
        return items.filter { snapshot.decisions[$0.id] == nil }
    }

    var keepCount: Int { snapshot?.count(of: .keep) ?? 0 }
    var snoozeCount: Int { snapshot?.count(of: .snooze) ?? 0 }
    var destroyCount: Int { snapshot?.count(of: .destroy) ?? 0 }

    var vaultIDs: [String] { ids(with: .vault) }
    var destroyIDs: [String] { ids(with: .destroy) }

    func kinds(for ids: [String]) -> [String: MediaKind] {
        guard let snapshot else { return [:] }
        var result: [String: MediaKind] = [:]
        for id in ids {
            guard let raw = snapshot.kinds[id],
                  let kind = MediaKind(rawValue: raw) else { continue }
            result[id] = kind
        }
        return result
    }

    // MARK: - 变更

    /// 开始新任务；返回是否成功（空相簿不会创建任务）。
    @discardableResult
    func start(
        albumLocalID: String?,
        albumTitle: String,
        items: [PhotoItem],
        batchSize: Int
    ) -> Bool {
        guard !items.isEmpty else { return false }

        var kinds: [String: String] = [:]
        kinds.reserveCapacity(items.count)
        for item in items {
            kinds[item.id] = item.kind.rawValue
        }

        snapshot = CleaningTaskSnapshot(
            albumLocalID: albumLocalID,
            albumTitle: albumTitle,
            assetIDs: items.map(\.id),
            kinds: kinds,
            decisions: [:],
            startedAt: Date(),
            batchSize: batchSize,
            decisionOrder: []
        )
        self.items = items
        persist()
        return true
    }

    /// 记录一张的最终去向；重复记录会被忽略。
    func record(id: String, decision: TaskDecision) {
        guard var snapshot,
              snapshot.assetIDs.contains(id),
              snapshot.decisions[id] == nil else { return }
        snapshot.decisions[id] = decision
        snapshot.decisionOrder.append(id)
        self.snapshot = snapshot
        persist()
    }

    /// 撤销最近一条决策：退回舞台并恢复计数。
    /// 返回被撤回的照片 id 与去向；没有可撤销项时返回 nil。
    @discardableResult
    func undoLastDecision() -> (id: String, decision: TaskDecision)? {
        guard var snapshot,
              let id = snapshot.decisionOrder.last,
              let decision = snapshot.decisions[id] else { return nil }

        snapshot.decisionOrder.removeLast()
        snapshot.decisions.removeValue(forKey: id)
        self.snapshot = snapshot
        persist()
        return (id, decision)
    }

    /// 启动时按快照顺序还原照片；系统里已不存在的资产会从任务中剔除。
    func restore(from restoredItems: [PhotoItem]) {
        guard var snapshot else { return }

        let existingIDs = Set(restoredItems.map(\.id))
        let keptIDs = snapshot.assetIDs.filter { existingIDs.contains($0) }
        let removed = snapshot.assetIDs.count - keptIDs.count

        if removed > 0 {
            snapshot.assetIDs = keptIDs
            snapshot.kinds = snapshot.kinds.filter { existingIDs.contains($0.key) }
            snapshot.decisions = snapshot.decisions.filter { existingIDs.contains($0.key) }
            snapshot.decisionOrder = snapshot.decisionOrder.filter { existingIDs.contains($0) }
            self.snapshot = snapshot
        }

        // 恢复也以快照记录的批次上限为准：中途把设置调大，不会给本批扩容。
        items = Array(restoredItems.prefix(snapshot.batchSize))

        if items.isEmpty {
            reset()
            return
        }
        persist()
    }

    func reset() {
        snapshot = nil
        items = []
        defaults.removeObject(forKey: Keys.current)
    }

    // MARK: - 内部

    private func ids(with decision: TaskDecision) -> [String] {
        guard let snapshot else { return [] }
        return snapshot.assetIDs.filter { snapshot.decisions[$0] == decision }
    }

    private func persist() {
        guard let snapshot else {
            defaults.removeObject(forKey: Keys.current)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Keys.current)
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> CleaningTaskSnapshot? {
        guard let data = defaults.data(forKey: Keys.current) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CleaningTaskSnapshot.self, from: data)
    }
}
