import SwiftUI
import StoreKit

/// 设置页内部路由；首页的 DEBUG 钩子也通过它直达统计与 VIP。
enum SettingsRoute: Hashable {
    case statistics
    case vip
    case about
    case designSystem
}

/// 设置页的统一行度量：标题行是「图标 + 文字」，非标题行只缩进到文字左边缘。
private enum SettingsLayout {
    static let iconSize: CGFloat = 34
    static let rowIndent: CGFloat = iconSize + Theme.Spacing.md
}

private extension View {
    /// 所有非标题行统一缩进到标题行文字的左边缘（34 + md = 46pt）。
    /// 控件本身可直接调用；Button / NavigationLink 应加在 label 内容上，
    /// 否则整行左侧会变成不可点击区域。
    func settingsRowIndent() -> some View {
        padding(.leading, SettingsLayout.rowIndent)
    }
}

struct SettingsView: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(StatisticsService.self) private var statistics
    @Environment(VaultSyncEngine.self) private var vaultSync
    @Environment(SoundService.self) private var sound
    @Environment(\.dismiss) private var dismiss

    private let initialRoute: SettingsRoute?
    @Binding private var requestedRoute: SettingsRoute?
    /// 延后列表（原入口在收藏夹列底部，现统一放到设置里）。
    private let snooze: SnoozeStore
    private let thumbnails: ThumbnailProvider
    private let onWakeSnoozed: (String) -> Void
    private let onWakeAllSnoozed: () -> Void
    private let onResetFirstVisit: () -> Void

    @State private var path: [SettingsRoute] = []
    @State private var didApplyInitialRoute = false
    @State private var isConfigured = false
    @State private var isVaultSetupPresented = false
    @State private var isVaultResetPresented = false
    @State private var isSnoozeListPresented = false
    @State private var isVIPPurchasePresented = false
    @State private var previewMachine: MachineKind?
    @State private var previewTrigger = 0
    @AppStorage(VaultAutoLock.defaultsKey) private var autoLockSeconds = VaultAutoLock.immediate.rawValue
    @AppStorage(TaskPolicy.batchSizeKey) private var batchSize = TaskPolicy.batchSize
    @AppStorage(VaultSyncPreference.enabledKey) private var syncEnabled = false

    init(
        initialRoute: SettingsRoute? = nil,
        requestedRoute: Binding<SettingsRoute?> = .constant(nil),
        snooze: SnoozeStore,
        thumbnails: ThumbnailProvider,
        onWakeSnoozed: @escaping (String) -> Void,
        onWakeAllSnoozed: @escaping () -> Void,
        onResetFirstVisit: @escaping () -> Void = {}
    ) {
        self.initialRoute = initialRoute
        self._requestedRoute = requestedRoute
        self.snooze = snooze
        self.thumbnails = thumbnails
        self.onWakeSnoozed = onWakeSnoozed
        self.onWakeAllSnoozed = onWakeAllSnoozed
        self.onResetFirstVisit = onResetFirstVisit
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                vipSection
                // 外观 / 销毁道具 / 统计 / 整理 / 延后 合并为一组主模块。
                mainSection
                vaultSection
                moreSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("设置".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".localized) { dismiss() }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
            .onAppear {
                isConfigured = vault.isConfigured
                if !entitlements.isVIP {
                    settings.destroyMachine = .wasteBasket
                    if syncEnabled {
                        syncEnabledBinding.wrappedValue = false
                    }
                }
            }
            .onChange(of: entitlements.isVIP) { _, isVIP in
                guard !isVIP else { return }
                settings.destroyMachine = .wasteBasket
                if syncEnabled {
                    syncEnabledBinding.wrappedValue = false
                }
            }
            .task {
                applyRequestedRoute()
            }
            .onChange(of: requestedRoute) { _, _ in
                applyRequestedRoute()
            }
            .fullScreenCover(isPresented: $isVaultSetupPresented) {
                VaultLockView()
            }
            .sheet(isPresented: $isSnoozeListPresented) {
                SnoozeListView(
                    records: snooze.records,
                    thumbnails: thumbnails,
                    onWake: onWakeSnoozed,
                    onWakeAll: onWakeAllSnoozed,
                    onClose: { isSnoozeListPresented = false }
                )
            }
            .sheet(isPresented: $isVaultResetPresented, onDismiss: {
                isConfigured = vault.isConfigured
            }) {
                VaultResetView()
            }
            .sheet(isPresented: $isVIPPurchasePresented) {
                VIPPurchaseSheet()
            }
        }
        // 购买 / 恢复的结果由当前可见的 VIP 页面反馈。
        .alert(
            "VIP",
            isPresented: Binding(
                get: { entitlements.notice != nil && !isVIPPurchasePresented },
                set: { presented in
                    if !presented { entitlements.clearNotice() }
                }
            )
        ) {
            Button("好".localized, role: .cancel) { entitlements.clearNotice() }
        } message: {
            Text(entitlements.notice ?? "")
        }
        .task {
            // 启动时若商品拉取失败，进入设置页再兜底一次，保证第一行能显示价格。
            if entitlements.product == nil {
                await entitlements.loadProduct()
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }

    // MARK: - 模块图标行

    /// 取代原来的 Section 灰色标题：3D 图标放进模块内部，作为该模块的一行。
    /// 需要标题/说明/当前值时才在同一行补文字；自带文字的单行模块
    /// （VIP / 关于）则把图标直接内嵌进功能行，不额外占一行。
    private func moduleRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        value: String? = nil
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            configIcon(icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            if let value {
                Text(value)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// `Assets.xcassets/Config` 里的 3D 配置图标，统一 34pt、等比不裁切。
    private func configIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: SettingsLayout.iconSize, height: SettingsLayout.iconSize)
            .accessibilityHidden(true)
    }

    /// VIP 两行需要等高：恢复购买行用等宽透明占位顶住 34pt 图标的高度，
    /// 左边缘与 `settingsRowIndent()` 完全一致（占位 + md 间距）。
    private var iconSpacer: some View {
        Color.clear.frame(width: SettingsLayout.iconSize, height: SettingsLayout.iconSize)
    }

    /// 先落盘再通知引擎，保证引擎读到的是新开关值。
    private var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { entitlements.isVIP && syncEnabled },
            set: { newValue in
                guard entitlements.isVIP else {
                    if newValue {
                        isVIPPurchasePresented = true
                    } else {
                        syncEnabled = false
                        UserDefaults.standard.set(false, forKey: VaultSyncPreference.enabledKey)
                        vaultSync.syncEnabledDidChange()
                    }
                    return
                }
                syncEnabled = newValue
                UserDefaults.standard.set(newValue, forKey: VaultSyncPreference.enabledKey)
                vaultSync.syncEnabledDidChange()
            }
        )
    }

    private var batchSizeValue: Int {
        TaskPolicy.configuredBatchSize(for: entitlements.tier)
    }

    private var batchSizeBinding: Binding<Int> {
        Binding(
            get: { batchSizeValue },
            set: { newValue in
                guard entitlements.isVIP else {
                    isVIPPurchasePresented = true
                    return
                }
                batchSize = TaskPolicy.clampedBatchSize(newValue)
            }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return "v\(version)"
    }

    /// sheet 内容可能早于外部状态更新被构建，这里同时读绑定值，保证能补齐跳转。
    private func applyRequestedRoute() {
        guard !didApplyInitialRoute else { return }
        guard let route = requestedRoute ?? initialRoute else { return }
        didApplyInitialRoute = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            path = [route]
        }
    }

    @ViewBuilder
    private func destination(for route: SettingsRoute) -> some View {
        switch route {
        case .statistics:
            StatisticsView()
        case .vip:
            VIPView()
        case .about:
            AboutView()
        case .designSystem:
            DesignSystemPreviewView()
        }
    }

    // MARK: - 主模块组

    /// 外观与销毁道具选择器组成一个紧凑分组，仅用一条分隔线区分；
    /// 「统计」「整理批次」「延后」各自压成一行。
    private var mainSection: some View {
        Section {
            selectorRows
            Toggle("音效".localized, isOn: soundBinding)
                .settingsRowIndent()
            statisticsRows
            taskRows
            snoozeRows
        }
    }

    // MARK: - 外观

    private var selectorRows: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                configIcon("icon_config_ui")
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("外观和交互".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)

                    Picker("显示模式".localized, selection: displayModeBinding) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(Theme.Text.tertiary.opacity(0.2))
                .padding(.leading, SettingsLayout.rowIndent)

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                configIcon("icon_config_destory")
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("销毁道具".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)

                    DevicePickerStrip(
                        selection: settings.destroyMachine,
                        isVIP: entitlements.isVIP,
                        onSelect: selectMachine
                    )
                    if let previewMachine {
                        DevicePreviewInline(
                            machine: previewMachine,
                            trigger: previewTrigger,
                            onClose: { self.previewMachine = nil }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .listRowSeparator(.hidden)
    }

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(get: { settings.displayMode }, set: { settings.displayMode = $0 })
    }

    private var soundBinding: Binding<Bool> {
        Binding(get: { settings.soundEnabled }, set: { settings.soundEnabled = $0 })
    }

    private func selectMachine(_ machine: MachineKind) {
        guard entitlements.isVIP || machine == .wasteBasket else {
            isVIPPurchasePresented = true
            return
        }
        settings.destroyMachine = machine
        sound.play(device: machine)
        withAnimation(.easeInOut(duration: 0.2)) {
            previewMachine = machine
            previewTrigger += 1
        }
    }

    // MARK: - 整理

    /// 整理批次：压成一行，副标题就是当前设置，右侧只留紧凑的 +/- 步进器。
    private var taskRows: some View {
        HStack(spacing: Theme.Spacing.md) {
            configIcon("icon_config_batch")

            VStack(alignment: .leading, spacing: 2) {
                Text("整理批次".localized)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Text.primary)
                Text("每批 %@ 张".localized(batchSizeValue))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Text.tertiary)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Stepper(
                "每批张数".localized,
                value: batchSizeBinding,
                in: entitlements.isVIP ? TaskPolicy.batchSizeRange : 0...200,
                step: TaskPolicy.batchSizeStep
            )
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("每批张数".localized)
            .accessibilityValue("每批 %@ 张".localized(batchSizeValue))
            .accessibilityHint(
                entitlements.isVIP
                    ? "范围 10 到 200 张，每次增加或减少 10 张".localized
                    : "VIP 专属，升级后可用".localized
            )
        }
        .padding(.vertical, 2)
    }

    private var todaySummary: StatSummary {
        statistics.summary(for: .today)
    }

    /// 统计：与「延后」同构，压成一行——图标 + 标题 + 副标题（今日件数）+ chevron。
    /// 分布条与各道具明细本来就在二级 `StatisticsView` 里，设置页只留摘要，不再重复占一行。
    private var statisticsRows: some View {
        Button {
            path.append(.statistics)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                configIcon("icon_config_data")

                VStack(alignment: .leading, spacing: 2) {
                    Text("统计".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)
                    Text(statisticsSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Text.secondary.opacity(0.5))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("统计".localized)
        .accessibilityValue(statisticsSubtitle)
        .accessibilityHint("查看完整的整理统计".localized)
    }

    private var statisticsSubtitle: String {
        todaySummary.destroyed > 0
            ? "今日 %@ 件".localized(todaySummary.destroyed)
            : "今日暂无销毁记录".localized
    }

    // MARK: - 延后

    /// 延后：压成一行，副标题显示当前数量；整行点击进入延后列表。
    /// 数量为 0 也保留这一行，列表本身的空态由 SnoozeListView 提供。
    private var snoozeRows: some View {
        Button {
            isSnoozeListPresented = true
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                configIcon("icon_config_later")

                VStack(alignment: .leading, spacing: 2) {
                    Text("延后".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)
                    Text("%@ 项待处理".localized(snooze.count))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Text.secondary.opacity(0.5))
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("延后".localized)
        .accessibilityValue("%@ 项".localized(snooze.count))
        .accessibilityHint("查看延后中的照片，可单张恢复或全部恢复".localized)
    }

    // MARK: - 私密保险箱

    private var vaultSection: some View {
        Section {
            moduleRow(icon: "icon_config_vault", title: "私密保险箱".localized)

            // iCloud 同步是模块级开关，放在模块首行：设置页很长，压在底部容易被忽略。
            syncToggleRow

            if syncEnabledBinding.wrappedValue {
                syncStatusRow
                syncDetailRow
            }

            if isConfigured {
                NavigationLink {
                    VaultPasswordChangeView()
                } label: {
                    Text("修改密码".localized)
                        .settingsRowIndent()
                }
            } else {
                Button {
                    isVaultSetupPresented = true
                } label: {
                    Text("设置保险箱密码".localized)
                        .settingsRowIndent()
                }
            }

            Picker("自动锁定".localized, selection: $autoLockSeconds) {
                ForEach(VaultAutoLock.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .settingsRowIndent()

            Button(role: .destructive) {
                isVaultResetPresented = true
            } label: {
                Text("重置保险箱".localized)
                    .settingsRowIndent()
            }
            .disabled(!isConfigured)
        }
    }

    /// iCloud 同步开关：常驻模块首行，副标题始终说明同步范围。
    /// 非 VIP 时同一行给「开通 VIP」文字入口，避免只留一个不可点的灰开关
    /// 让人以为功能没做或开关没加上。
    private var syncToggleRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Toggle(isOn: syncEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud 同步".localized)
                    Text(syncSubtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !entitlements.isVIP {
                Button("开通 VIP".localized) { isVIPPurchasePresented = true }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
                    .accessibilityHint("购买 VIP 后即可开启 iCloud 同步".localized)
            }
        }
        .settingsRowIndent()
    }

    private var syncStatusRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(vaultSync.statusText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Spacing.sm)
            if vaultSync.isSyncing {
                ProgressView()
            } else {
                Button("立即同步".localized) { vaultSync.syncNow() }
                    .font(Theme.Typography.caption)
                    .disabled(!vaultSync.canSyncNow)
            }
        }
        .settingsRowIndent()
    }

    private var syncDetailRow: some View {
        Text(vaultSync.detailText)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .settingsRowIndent()
    }

    private var syncSubtitle: String {
        if !entitlements.isVIP { return "VIP 专属 · 升级后可开启".localized }
        return syncEnabledBinding.wrappedValue
            ? "保险箱文件跨设备可用".localized
            : "开启后，保险箱文件同步到你的 iCloud 私有数据库".localized
    }

    // MARK: - VIP

    /// 极简两行：第一行「标题 + 副标题（VIP 为成为 VIP 的天数，未购买为商品本地化描述）
    /// / 含价格的购买按钮」，第二行「恢复购买」。两行都是整行 Button（.plain + contentShape），
    /// 点击区域覆盖整行；购买入口打开完整 VIP 购买弹窗，恢复结果由本页反馈。
    private var vipSection: some View {
        Section {
            Button {
                isVIPPurchasePresented = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    configIcon("icon_config_vip")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entitlements.isVIP ? "欢迎尊贵的VIP大人".localized : "VIP")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Text.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        // StoreKit 按设备语言返回 App Store Connect 配置的商品描述。
                        Text(vipDescription)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Text.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Spacing.sm)

                    if entitlements.isVIP {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Accent.fire)
                    } else if entitlements.isLoadingProduct || entitlements.isPurchasing {
                        ProgressView()
                    } else {
                        Text(purchaseLabel)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Text.pillButton)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 6)
                            .background(Theme.Surface.pillButton, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entitlements.isPurchasing || entitlements.isRestoring)
            .accessibilityLabel(vipAccessibilityLabel)

            Button {
                Task { await entitlements.restore() }
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    iconSpacer

                    Text(entitlements.isRestoring ? "正在恢复…".localized : "恢复购买".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)

                    Spacer(minLength: Theme.Spacing.sm)

                    if entitlements.isRestoring {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Theme.Text.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entitlements.isPurchasing || entitlements.isRestoring)
            .accessibilityLabel("恢复购买".localized)
            .accessibilityHint("找回此前已购买的 VIP，不会重复扣费".localized)
        }
    }

    /// VIP 有效时副标题固定为「成为 VIP 的天数」，天数由 EntitlementStore
    /// 按最早的已验证购买交易计算（含中断与重复购买，不重新计时）；
    /// 未购买时才展示 App Store Connect 配置的分语言商品描述。
    private var vipDescription: String {
        if entitlements.isVIP {
            guard let days = entitlements.vipDays else {
                // 收据日期暂时取不到时的兜底，避免出现空白第二行。
                return "已永久解锁全部权益".localized
            }
            return "从成为VIP那天到现在已经%@天啦！".localized(days)
        }
        if let description = entitlements.product?.description,
           !description.isEmpty {
            return description
        }
        return "一次性购买 · 永久解锁，无需续订".localized
    }

    /// 价格整合进购买按钮；商品未就绪时按钮只用于重新拉取，不发起扣费。
    private var purchaseLabel: String {
        guard let product = entitlements.product else { return "重新获取".localized }
        return "购买 %@".localized(product.displayPrice)
    }

    private var vipAccessibilityLabel: String {
        if entitlements.isVIP {
            if let days = entitlements.vipDays {
                return "欢迎尊贵的VIP大人，已解锁 %@ 天".localized(days)
            }
            return "欢迎尊贵的VIP大人，权益已解锁".localized
        }
        guard let price = entitlements.product?.displayPrice else { return "购买 VIP".localized }
        return "购买 VIP，%@".localized(price)
    }

    // MARK: - 我们的应用 / 关于

    /// 合并为一组：应用列表用图标行标识，关于把图标与版本号直接放在入口行里。
    private var moreSection: some View {
        Section {
            moduleRow(icon: "icon_config_apps", title: "我们的应用".localized)

            OurAppsRows()

            NavigationLink(value: SettingsRoute.about) {
                HStack(spacing: Theme.Spacing.md) {
                    configIcon("icon_config_about")

                    Text("关于".localized)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.primary)

                    Spacer(minLength: Theme.Spacing.sm)

                    Text(appVersion)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.designSystem) {
                Text("设计系统预览".localized)
                    .settingsRowIndent()
            }

            HStack(spacing: Theme.Spacing.sm) {
                simulationButton(title: "非 VIP".localized, tier: .free)
                simulationButton(title: "VIP".localized, tier: .vip)
            }
            .settingsRowIndent()

            Button("清空首次访问标识".localized) {
                onResetFirstVisit()
                dismiss()
            }
            .settingsRowIndent()
        } header: {
            Text("开发工具".localized)
        }
    }

    private func simulationButton(title: String, tier: EntitlementTier) -> some View {
        let isSelected = entitlements.simulatedTier == tier
        return Button {
            entitlements.setSimulatedTier(tier)
        } label: {
            Text(title)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.Text.primary : Theme.Text.secondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .neuSurface(isSelected ? .inset : .raisedSmall, cornerRadius: Theme.Radius.chip)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    #endif
}

private struct DevicePreviewInline: View {
    let machine: MachineKind
    let trigger: Int
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion
    @State private var shakeToken = 0
    @State private var switchToken = 0

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack {
                Text("道具试听：%@".localized(machine.displayName))
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(Theme.Text.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Text.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭".localized)
            }
            DestroyDock(
                pendingCount: 1,
                shakeToken: shakeToken,
                machine: machine,
                switchToken: switchToken,
                onSwitch: {}
            )
            .frame(height: 100)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.top, Theme.Spacing.xs)
        .onAppear(perform: triggerAnimation)
        .onChange(of: trigger) { _, _ in
            triggerAnimation()
        }
    }

    private func triggerAnimation() {
        withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
            shakeToken += 1
            switchToken += 1
        }
    }
}

#Preview {
    SettingsView(
        snooze: SnoozeStore(),
        thumbnails: ThumbnailProvider(),
        onWakeSnoozed: { _ in },
        onWakeAllSnoozed: {}
    )
    .environment(EntitlementStore())
    .environment(VaultStore())
    .environment(AppSettings())
    .environment(StatisticsService())
    .environment(VaultSyncEngine())
    .environment(SoundService())
}
