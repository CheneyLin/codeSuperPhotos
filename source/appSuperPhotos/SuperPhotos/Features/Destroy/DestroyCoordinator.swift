import Foundation
import UIKit

/// 销毁编排：吸附 → 蓄力 → 系统确认 → 动画 → 结果。
/// 严格串行，保证同一时间只有一批在执行。
@MainActor
@Observable
final class DestroyCoordinator {
    private(set) var phase: DestroyPhase = .idle
    private(set) var progress: Double = 0
    private(set) var machine: MachineKind = .wasteBasket
    private(set) var tickets: [DestroyTicket] = []
    /// 本次批量销毁的张数，蓄力阶段由界面读取。
    private(set) var pendingCount = 0
    private(set) var lastOutcome: DestroyOutcome?

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var isCancellationRequested = false

    // MARK: - 队列

    /// 加入队列；返回实际接受的条数。超出批量上限的部分被忽略。
    @discardableResult
    func enqueue(ids: [String], kinds: [String: MediaKind], limit: Int) -> Int {
        let existing = Set(tickets.map(\.id))
        var accepted = 0

        for id in ids where !existing.contains(id) {
            guard tickets.count < limit else { break }
            tickets.append(DestroyTicket(id: id, kind: kinds[id] ?? .photo))
            accepted += 1
        }
        return accepted
    }

    func clearQueue() {
        guard !phase.isBusy else { return }
        tickets.removeAll()
        progress = 0
        phase = .idle
    }

    /// 切换道具；销毁流程进行中拒绝切换，返回值告诉调用方是否真的生效，
    /// 避免设置项与界面显示分叉。
    @discardableResult
    func switchMachine(_ kind: MachineKind) -> Bool {
        guard !phase.isBusy else { return false }
        machine = kind
        return true
    }

    // MARK: - 执行

    /// 开始销毁队列。`delete` 必须一次提交整批（一次 performChanges）。
    func start(delete: @escaping @MainActor ([String]) async throws -> Void) {
        guard !phase.isBusy, !tickets.isEmpty else { return }
        startMachineAnimationClock()
        runTask = Task { [weak self] in
            await self?.run(delete: delete)
        }
    }

    func cancel() {
        guard phase.canCancel else { return }
        isCancellationRequested = true
        runTask?.cancel()

        lastOutcome = DestroyOutcome(
            machine: machine,
            succeededIDs: [],
            failedIDs: tickets.map(\.id),
            wasCancelled: true
        )
    }

    // MARK: - 内部时序

    private func run(delete: @escaping @MainActor ([String]) async throws -> Void) async {
        isCancellationRequested = false
        let ids = tickets.map(\.id)
        pendingCount = ids.count

        // T0：吸附
        phase = .armed
        progress = 0
        await sleep(milliseconds: 200)
        guard !Task.isCancelled, !isCancellationRequested else { return eject() }

        // 蓄力 1.2s，唯一的后悔窗口
        phase = .charging
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        await charge()
        guard !Task.isCancelled, !isCancellationRequested else { return eject() }

        // 系统确认
        phase = .awaitingSystemConfirm
        do {
            try await delete(ids)
        } catch {
            eject()
            lastOutcome = DestroyOutcome(
                machine: machine,
                succeededIDs: [],
                failedIDs: ids,
                wasCancelled: true
            )
            return
        }

        // 销毁动画
        phase = .destroying
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await sleep(seconds: machine.destroyDuration)

        let outcome = DestroyOutcome(
            machine: machine,
            succeededIDs: ids,
            failedIDs: [],
            wasCancelled: false
        )
        lastOutcome = outcome
        phase = .finished
        tickets.removeAll()
        progress = 0
        pendingCount = 0

        await sleep(milliseconds: 300)
        if phase == .finished { phase = .idle }
    }

    private func charge() async {
        let total: TimeInterval = 1.2
        let step: TimeInterval = 0.05
        let steps = Int(total / step)

        for index in 1...steps {
            guard !Task.isCancelled, !isCancellationRequested else { return }
            progress = Double(index) / Double(steps)
            try? await Task.sleep(for: .milliseconds(Int(step * 1000)))
            if index == steps / 2 {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }

    private func eject() {
        runTask = nil
        phase = .ejecting
        progress = 0
        UINotificationFeedbackGenerator().notificationOccurred(.error)

        // 退件是纯视觉：延迟回 idle，队列保留供重试。
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.phase == .ejecting else { return }
            self.phase = .idle
        }
    }

    private func startMachineAnimationClock() {
        // 目前所有动画由 phase + progress 驱动，无需额外时钟；保留入口以便后续接音效。
    }

    private func sleep(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
