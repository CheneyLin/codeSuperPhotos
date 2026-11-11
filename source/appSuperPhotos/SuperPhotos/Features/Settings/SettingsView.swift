import SwiftUI

/// 设置页内部路由；首页的 DEBUG 钩子也通过它直达统计与 VIP。
enum SettingsRoute: Hashable {
    case statistics
    case vip
    case about
    case designSystem
}

struct SettingsView: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(VaultStore.self) private var vault
    @Environment(AppSettings.self) private var settings
    @Environment(StatisticsService.self) private var statistics
    @Environment(\.dismiss) private var dismiss

    private let initialRoute: SettingsRoute?
    @Binding private var requestedRoute: SettingsRoute?
    /// 延后列表（原入口在收藏夹列底部，现统一放到设置里）。
    private let snooze: SnoozeStore
    private let thumbnails: ThumbnailProvider
    private let onWakeSnoozed: (String) -> Void
    private let onWakeAllSnoozed: () -> Void

    @State private var path: [SettingsRoute] = []
    @State private var didApplyInitialRoute = false
    @State private var probeMessage = ""
    @State private var isProbeAlertPresented = false
    @State private var isConfigured = false
    @State private var isVaultSetupPresented = false
    @State private var isVaultResetPresented = false
    @State private var isSnoozeListPresented = false
    @AppStorage(VaultAutoLock.defaultsKey) private var autoLockSeconds = VaultAutoLock.immediate.rawValue
    @AppStorage(VaultEncryptionMode.defaultsKey) private var encryptionModeRaw = VaultEncryptionMode.standard.rawValue
    @AppStorage(TaskPolicy.batchSizeKey) private var batchSize = TaskPolicy.batchSize

    private let gigabyte: Int64 = 1024 * 1024 * 1024

    init(
        initialRoute: SettingsRoute? = nil,
        requestedRoute: Binding<SettingsRoute?> = .constant(nil),
        snooze: SnoozeStore,
        thumbnails: ThumbnailProvider,
        onWakeSnoozed: @escaping (String) -> Void,
        onWakeAllSnoozed: @escaping () -> Void
    ) {
        self.initialRoute = initialRoute
        self._requestedRoute = requestedRoute
        self.snooze = snooze
        self.thumbnails = thumbnails
        self.onWakeSnoozed = onWakeSnoozed
        self.onWakeAllSnoozed = onWakeAllSnoozed
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                appearanceSection
                deviceSection
                statisticsSection
                taskSection
                snoozeSection
                vaultSection
                vipSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(for: route)
            }
            .alert("门禁结果", isPresented: $isProbeAlertPresented) {
                Button("好", role: .cancel) {}
            } message: {
                Text(probeMessage)
            }
            .onAppear {
                isConfigured = vault.isConfigured
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
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
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

    // MARK: - 外观

    private var appearanceSection: some View {
        Section {
            Picker("显示模式", selection: displayModeBinding) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("高对比度", isOn: highContrastBinding)

            Toggle("降低动效", isOn: reduceMotionBinding)

            Toggle("音效", isOn: soundBinding)
        } header: {
            Text("外观与交互")
        } footer: {
            Text("显示模式即时生效并保留到下次启动；高对比度会加深文字、加粗描边；降低动效与系统设置取并集。")
        }
    }

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(get: { settings.displayMode }, set: { settings.displayMode = $0 })
    }

    private var highContrastBinding: Binding<Bool> {
        Binding(get: { settings.highContrast }, set: { settings.highContrast = $0 })
    }

    private var reduceMotionBinding: Binding<Bool> {
        Binding(get: { settings.reduceMotion }, set: { settings.reduceMotion = $0 })
    }

    private var soundBinding: Binding<Bool> {
        Binding(get: { settings.soundEnabled }, set: { settings.soundEnabled = $0 })
    }

    // MARK: - 销毁道具

    /// 底部道具的直选入口，与首页「轻点循环切换」共用 AppSettings.destroyMachine。
    private var deviceSection: some View {
        Section {
            DevicePickerStrip(selection: settings.destroyMachine) { machine in
                settings.destroyMachine = machine
            }
        } header: {
            Text("销毁道具")
        } footer: {
            Text("桌面底部可轻点道具按顺序循环切换：废纸篓 → 碎纸机 → 壁炉 → 邮筒 → 任意门。每款道具都有独立的落入动效与音效，选择会保留到下次启动；统计按当时选中的道具分别计数。")
        }
    }

    // MARK: - 统计

    private var taskSection: some View {
        Section {
            Stepper(
                "每批 \(batchSize) 张",
                value: $batchSize,
                in: TaskPolicy.batchSizeRange,
                step: TaskPolicy.batchSizeStep
            )
            .accessibilityLabel("每批张数")
            .accessibilityValue("每批 \(batchSize) 张")
            .accessibilityHint("范围 10 到 200 张，每次增加或减少 10 张")
        } header: {
            Text("整理")
        } footer: {
            Text("只影响之后新建的批次；正在进行的任务按开始时的张数计算进度，中途修改不会改变分母。相簿不足时按实际张数开始。")
        }
    }

    private var todaySummary: StatSummary {
        statistics.summary(for: .today)
    }

    /// 今日各道具件数的紧凑摘要；零计数不展示，避免出现一长串 0。
    private var todayDeviceLine: String {
        let parts = MachineKind.allCases
            .filter { todaySummary.count(for: $0) > 0 }
            .map { "\($0.displayName) \(todaySummary.count(for: $0))" }
        return parts.isEmpty ? "今日暂无销毁记录" : parts.joined(separator: " · ")
    }

    private var statisticsSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.statistics) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("整理统计")
                        Spacer()
                        Text("今日 \(todaySummary.destroyed) 件")
                            .foregroundStyle(.secondary)
                    }
                    DeviceDistributionBar(summary: todaySummary, height: 7)
                    Text(todayDeviceLine)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.tertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("统计")
        } footer: {
            Text("免费版提供今日、本周、累计，以及五款道具各自的件数与占比；本月周期属于 VIP 权益。")
        }
    }

    // MARK: - 延后

    /// 延后入口。数量为 0 也保留这一行：用户可以进列表确认“确实没有延后”，
    /// 列表本身的空态由 SnoozeListView 提供。
    private var snoozeSection: some View {
        Section {
            Button {
                isSnoozeListPresented = true
            } label: {
                HStack {
                    Text("延后处理 \(snooze.count) 项")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看延后中的照片，可单张恢复或全部恢复")
        } header: {
            Text("延后")
        } footer: {
            Text("延后中的照片到期前不会进入舞台；可在这里逐张恢复或全部恢复。")
        }
    }

    // MARK: - 私密保险箱

    private var vaultSection: some View {
        Section {
            if isConfigured {
                NavigationLink {
                    VaultPasswordChangeView()
                } label: {
                    Text("修改密码")
                }
            } else {
                Button("设置保险箱密码") {
                    isVaultSetupPresented = true
                }
            }

            Picker("自动锁定", selection: $autoLockSeconds) {
                ForEach(VaultAutoLock.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }

            Picker("内容保护", selection: $encryptionModeRaw) {
                ForEach(VaultEncryptionMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Button(role: .destructive) {
                isVaultResetPresented = true
            } label: {
                Text("重置保险箱")
            }
            .disabled(!isConfigured)
        } header: {
            Text("私密保险箱")
        } footer: {
            Text("密码盘组合空间 30 × 60 = 1800 种（约 10.8 bit），能挡住随手翻看，挡不住有时间暴力尝试的人；已配合阶梯锁定。密码忘记后无法找回。\n\n内容保护：标准（默认）把文件以普通格式存放在 App 沙盒，只受 iOS 沙盒与系统文件保护，App 密码只保护界面访问，不做应用层加密；强加密才使用 AES-GCM 与仅存本机的 Keychain 内容密钥。两档文件都不进入 iCloud / iTunes 备份。切换只影响之后存入的内容，切换前已存入的条目不保证可读（开发期不做迁移）。")
        }
    }

    // MARK: - VIP

    private var vipSection: some View {
        Section {
            HStack {
                Text("当前权益")
                Spacer()
                Text(entitlements.isVIP ? "VIP（模拟）" : "免费版")
                    .foregroundStyle(entitlements.isVIP ? Color.orange : Color.secondary)
            }

            NavigationLink(value: SettingsRoute.vip) {
                Text("查看权益对比")
            }

            Toggle(
                "模拟 VIP",
                isOn: Binding(
                    get: { entitlements.isVIP },
                    set: { entitlements.setVIP($0) }
                )
            )
        } header: {
            Text("VIP")
        } footer: {
            Text("一期只有模拟开关，无内购、无价格。二期接入 StoreKit 2 后，真实交易结果会写入同一个 EntitlementStore。")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.about) {
                Text("关于与隐私")
            }
        } header: {
            Text("关于")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.designSystem) {
                Text("设计系统预览")
            }

            Toggle("模拟销毁（不真删）", isOn: Binding(
                get: { DebugOptions.readSimulatingDestroy() },
                set: { DebugOptions.setSimulatingDestroy($0) }
            ))

            gateProbeRows
        } header: {
            Text("开发工具")
        } footer: {
            Text("仅 Debug 构建可见。模拟销毁会完整走吸附、蓄力、动画与提示，但不调用系统删除。")
        }
    }

    @ViewBuilder
    private var gateProbeRows: some View {
        ForEach(MediaKind.allCases) { kind in
            Button {
                showProbe(for: kind)
            } label: {
                HStack {
                    Text("入库：\(kind.displayName)")
                    Spacer()
                    statusIcon(
                        entitlements.canImport(
                            kind: kind,
                            byteSize: 5 * 1024 * 1024,
                            usedItems: 10,
                            usedBytes: 512 * 1024 * 1024
                        )
                    )
                }
                .foregroundStyle(.primary)
            }
        }

        probeRow(title: "容量：59 件 / 1.9GB", result: entitlements.quotaStatus(usedItems: 59, usedBytes: Int64(1.9 * Double(gigabyte))))
        probeRow(title: "容量：60 件 / 2.0GB", result: entitlements.quotaStatus(usedItems: 60, usedBytes: 2 * gigabyte))
        probeRow(title: "容量：61 件", result: entitlements.quotaStatus(usedItems: 61, usedBytes: 2 * gigabyte))
        probeRow(title: "容量：2.1GB", result: entitlements.quotaStatus(usedItems: 60, usedBytes: Int64(2.1 * Double(gigabyte))))
    }

    private func probeRow(title: String, result: GateResult) -> some View {
        HStack {
            Text(title)
            Spacer()
            statusIcon(result)
        }
    }

    @ViewBuilder
    private func statusIcon(_ result: GateResult) -> some View {
        switch result {
        case .allowed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .accessibilityLabel("允许")
        case .requiresVIP:
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.orange)
                .accessibilityLabel("需要 VIP")
        case .quotaExceeded:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
                .accessibilityLabel("超出额度")
        }
    }

    private func showProbe(for kind: MediaKind) {
        let result = entitlements.canImport(
            kind: kind,
            byteSize: 5 * 1024 * 1024,
            usedItems: 10,
            usedBytes: 512 * 1024 * 1024
        )
        probeMessage = result.isAllowed
            ? "允许入库：\(kind.displayName)"
            : (result.message ?? "未通过门禁")
        isProbeAlertPresented = true
    }
    #endif
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
}
