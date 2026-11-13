import Foundation
import Observation
import StoreKit

/// 权益的唯一判定入口 + 唯一计费点的 StoreKit 2 交易封装。
/// 计费点为**非消耗型**：一次购买永久解锁 VIP，无续订、无到期日。
/// 实际权益数据源为真实交易（购买 / 恢复购买）；Debug 构建可临时覆盖展示状态，
/// 不会修改 StoreKit 快照。调用点只依赖这里的判定，不感知交易细节。
@MainActor
@Observable
final class EntitlementStore {
    /// 唯一计费点（非消耗型 / 一次性购买）。需在 App Store Connect 中
    /// 把该 ID 配置为「非消耗型购买」，而不是自动续订订阅。
    static let vipProductID = "com.gpwzw.appSuperPhotos.vip"
    private static let previouslyVerifiedVIPKey = "entitlements.previouslyVerifiedVIP"
    private static let missingVIPRecordSinceKey = "entitlements.missingVIPRecordSince"
    private static let missingVIPRecordGrace: TimeInterval = 24 * 60 * 60

    // MARK: - 权益快照

    private(set) var snapshot: EntitlementSnapshot = .free
    #if DEBUG
    /// Temporary override for testing VIP-gated flows; never changes the StoreKit snapshot.
    private(set) var simulatedTier: EntitlementTier?
    #endif
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
    @ObservationIgnored private var purchaseGraceUntil: Date?
    @ObservationIgnored private var missingRecordGraceTask: Task<Void, Never>?

    var tier: EntitlementTier {
        #if DEBUG
        simulatedTier ?? snapshot.tier
        #else
        snapshot.tier
        #endif
    }
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

    #if DEBUG
    func setSimulatedTier(_ tier: EntitlementTier) {
        simulatedTier = tier
    }
    #endif

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
                notice = "暂时无法获取会员商品，请检查网络或稍后重试。".localized
            }
        } catch {
            notice = "获取会员商品失败：%@".localized(error.localizedDescription)
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
            missingRecordGraceTask?.cancel()
            missingRecordGraceTask = nil
            UserDefaults.standard.set(true, forKey: Self.previouslyVerifiedVIPKey)
            UserDefaults.standard.removeObject(forKey: Self.missingVIPRecordSinceKey)
            // 每次重算都从完整历史交易里核对最早购买日，回前台 / 重启后天数不会倒退。
            await refreshVIPSince()
        }

        let now = Date()
        let hasPreviouslyVerifiedVIP = UserDefaults.standard.bool(forKey: Self.previouslyVerifiedVIPKey)
            || snapshot.tier == .vip
        var missingRecordSince: Date?
        if !isActive && hasPreviouslyVerifiedVIP {
            let storedDate = UserDefaults.standard.object(forKey: Self.missingVIPRecordSinceKey) as? Date
            let date = storedDate ?? now
            if storedDate == nil {
                UserDefaults.standard.set(date, forKey: Self.missingVIPRecordSinceKey)
            }
            missingRecordSince = date
        }
        let missingRecordDeadline = missingRecordSince?.addingTimeInterval(Self.missingVIPRecordGrace)
        let isWithinMissingRecordGrace = missingRecordDeadline.map { now < $0 } ?? false
        let isWithinPurchaseGrace = purchaseGraceUntil.map { now < $0 } ?? false

        if isActive {
            apply(.storeKit(tier: .vip))
        } else if allowDowngrade && !isWithinPurchaseGrace && !isWithinMissingRecordGrace {
            apply(.storeKit(tier: .free))
            UserDefaults.standard.set(false, forKey: Self.previouslyVerifiedVIPKey)
            UserDefaults.standard.removeObject(forKey: Self.missingVIPRecordSinceKey)
            missingRecordGraceTask?.cancel()
            missingRecordGraceTask = nil
        } else if !isActive {
            if hasPreviouslyVerifiedVIP, let missingRecordDeadline, isWithinMissingRecordGrace {
                apply(.storeKit(tier: .vip))
                scheduleMissingRecordGraceExpiry(at: missingRecordDeadline)
                log("未检索到有效交易，24 小时宽限期至 \(missingRecordDeadline)")
            }
            if isWithinPurchaseGrace {
                log("重算未命中交易，但处于购买保护窗口内，保持 VIP 不降级")
            } else if !allowDowngrade {
                log("后台确认暂不允许降级")
            }
        }
        return isActive
    }

    private func scheduleMissingRecordGraceExpiry(at deadline: Date) {
        guard missingRecordGraceTask == nil else { return }
        missingRecordGraceTask = Task { [weak self] in
            let delay = max(deadline.timeIntervalSinceNow, 0)
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            missingRecordGraceTask = nil
            await refreshEntitlements()
        }
    }

    /// 非消耗型交易没有到期日，判定条件是「交易已验证 + 商品 ID 匹配 + 未被撤销」。
    /// 无有效交易时会应用本地 24 小时宽限期，之后回落为免费版。
    private func isUnlocked(_ transaction: Transaction) -> Bool {
        transaction.productID == Self.vipProductID
            && transaction.revocationDate == nil
    }

    /// 多来源交叉校验：
    /// 1. `Transaction.currentEntitlements`（首选，含当前有效的一次性购买）；
    /// 2. `Transaction.all`（回退，含已 finish 的历史交易）。
    /// Sandbox / 真机上刚完成的购买常有几秒收据同步延迟，此时第 1 路可能暂时查不到，
    /// 单靠它会出现「付款成功却判定为免费版」；非消耗型永久有效，用历史交易兜底是安全的。
    /// 退款后两条路径里的交易都会带 `revocationDate`，因而不会被视为有效交易。
    private func hasVerifiedVIPTransaction() async -> Bool {
        var seen: [String] = []
        var unverifiedCount = 0

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                seen.append(transaction.productID + (transaction.revocationDate == nil ? "" : "(已撤销)".localized))
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
                    notice = "交易未能通过校验，请联系 App Store 支持。".localized
                    return
                }
                await transaction.finish()

                guard isUnlocked(transaction) else {
                    notice = "购买已完成，但交易与 VIP 计费点不一致，请联系支持。".localized
                    await refreshEntitlements()
                    return
                }

                // 关键：本次交易已由 StoreKit 验证通过，立即开通，不等收据刷新。
                // 之前的做法只依赖 currentEntitlements 重算，Sandbox 下新交易可能
                // 延迟出现，会出现「付款成功仍显示免费版」。
                // 购买弹窗收起还会触发一次 scenePhase 回前台重算，故开 60 秒保护窗口。
                apply(.storeKit(tier: .vip))
                UserDefaults.standard.set(true, forKey: Self.previouslyVerifiedVIPKey)
                UserDefaults.standard.removeObject(forKey: Self.missingVIPRecordSinceKey)
                missingRecordGraceTask?.cancel()
                missingRecordGraceTask = nil
                // 本次交易的购买日立即生效，欢迎语不用等收据同步完成。
                recordVIPStart(transaction.purchaseDate)
                purchaseGraceUntil = Date().addingTimeInterval(60)
                notice = "购买成功，VIP 已永久解锁。".localized
                scheduleConfirmation()
            case .userCancelled:
                break
            case .pending:
                notice = "购买正在等待处理（例如需要家长批准），完成后权益会自动开通。".localized
            @unknown default:
                break
            }
        } catch {
            notice = "购买未完成：%@".localized(error.localizedDescription)
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
                ? "已恢复购买，VIP 权益已开启。".localized
                : "未找到可恢复的购买记录；若刚购买请稍后再试。".localized
        } catch {
            notice = "恢复失败：%@".localized(error.localizedDescription)
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
            // 撤销交易不再视为有效；按首次未检索到有效交易的时间启动 24 小时宽限期。
            confirmationTask?.cancel()
            purchaseGraceUntil = nil
            await refreshEntitlements()
            log("交易已撤销，按无有效记录策略重新校验权益")
            return
        }

        // 新购买、Ask to Buy 通过、其它设备购买：同样以交易本身即时开通。
        apply(.storeKit(tier: .vip))
        UserDefaults.standard.set(true, forKey: Self.previouslyVerifiedVIPKey)
        UserDefaults.standard.removeObject(forKey: Self.missingVIPRecordSinceKey)
        missingRecordGraceTask?.cancel()
        missingRecordGraceTask = nil
        recordVIPStart(transaction.purchaseDate)
        await refreshEntitlements(allowDowngrade: false)
    }

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
