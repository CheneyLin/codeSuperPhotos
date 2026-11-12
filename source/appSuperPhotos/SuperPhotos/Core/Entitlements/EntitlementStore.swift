import Foundation
import Observation
import StoreKit

/// 权益的唯一判定入口 + 唯一计费点的 StoreKit 2 交易封装。
/// 计费点为**非消耗型**：一次购买永久解锁 VIP，无续订、无到期日。
/// 数据源只有真实交易（购买 / 恢复购买），不再有本地模拟开关；
/// 调用点（入库、批量、统计、设置）只依赖这里的判定，不感知交易细节。
@MainActor
@Observable
final class EntitlementStore {
    /// 唯一计费点（非消耗型 / 一次性购买）。需在 App Store Connect 中
    /// 把该 ID 配置为「非消耗型购买」，而不是自动续订订阅。
    static let vipProductID = "com.gpwzw.appSuperPhotos.vip"

    // MARK: - 权益快照

    private(set) var snapshot: EntitlementSnapshot = .free
    /// 成为 VIP 的起始日：本计费点所有已验证交易里最早的 `purchaseDate`。
    /// 不按 `revocationDate` 过滤——「不考虑中断」，中途退款后再购买也仍从最早算起。
    /// 只用于欢迎文案展示，不参与权益判定，也不落盘（每次按 StoreKit 交易重算）。
    private(set) var vipSince: Date?

    // MARK: - 交易状态（供 VIP 页展示）

    private(set) var product: Product?
    /// 商品被误配成订阅时置 true（应为非消耗型），供页面提示排查；正常情况恒为 false。
    private(set) var isProductTypeMismatch = false
    private(set) var isLoadingProduct = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// 一次性提示：购买 / 恢复结果或错误。页面展示后调用 clearNotice()。
    private(set) var notice: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    /// 购买成功后的后台一致性确认（只印证、不降级）。
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?
    /// 购买后的短暂保护窗口：此期间收据可能尚未同步，普通重算不得降级。
    /// 明确的退款 / 撤销由 handleUpdate 立即降级，不受窗口影响。
    @ObservationIgnored private var purchaseGraceUntil: Date?

    var tier: EntitlementTier { snapshot.tier }
    var isVIP: Bool { tier == .vip }

    /// 成为 VIP 的天数：按日历日计（跨时区 / 夏令时按本机日历对齐），
    /// 购买当天记 1 天，避免出现「已经 0 天啦」；nil 表示还没有可用交易日期。
    var vipDays: Int? {
        guard let vipSince else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: vipSince)
        let today = calendar.startOfDay(for: Date())
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        // 设备时间被回拨 / 收据日期异常时也不显示负数或 0。
        return max(1, elapsed + 1)
    }

    /// 仅由 StoreKit 交易结果写入，UI 不得直接改动权益。
    func apply(_ newSnapshot: EntitlementSnapshot) {
        snapshot = newSnapshot
    }

    // MARK: - StoreKit 2 生命周期

    /// App 启动时调用一次：加载商品、校验已购项目、常驻监听交易变化。
    /// 重复调用是安全的（监听只会启动一次）。
    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    await self.handleUpdate(result)
                }
            }
        }
        await loadProduct()
        await refreshEntitlements()
    }

    /// 拉取唯一计费点的商品信息（本地化名称与一次性价格）。
    func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [Self.vipProductID])
            let loaded = products.first
            product = loaded
            isProductTypeMismatch = loaded?.subscription != nil
            if loaded == nil {
                notice = "暂时无法获取会员商品，请检查网络或稍后重试。"
            }
        } catch {
            notice = "获取会员商品失败：\(error.localizedDescription)"
        }
    }

    /// 重算权益：购买、恢复、退款撤销都收敛到这里。
    /// `allowDowngrade: false` 只用于「刚购买成功」的后台确认——此时若收据尚未刷新，
    /// 不允许把已经凭本次已验证交易开通的 VIP 错误降回免费版。
    @discardableResult
    func refreshEntitlements(allowDowngrade: Bool = true) async -> Bool {
        let isActive = await hasVerifiedVIPTransaction()
        if isActive {
            purchaseGraceUntil = nil
            // 每次重算都从完整历史交易里核对最早购买日，回前台 / 重启后天数不会倒退。
            await refreshVIPSince()
        }

        let isProtected = purchaseGraceUntil.map { Date() < $0 } ?? false
        if isActive || (allowDowngrade && !isProtected) {
            apply(.storeKit(tier: isActive ? .vip : .free))
        } else if !isActive {
            log("重算未命中交易，但处于购买保护窗口内，保持 VIP 不降级")
        }
        return isActive
    }

    /// 非消耗型交易没有到期日，判定条件是「交易已验证 + 商品 ID 匹配 + 未被撤销」。
    /// 不缓存 VIP 到本地，退款 / 撤销后权益会立即回落。
    private func isUnlocked(_ transaction: Transaction) -> Bool {
        transaction.productID == Self.vipProductID
            && transaction.revocationDate == nil
    }

    /// 多来源交叉校验：
    /// 1. `Transaction.currentEntitlements`（首选，含当前有效的一次性购买）；
    /// 2. `Transaction.all`（回退，含已 finish 的历史交易）。
    /// Sandbox / 真机上刚完成的购买常有几秒收据同步延迟，此时第 1 路可能暂时查不到，
    /// 单靠它会出现「付款成功却判定为免费版」；非消耗型永久有效，用历史交易兜底是安全的。
    /// 退款后两条路径里的交易都会带 `revocationDate`，因此仍能正确回落。
    private func hasVerifiedVIPTransaction() async -> Bool {
        var seen: [String] = []
        var unverifiedCount = 0

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                seen.append(transaction.productID + (transaction.revocationDate == nil ? "" : "(已撤销)"))
                if isUnlocked(transaction) {
                    log("命中 currentEntitlements：\(transaction.productID)")
                    return true
                }
            case .unverified:
                unverifiedCount += 1
            @unknown default:
                break
            }
        }

        for await result in Transaction.all {
            if case .verified(let transaction) = result, isUnlocked(transaction) {
                log("命中 Transaction.all 历史交易：\(transaction.productID)")
                return true
            }
        }

        log("未命中有效交易：currentEntitlements=\(seen), 未验证=\(unverifiedCount), 期望=\(Self.vipProductID)")
        return false
    }

    /// 从 `Transaction.all` 取本计费点所有已验证交易里最早的 `purchaseDate`。
    /// 刻意不排除已撤销 / 已退款的交易：需求明确「不考虑中断」，
    /// 只要曾经购买过，计时起点就固定在最早那次，重复购买不会让天数归零。
    private func earliestVIPPurchaseDate() async -> Date? {
        var earliest: Date?
        for await result in Transaction.all {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.vipProductID else { continue }
            if let current = earliest {
                if transaction.purchaseDate < current { earliest = transaction.purchaseDate }
            } else {
                earliest = transaction.purchaseDate
            }
        }
        return earliest
    }

    private func refreshVIPSince() async {
        if let earliest = await earliestVIPPurchaseDate() {
            recordVIPStart(earliest)
        }
    }

    /// 只往前推、不后退：刚购买 / 交易更新时立刻用本次交易填充，
    /// 随后完整的 `Transaction.all` 校验若发现更早的历史购买会再往前修正。
    private func recordVIPStart(_ date: Date) {
        if let existing = vipSince {
            vipSince = min(existing, date)
        } else {
            vipSince = date
        }
    }

    /// 购买成功后延迟多轮印证，仅用于让本地快照与 StoreKit 收据最终一致，不会降级。
    private func scheduleConfirmation() {
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            for seconds in [0.8, 2.0, 4.0] {
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                if await self.refreshEntitlements(allowDowngrade: false) { return }
            }
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[Entitlements] \(message)")
        #endif
    }

    /// 购买唯一计费点（一次性）。结果以 StoreKit 交易为准，
    /// 成功后立即凭本次已验证交易开通，再由后台任务做收据一致性确认。
    func purchase() async {
        guard !isPurchasing, !isRestoring else { return }
        if product == nil { await loadProduct() }
        guard let product else { return }

        clearNotice()
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    notice = "交易未能通过校验，请联系 App Store 支持。"
                    return
                }
                await transaction.finish()

                guard isUnlocked(transaction) else {
                    notice = "购买已完成，但交易与 VIP 计费点不一致，请联系支持。"
                    await refreshEntitlements()
                    return
                }

                // 关键：本次交易已由 StoreKit 验证通过，立即开通，不等收据刷新。
                // 之前的做法只依赖 currentEntitlements 重算，Sandbox 下新交易可能
                // 延迟出现，会出现「付款成功仍显示免费版」。
                // 购买弹窗收起还会触发一次 scenePhase 回前台重算，故开 60 秒保护窗口。
                apply(.storeKit(tier: .vip))
                // 本次交易的购买日立即生效，欢迎语不用等收据同步完成。
                recordVIPStart(transaction.purchaseDate)
                purchaseGraceUntil = Date().addingTimeInterval(60)
                notice = "购买成功，VIP 已永久解锁。"
                scheduleConfirmation()
            case .userCancelled:
                break
            case .pending:
                notice = "购买正在等待处理（例如需要家长批准），完成后权益会自动开通。"
            @unknown default:
                break
            }
        } catch {
            notice = "购买未完成：\(error.localizedDescription)"
        }
    }

    /// 恢复购买：唤起 App Store 账号校验，再以当前有效交易重算权益。
    /// 非消耗型商品只能恢复、不会重复扣费；没有已购记录时给出明确提示。
    func restore() async {
        guard !isRestoring, !isPurchasing else { return }

        clearNotice()
        isRestoring = true
        // 恢复购买是一次显式校验，停止购买后的确认任务，允许按真实结果降级。
        confirmationTask?.cancel()
        purchaseGraceUntil = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            let isActive = await refreshEntitlements()
            notice = isActive
                ? "已恢复购买，VIP 权益已开启。"
                : "未找到可恢复的购买记录；若刚购买请稍后再试。"
        } catch {
            notice = "恢复失败：\(error.localizedDescription)"
        }
    }

    func clearNotice() {
        notice = nil
    }

    private func handleUpdate(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.vipProductID else { return }
        await transaction.finish()

        if transaction.revocationDate != nil {
            // 明确的退款 / 撤销：取消未完成的购买确认与保护窗口，立即回落。
            confirmationTask?.cancel()
            purchaseGraceUntil = nil
            apply(.storeKit(tier: .free))
            log("交易已撤销，权益回落")
            return
        }

        // 新购买、Ask to Buy 通过、其它设备购买：同样以交易本身即时开通。
        apply(.storeKit(tier: .vip))
        recordVIPStart(transaction.purchaseDate)
        await refreshEntitlements(allowDowngrade: false)
    }

    #if DEBUG
    /// 真机排查用：把 StoreKit 实际返回的交易列出来，便于确认
    /// 是「收据尚未同步」还是「商品 ID 不匹配 / 交易未通过校验」。
    func diagnostics() async -> String {
        var lines = [
            "计费点：\(Self.vipProductID)",
            "当前权益：\(tier.displayName)"
        ]

        var currentCount = 0
        for await result in Transaction.currentEntitlements {
            currentCount += 1
            switch result {
            case .verified(let transaction):
                lines.append("有效交易 #\(currentCount)：\(transaction.productID) / 已验证 / 撤销=\(transaction.revocationDate == nil ? "否" : "是")")
            case .unverified:
                lines.append("有效交易 #\(currentCount)：未通过校验")
            @unknown default:
                break
            }
        }
        if currentCount == 0 { lines.append("currentEntitlements：空") }

        var allCount = 0
        var matchedCount = 0
        for await result in Transaction.all {
            allCount += 1
            if case .verified(let transaction) = result,
               transaction.productID == Self.vipProductID {
                matchedCount += 1
                lines.append("历史交易：\(transaction.productID) / 撤销=\(transaction.revocationDate == nil ? "否" : "是")")
            }
        }
        lines.append("Transaction.all：共 \(allCount) 条，匹配 \(matchedCount) 条")
        if let since = vipSince, let days = vipDays {
            lines.append("最早购买：\(since.formatted(date: .numeric, time: .shortened)) / 已 \(days) 天")
        } else {
            lines.append("最早购买：未取到交易日期")
        }
        return lines.joined(separator: "\n")
    }
    #endif

    // MARK: - 门禁判定

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
