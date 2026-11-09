import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(VaultStore.self) private var vault
    @Environment(StatisticsService.self) private var statistics
    @Environment(SoundService.self) private var sound
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var library = LibraryService()
    @State private var albumService = AlbumService()
    /// 任务式整理：一次最多 100 张，进度与决策持久化。
    @State private var task = CleaningTaskStore()
    /// 是否进入三栏工作区；桌面首屏不展示照片。
    @State private var isWorkspacePresented = false
    @State private var isAlbumPickerPresented = false
    @State private var isExecutingTaskEnd = false
    @State private var settlement: TaskSettlement?

    @State private var isSettingsPresented = false
    @State private var settingsInitialRoute: SettingsRoute?
    @State private var isDesignSystemPresented = false
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false
    @State private var isOnboardingPresented = false
    @State private var isRequestingAccess = false
    @State private var isAlbumsDrawerPresented = false

    @State private var isVaultPresented = false
    @State private var isVaultDrawerPresented = false
    /// 左滑存入保险箱时同步打开箱门；入队动画结束后自动合上。
    @State private var vaultDoorOpen = false
    /// 右滑存入收藏夹时给选中相簿一个强调脉冲。
    @State private var favoritesReceiving = false
    /// 延后存储：到期前不再进入新任务。
    @State private var snooze = SnoozeStore()
    /// 全屏查看的启动目标；nil 表示未打开。
    @State private var fullscreenRequest: FullscreenRequest?
    @State private var isSnoozeListPresented = false

    /// 当前照片的稳定标识；决策记录后仍能指向同一张。
    @State private var currentID: String?
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1

    @State private var destroy = DestroyCoordinator()
    /// 坞口被点击时自增，舞台据此播放一次“下滑入待销毁”的等效动画。
    @State private var discardRequest = 0
    /// UI 测试用：自增触发一次舞台轻点。
    @State private var tapRequest = 0
    @State private var toastMessage: ToastMessage?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Surface.base.ignoresSafeArea()

                switch library.accessState {
                case .notDetermined:
                    PermissionIntroView(isRequesting: isRequestingAccess) {
                        requestAccess()
                    }
                case .denied:
                    PermissionDeniedView {
                        library.openSettings()
                    }
                case .authorized, .limited:
                    if isWorkspacePresented, task.isActive {
                        taskWorkspace
                    } else {
                        deskView
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerBar
            }
            .overlay {
                if isVaultDrawerPresented {
                    GeometryReader { proxy in
                        vaultDrawer(width: proxy.size.width)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $isSettingsPresented, onDismiss: {
                settingsInitialRoute = nil
            }) {
                SettingsView(
                    initialRoute: settingsInitialRoute,
                    requestedRoute: $settingsInitialRoute
                )
            }
            .sheet(isPresented: $isAlbumPickerPresented) {
                TaskAlbumPickerView(
                    allPhotoCount: albumService.allPhotoCount,
                    albums: albumService.userAlbums,
                    onSelect: { album in
                        isAlbumPickerPresented = false
                        startTask(album: album)
                    },
                    onClose: { isAlbumPickerPresented = false }
                )
            }
            .fullScreenCover(isPresented: $isDesignSystemPresented) {
                NavigationStack {
                    DesignSystemPreviewView()
                }
            }
            .fullScreenCover(isPresented: $isVaultPresented) {
                VaultLockView()
            }
            .fullScreenCover(item: $fullscreenRequest) { request in
                PhotoFullscreenView(
                    items: visibleItems,
                    startID: request.id,
                    thumbnails: library.thumbnails,
                    onChangeCurrent: { id in
                        currentID = id
                        isZoomed = false
                        zoomScale = 1
                    },
                    onClose: { fullscreenRequest = nil }
                )
            }
            .sheet(isPresented: $isSnoozeListPresented) {
                SnoozeListView(
                    records: snooze.records,
                    thumbnails: library.thumbnails,
                    onWake: { id in
                        wakeUpSnoozed(id: id)
                    },
                    onWakeAll: {
                        wakeAllSnoozed()
                    },
                    onClose: { isSnoozeListPresented = false }
                )
            }
            .fullScreenCover(item: $settlement) { value in
                TaskSettlementView(
                    settlement: value,
                    onNext: {
                        settlement = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(420))
                            isAlbumPickerPresented = true
                        }
                    },
                    onClose: { settlement = nil }
                )
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingView {
                    hasCompletedOnboarding = true
                    isOnboardingPresented = false
                }
            }
            .task {
                library.excludedLocalIDs = vault.originLocalIDs
                await library.start()
                await albumService.load()
                syncDefaultAlbum()
                restoreTaskIfNeeded()
                clampCurrentID()
                presentOnboardingIfNeeded()
                await runUITestHooksIfNeeded()
            }
            .task {
                // 延后到期自动回到待整理池：每分钟清理一次过期记录。
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    snooze.purgeExpired()
                }
            }
            .onChange(of: library.accessState) { _, state in
                if state.canBrowse {
                    restoreTaskIfNeeded()
                    clampCurrentID()
                    if !hasCompletedOnboarding {
                        isOnboardingPresented = true
                    }
                }
            }
            .onChange(of: library.revision) { _, _ in
                clampCurrentID()
                Task {
                    await albumService.load(force: true)
                    syncDefaultAlbum()
                }
            }
            .onChange(of: albumService.userAlbums) { _, _ in
                syncDefaultAlbum()
            }
            .onChange(of: vault.revision) { _, _ in
                library.excludedLocalIDs = vault.originLocalIDs
            }
            .task(id: currentItem?.id) {
                guard let id = currentItem?.id else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                statistics.recordBrowse(id: id)
            }
            .toast($toastMessage, topPadding: 64)
        }
        // 单屏工作区的固定高度元素较多，限制在非无障碍字号内避免遮挡；
        // 设置、统计、引导等阅读页仍完整支持 AX 字号。
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - 顶部

    private var headerBar: some View {
        // 左：保险箱入口；中：工作区内显示销毁方式主控；右：设置。
        HStack(spacing: Theme.Spacing.sm) {
            vaultHeaderButton

            Spacer(minLength: Theme.Spacing.sm)

            if isWorkspacePresented, task.isActive {
                DestroyMachineSelector(machine: destroy.machine) { kind in
                    destroy.switchMachine(kind)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.neuIcon)
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Surface.base)
    }

    private var vaultHeaderButton: some View {
        Button {
            openVaultPreview()
        } label: {
            Image(systemName: vault.isConfigured ? "lock.shield.fill" : "lock.shield")
        }
        .buttonStyle(NeuIconButtonStyle(tint: Theme.Accent.brass))
        .overlay(alignment: .topTrailing) {
            if vault.records.count > 0 {
                Text("\(min(vault.records.count, 99))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Surface.base)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.Accent.brass, in: Capsule())
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel("私密保险箱，已存 \(vault.records.count) 件")
    }

    // MARK: - 桌面

    private var deskView: some View {
        TaskDeskView(
            isTaskActive: task.isActive,
            isTaskFinished: task.isFinished,
            albumTitle: task.albumTitle,
            processed: task.processedCount,
            total: task.totalCount,
            onStart: { isAlbumPickerPresented = true },
            onResume: { enterWorkspace() }
        )
    }

    // MARK: - 三栏工作区

    private var taskWorkspace: some View {
        GeometryReader { proxy in
            // 两侧各 20%，中间 60%；窄屏（Duo 外屏等）下两侧收到 64pt，保证中间可读。
            let sideWidth = min(148, max(64, proxy.size.width * 0.2))

            VStack(spacing: 0) {
                if library.accessState == .limited {
                    LimitedAccessBanner {
                        library.manageLimitedAccess()
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.bottom, Theme.Spacing.sm)
                }

                TaskProgressHeader(
                    albumTitle: task.albumTitle,
                    processed: task.processedCount,
                    total: task.totalCount,
                    isFinished: task.isFinished,
                    isExecuting: isExecutingTaskEnd,
                    onPause: { pauseTask() },
                    onFinish: {
                        Task { await executeTaskEnd() }
                    }
                )

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    VaultDoorColumn(
                        width: sideWidth,
                        count: vault.records.count,
                        isConfigured: vault.isConfigured,
                        isOpen: vaultDoorOpen,
                        pendingCount: task.vaultCount,
                        onTap: { openVaultPreview() }
                    )

                    Group {
                        stageSection(sideWidth: sideWidth)
                    }
                    .frame(maxWidth: .infinity)

                    FavoriteAlbumColumn(
                        width: sideWidth,
                        albums: albumService.userAlbums,
                        selectedAlbumID: settings.defaultAlbumID,
                        isReceiving: favoritesReceiving,
                        snoozedCount: snooze.count,
                        onSelect: { selectDefaultAlbum($0) },
                        onOpenAlbums: { openAlbums() },
                        onOpenSnoozed: { isSnoozeListPresented = true }
                    )
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(maxHeight: .infinity)
                // 舞台要接住抽屉带来的缩放与失焦；两侧实体不参与缩放。
                .allowsHitTesting(!isAlbumsDrawerPresented && !isVaultDrawerPresented)
            }
            .overlay {
                if isAlbumsDrawerPresented {
                    albumsDrawer(width: proxy.size.width)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                dockSection
            }
        }
    }

    private func stageSection(sideWidth: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            PhotoStageView(
                items: visibleItems,
                currentIndex: stageIndex,
                thumbnails: library.thumbnails,
                isInteractionEnabled: !isAlbumsDrawerPresented
                    && !isVaultDrawerPresented
                    && !isExecutingTaskEnd,
                canDiscard: task.isActive && !isExecutingTaskEnd,
                canFavorite: settings.defaultAlbumID != nil,
                discardRequest: discardRequest,
                tapRequest: tapRequest,
                sideDropOffset: sideWidth + Theme.Spacing.sm + 26,
                onAdvance: { id in
                    advanceCurrent(from: id)
                },
                onOpenFullscreen: { id in
                    openFullscreen(id: id)
                },
                onVaultStore: { id in
                    vaultSwipe(id)
                },
                onFavoriteStore: { id in
                    favoriteSwipe(id)
                },
                onFavoriteRejected: {
                    toastMessage = ToastMessage(
                        text: "先在右侧选择一个默认收藏夹",
                        kind: .warning
                    )
                },
                onDiscard: { id in
                    discardCurrent(id: id)
                },
                onSnooze: { id, days in
                    snoozeCurrent(id: id, days: days)
                },
                onZoomChanged: { zoomed, scale in
                    isZoomed = zoomed
                    zoomScale = scale
                }
            )
            .overlay(alignment: .topTrailing) {
                if isZoomed {
                    Text(String(format: "%.1f×", zoomScale))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Text.secondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)
                        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.trailing, Theme.Spacing.xl)
                        .allowsHitTesting(false)
                }
            }

            infoBar

            Text("轻点全屏 · 上滑延后 · 左滑保险箱 · 右滑收藏夹 · 下滑待销毁")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .padding(.bottom, Theme.Spacing.sm)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, Theme.Spacing.sm)
        }
        .scaleEffect(isAlbumsDrawerPresented ? 0.96 : 1)
        .animation(
            Theme.Motion.animation(.drawer, reduceMotion: reduceMotion),
            value: isAlbumsDrawerPresented
        )
    }

    // MARK: - 销毁坞

    private var isDockExpanded: Bool {
        task.destroyCount > 0
    }

    private var dockSection: some View {
        DestroyDock(
            machine: destroy.machine,
            phase: destroy.phase,
            progress: destroy.progress,
            pendingCount: task.destroyCount,
            isExpanded: isDockExpanded,
            bottomInset: max(0, bottomSafeInset - 8),
            onTapMouth: {
                requestDiscardCurrent()
            }
        )
    }

    /// 模拟器/无 Home indicator 的设备上安全区为 0，此时补 8pt 避免贴边。
    private var bottomSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first?
            .safeAreaInsets.bottom ?? 0
    }

    private func vaultDrawer(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { closeVaultDrawer() }

            VaultPreviewDrawer(
                isVIP: entitlements.isVIP,
                currentItem: currentItem,
                thumbnails: library.thumbnails,
                showsCloseButton: true,
                onUnlock: { openVault() },
                onStoreCurrent: { storeCurrentInVault() },
                onClose: { closeVaultDrawer() }
            )
            .frame(width: min(width * 0.82, 320))
            .frame(maxHeight: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomTrailingRadius: Theme.Radius.drawer,
                    topTrailingRadius: Theme.Radius.drawer,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.2), radius: 18, x: 6, y: 0)
            .transition(.move(edge: .leading))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    private func albumsDrawer(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { closeAlbums() }

            AlbumsPanel(
                albums: albumService,
                selectedAlbumID: settings.defaultAlbumID,
                showsCloseButton: true,
                onSelect: { item in
                    if let item {
                        selectDefaultAlbum(item)
                    }
                    closeAlbums()
                },
                onClose: { closeAlbums() }
            )
            .frame(width: min(width * 0.78, Theme.Metrics.drawerMaxWidth))
            .frame(maxHeight: .infinity)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.Radius.drawer,
                    bottomLeadingRadius: Theme.Radius.drawer,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.2), radius: 18, x: -6, y: 0)
            .transition(.move(edge: .trailing))
        }
        .transition(.opacity)
    }

    private var infoBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let item = currentItem {
                Text(item.shortDateText)
                Text("·").foregroundStyle(Theme.Text.tertiary)
                Text(item.kind.displayName)
                Text("·").foregroundStyle(Theme.Text.tertiary)
                Text("\(Int(item.pixelSize.width))×\(Int(item.pixelSize.height))")
            } else {
                Text("—")
            }
        }
        .font(Theme.Typography.caption.monospacedDigit())
        .foregroundStyle(Theme.Text.secondary)
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 36)
        .neuSurface(.inset, cornerRadius: Theme.Radius.card)
        .padding(.horizontal, Theme.Spacing.page)
    }

    private func presentOnboardingIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_DONE"] == "1" { return }
        #endif
        guard !hasCompletedOnboarding, library.accessState.canBrowse else { return }
        isOnboardingPresented = true
    }

    // MARK: - 状态

    /// 舞台上仍可处理的照片序列：即任务里还没决定去向的照片。
    private var visibleItems: [PhotoItem] {
        guard task.isActive else { return [] }
        return task.remainingItems
    }

    private var stageIndex: Int {
        guard let currentID,
              let index = visibleItems.firstIndex(where: { $0.id == currentID }) else {
            return 0
        }
        return index
    }

    private var currentItem: PhotoItem? {
        let visible = visibleItems
        guard !visible.isEmpty else { return nil }
        if let currentID,
           let index = visible.firstIndex(where: { $0.id == currentID }) {
            return visible[index]
        }
        return visible.first
    }

    // MARK: - 动作

    private func requestAccess() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        Task {
            await library.requestAccess()
            isRequestingAccess = false
            restoreTaskIfNeeded()
            clampCurrentID()
            await albumService.load(force: true)
        }
    }

    // MARK: 任务

    private func startTask(album: AlbumItem?) {
        let albumID = album?.id
        let title = album?.title ?? "全部照片"

        // 延后未到期的照片不进入本批；多取一些再截断，保证凑满 100。
        let snoozedIDs = snooze.activeIDs
        let rawItems = library.taskItems(
            albumLocalID: albumID,
            limit: TaskPolicy.batchSize + snoozedIDs.count
        )
        let items = Array(
            rawItems
                .filter { !snoozedIDs.contains($0.id) }
                .prefix(TaskPolicy.batchSize)
        )
        guard !items.isEmpty else {
            toastMessage = ToastMessage(
                text: "这个相簿里没有可整理的照片",
                kind: .warning
            )
            return
        }

        if task.isActive {
            let hadProgress = task.processedCount > 0
            task.reset()
            if hadProgress {
                toastMessage = ToastMessage(text: "已放弃上一批未执行的决策", kind: .info)
            }
        }
        resetStage()

        task.start(albumLocalID: albumID, albumTitle: title, items: items)
        currentID = task.remainingItems.first?.id
        isWorkspacePresented = true
        closeAlbums()
        closeVaultDrawer()

        if task.isFinished {
            Task { await executeTaskEnd() }
        }
    }

    private func enterWorkspace() {
        guard task.isActive else {
            isAlbumPickerPresented = true
            return
        }
        clampCurrentID()
        isWorkspacePresented = true
        if task.isFinished {
            Task { await executeTaskEnd() }
        }
    }

    private func pauseTask() {
        isWorkspacePresented = false
        isAlbumsDrawerPresented = false
        isVaultDrawerPresented = false
        resetStage()
        toastMessage = ToastMessage(text: "已保留本批进度，下次可继续", kind: .info)
    }

    private func restoreTaskIfNeeded() {
        guard task.isActive, library.accessState.canBrowse else { return }
        let restored = LibraryService.items(for: task.assetIDs)
        task.restore(from: restored)
        if !task.isActive {
            toastMessage = ToastMessage(
                text: "上次整理的照片已不在相册，任务已清空",
                kind: .info
            )
        }
    }

    private func handleTaskProgress() {
        if task.isFinished {
            // 留出最后一张的退场/关门动画时间，再进入统一结算。
            Task {
                try? await Task.sleep(for: .milliseconds(420))
                await executeTaskEnd()
            }
        } else {
            clampCurrentID()
        }
    }

    // MARK: 任务结算

    /// 任务结束：保险箱队列先复制加密，废纸篓队列交给系统删除。
    /// 不再弹 App 自建确认框；两个队列都整批一次提交，系统各弹一次确认。
    private func executeTaskEnd() async {
        guard task.isActive, task.isFinished, !isExecutingTaskEnd else { return }
        isExecutingTaskEnd = true
        defer { isExecutingTaskEnd = false }

        let total = task.totalCount
        let kept = task.keepCount
        let snoozed = task.snoozeCount
        let vaultIDs = task.vaultIDs
        let destroyIDs = task.destroyIDs
        let vaultKinds = task.kinds(for: vaultIDs)
        let albumTitle = task.albumTitle

        var encrypted = 0
        var deleted = 0
        var vaultCancelled = 0
        var destroyCancelled = 0
        var vaultFailed = 0
        var destroyFailed = 0

        let sampleTask: Task<ByteSample, Never>? = destroyIDs.isEmpty
            ? nil
            : Task { await StatisticsService.sampleBytes(localIDs: destroyIDs) }

        // 1) 加密阶段：只写副本，不删除原件。单张复制失败只跳过该张。
        var stagedRecords: [VaultRecord] = []
        if !vaultIDs.isEmpty {
            let staged = await vault.stageAssets(
                localIDs: vaultIDs,
                kinds: vaultKinds,
                entitlements: entitlements
            )
            stagedRecords = staged.records
            vaultFailed = vaultIDs.count - stagedRecords.count
        }

        // 2) 合并删除：保险箱成功副本对应的原件 + 废纸篓，一次 performChanges。
        //    系统只会弹一次确认框；已不在相册的资产由 DeleteService 预剔，不拖垮整批。
        let stagedOriginIDs = stagedRecords.compactMap(\.originLocalID)
        let combinedIDs = stagedOriginIDs + destroyIDs
        var cancelled = false
        if !combinedIDs.isEmpty {
            do {
                let outcome = try await performCombinedDelete(combinedIDs)
                let removedSet = Set(outcome.deletedIDs + outcome.missingIDs)
                encrypted = stagedOriginIDs.filter { removedSet.contains($0) }.count
                deleted = destroyIDs.filter { removedSet.contains($0) }.count
            } catch {
                if DeleteService.isUserCancelled(error) {
                    // 系统框取消：回滚本次写入的全部副本，两个队列都按取消计入。
                    cancelled = true
                    vaultCancelled = vault.rollbackStaged(stagedRecords)
                    destroyCancelled = destroyIDs.count
                } else {
                    // 非取消失败：副本保留并标记待移出，结算页分别给出加密数与删除失败数。
                    vault.markPendingRemoval(stagedRecords)
                    encrypted = stagedRecords.count
                    destroyFailed = destroyIDs.count
                }
            }
        }

        // 3) 成功路径提交副本，统计与刷新。
        if !cancelled, destroyFailed == 0 {
            vault.commitStaged(stagedRecords)
        }
        if encrypted > 0 {
            statistics.recordImport(count: encrypted)
            sound.play(.vaultImport)
        }

        let sample = await sampleTask?.value ?? ByteSample()
        if deleted > 0 {
            statistics.recordDestroy(
                count: deleted,
                sample: sample.scoped(to: destroyIDs),
                machine: destroy.machine
            )
            sound.play(.destroyFinish)
        }

        library.excludedLocalIDs = vault.originLocalIDs
        await library.refresh()

        let cancelledCount = vaultCancelled + destroyCancelled
        let failedCount = vaultFailed + destroyFailed

        let result = TaskSettlement(
            albumTitle: albumTitle,
            total: total,
            kept: kept,
            snoozed: snoozed,
            encrypted: encrypted,
            deleted: deleted,
            cancelled: cancelledCount,
            failed: failedCount
        )

        task.reset()
        resetStage()
        isWorkspacePresented = false
        settlement = result
    }

    /// 保险箱原件与废纸篓合并后的唯一一次删除请求；Debug 的模拟开关沿用原有行为。
    private func performCombinedDelete(_ ids: [String]) async throws -> DeleteOutcome {
        #if DEBUG
        if DebugOptions.isSimulatingDestroy {
            try? await Task.sleep(for: .milliseconds(200))
            return DeleteOutcome(deletedIDs: ids, missingIDs: [])
        }
        #endif
        return try await library.delete(localIDs: ids)
    }

    // MARK: 决策

    private func resetStage() {
        currentID = nil
        isZoomed = false
        zoomScale = 1
    }

    private func openAlbums() {
        isVaultDrawerPresented = false
        withAnimation(Theme.Motion.animation(.drawer, reduceMotion: reduceMotion)) {
            isAlbumsDrawerPresented = true
        }
    }

    private func closeAlbums() {
        withAnimation(Theme.Motion.animation(.drawer, reduceMotion: reduceMotion)) {
            isAlbumsDrawerPresented = false
        }
    }

    /// 保证 currentID 指向仍可处理的照片；决策/照片库刷新后调用。
    private func clampCurrentID() {
        let visible = visibleItems
        guard !visible.isEmpty else {
            currentID = nil
            return
        }
        if let currentID, visible.contains(where: { $0.id == currentID }) { return }
        currentID = visible.first?.id
    }

    /// 下一张 = 保留：记录决策并把舞台推进到下一张。
    private func advanceCurrent(from id: String) {
        guard task.isActive, !isExecutingTaskEnd else { return }
        let visible = visibleItems
        guard visible.contains(where: { $0.id == id }) else {
            clampCurrentID()
            return
        }

        let nextID = idAfterRemoving(id)
        task.record(id: id, decision: .keep)
        currentID = nextID
        isZoomed = false
        zoomScale = 1
        #if DEBUG
        NSLog("[task] keep %@ -> %@", id, nextID ?? "nil")
        #endif
        handleTaskProgress()
    }

    /// 移除一张之后舞台应该停在哪：优先后一张，若已到末尾则回到前一张。
    private func idAfterRemoving(_ id: String) -> String? {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return nil }
        if visible.indices.contains(index + 1) {
            return visible[index + 1].id
        }
        if index > 0 {
            return visible[index - 1].id
        }
        return nil
    }

    // MARK: 全屏与延后

    private func openFullscreen(id: String) {
        guard visibleItems.contains(where: { $0.id == id }) else { return }
        fullscreenRequest = FullscreenRequest(id: id)
    }

    /// 上滑落库：写入到期时间并记录“延后”决策，本批不再出现。
    private func snoozeCurrent(id: String, days: Int) {
        guard task.isActive, !isExecutingTaskEnd else { return }
        guard let item = task.items.first(where: { $0.id == id }) else { return }

        let nextID = idAfterRemoving(id)
        snooze.snooze(id: item.id, days: days)
        task.record(id: id, decision: .snooze)

        currentID = nextID
        isZoomed = false
        zoomScale = 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toastMessage = ToastMessage(
            text: "已延后 \(days) 天，本批不再出现",
            kind: .success
        )
        handleTaskProgress()
    }

    private func wakeUpSnoozed(id: String) {
        snooze.unsnooze(id: id)
        toastMessage = ToastMessage(text: "已恢复，将出现在下一批", kind: .info)
    }

    private func wakeAllSnoozed() {
        guard snooze.count > 0 else { return }
        snooze.wakeAll()
        toastMessage = ToastMessage(text: "全部恢复，将出现在下一批", kind: .info)
    }

    // MARK: 收藏夹

    private func selectDefaultAlbum(_ album: AlbumItem) {
        settings.setDefaultAlbum(id: album.id, title: album.title)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 相簿列表变化后保证默认收藏夹仍有效；第一次进入时默认选第一本。
    private func syncDefaultAlbum() {
        guard !albumService.isLoading else { return }
        let albums = albumService.userAlbums
        if let id = settings.defaultAlbumID,
           albums.contains(where: { $0.id == id }) {
            return
        }
        if let first = albums.first {
            settings.setDefaultAlbum(id: first.id, title: first.title)
        } else {
            settings.setDefaultAlbum(id: nil, title: "未选择")
        }
    }

    /// 右滑：加入默认相簿，同时记录“保留”决策并推进。
    private func favoriteSwipe(_ id: String) {
        guard task.isActive, !isExecutingTaskEnd else { return }
        guard let albumID = settings.defaultAlbumID else {
            toastMessage = ToastMessage(text: "先在右侧选择一个默认收藏夹", kind: .warning)
            return
        }

        favoritesReceiving = true

        let nextID = idAfterRemoving(id)
        task.record(id: id, decision: .keep)
        currentID = nextID
        isZoomed = false
        zoomScale = 1
        handleTaskProgress()

        Task {
            do {
                try await albumService.addAssets([id], toAlbum: albumID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toastMessage = ToastMessage(
                    text: "已加入「\(settings.defaultAlbumTitle)」",
                    kind: .success
                )
            } catch {
                toastMessage = ToastMessage(
                    text: error.localizedDescription,
                    kind: .warning
                )
            }

            try? await Task.sleep(for: .milliseconds(240))
            favoritesReceiving = false
            await albumService.load(force: true)
            syncDefaultAlbum()
        }
    }

    // MARK: 保险箱

    /// 左滑：只记录“保险箱”决策并打开箱门；任务结束才统一加密。
    private func vaultSwipe(_ id: String) {
        guard task.isActive, !isExecutingTaskEnd else { return }

        let nextID = idAfterRemoving(id)
        task.record(id: id, decision: .vault)
        currentID = nextID
        isZoomed = false
        zoomScale = 1

        withAnimation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.28)
        ) {
            vaultDoorOpen = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(.easeOut(duration: 0.25)) {
                vaultDoorOpen = false
            }
        }

        handleTaskProgress()
    }

    private func openVaultPreview() {
        isAlbumsDrawerPresented = false
        withAnimation(Theme.Motion.animation(.drawer, reduceMotion: reduceMotion)) {
            isVaultDrawerPresented = true
        }
    }

    private func closeVaultDrawer() {
        withAnimation(Theme.Motion.animation(.drawer, reduceMotion: reduceMotion)) {
            isVaultDrawerPresented = false
        }
    }

    private func openVault() {
        isVaultDrawerPresented = false
        isAlbumsDrawerPresented = false
        isVaultPresented = true
    }

    /// 抽屉里的“存入当前照片”走同一条保险箱决策。
    private func storeCurrentInVault() {
        guard let item = currentItem else { return }
        closeVaultDrawer()
        vaultSwipe(item.id)
    }

    // MARK: 销毁

    /// 点击坞口只触发一次“下滑入待销毁”，真正的决策发生在舞台回调里。
    private func requestDiscardCurrent() {
        guard task.isActive, !isExecutingTaskEnd else { return }
        guard currentItem != nil else {
            toastMessage = ToastMessage(text: "当前没有可加入的照片", kind: .warning)
            return
        }
        discardRequest += 1
    }

    /// 舞台完成下滑动画后调用：记录“废纸篓”决策并推进。
    private func discardCurrent(id: String) {
        guard task.isActive, !isExecutingTaskEnd else { return }
        guard task.items.contains(where: { $0.id == id }) else { return }

        let nextID = idAfterRemoving(id)
        task.record(id: id, decision: .destroy)
        currentID = nextID
        isZoomed = false
        zoomScale = 1
        handleTaskProgress()
    }

    /// UI 测试用：确保有任务可操作。
    private func ensureUITestTask() {
        guard !task.isActive else {
            isWorkspacePresented = true
            clampCurrentID()
            return
        }
        let snoozedIDs = snooze.activeIDs
        let rawItems = library.taskItems(
            albumLocalID: nil,
            limit: TaskPolicy.batchSize + snoozedIDs.count
        )
        let items = Array(
            rawItems
                .filter { !snoozedIDs.contains($0.id) }
                .prefix(TaskPolicy.batchSize)
        )
        guard !items.isEmpty else { return }
        task.start(albumLocalID: nil, albumTitle: "全部照片", items: items)
        isWorkspacePresented = true
        currentID = task.remainingItems.first?.id
    }

    /// UI 测试钩子；正常启动不会触发。
    private func runUITestHooksIfNeeded() async {
        let environment = ProcessInfo.processInfo.environment

        #if DEBUG
        if let simulate = environment["UI_TEST_SIMULATE_DESTROY"] {
            DebugOptions.setSimulatingDestroy(simulate == "1")
        }
        #endif

        #if DEBUG
        if environment["UI_TEST_VAULT_SELFCHECK"] == "1" {
            try? await Task.sleep(for: .milliseconds(700))
            try? vault.configure(a: 7, b: 23)
            vault.lock()
            let wrong = await vault.unlock(a: 3, b: 3)
            let right = await vault.unlock(a: 7, b: 23)
            let tier5 = VaultLockPolicy.lockDuration(failures: 5, recentCount: 5) ?? -1
            let tier9 = VaultLockPolicy.lockDuration(failures: 9, recentCount: 9) ?? -1
            let recent10 = VaultLockPolicy.lockDuration(failures: 10, recentCount: 10) ?? -1
            toastMessage = ToastMessage(
                text: "wrong=\(wrong) | right=\(right) | tier5=\(Int(tier5)) tier9=\(Int(tier9)) recent10=\(Int(recent10))",
                kind: .success
            )
            return
        }
        #endif

        if environment["UI_TEST_VAULT_DEMO"] == "1" {
            try? await Task.sleep(for: .milliseconds(900))
            let ids = library.items.prefix(2).map(\.id)
            if !ids.isEmpty {
                let kinds = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0.kind) })
                let staged = await vault.stageAssets(
                    localIDs: ids,
                    kinds: kinds,
                    entitlements: entitlements
                )
                vault.commitStaged(staged.records)
            }
            try? vault.configure(a: 7, b: 23)
            try? await Task.sleep(for: .milliseconds(300))
            isVaultPresented = true
            return
        }
        if environment["UI_TEST_VAULT_SETUP"] == "1" {
            #if DEBUG
            VaultCredentials.debugReset()
            VaultLockPolicy.reset()
            #endif
            try? await Task.sleep(for: .milliseconds(600))
            isVaultPresented = true
            return
        }
        if environment["UI_TEST_VAULT_LOCK_DEMO"] == "1" {
            try? await Task.sleep(for: .milliseconds(700))
            try? vault.configure(a: 7, b: 23)
            vault.lock()
            isVaultPresented = true
            return
        }
        if environment["UI_TEST_VAULT_DRAWER"] == "1" {
            try? await Task.sleep(for: .milliseconds(700))
            openVaultPreview()
            return
        }
        if environment["UI_TEST_OPEN_VAULT"] == "1" {
            try? await Task.sleep(for: .milliseconds(600))
            isVaultPresented = true
            return
        }
        if environment["UI_TEST_OPEN_DESIGN_SYSTEM"] == "1" {
            try? await Task.sleep(for: .milliseconds(400))
            isDesignSystemPresented = true
            return
        }
        if environment["UI_TEST_OPEN_ALBUMS"] == "1" {
            try? await Task.sleep(for: .milliseconds(400))
            ensureUITestTask()
            isAlbumsDrawerPresented = true
            return
        }
        if environment["UI_TEST_STAGE_DISCARD"] == "1" {
            try? await Task.sleep(for: .milliseconds(1000))
            ensureUITestTask()
            discardRequest += 1
            return
        }
        if environment["UI_TEST_STAGE_TAP"] == "1" {
            try? await Task.sleep(for: .milliseconds(1000))
            ensureUITestTask()
            tapRequest += 1
            return
        }
        if environment["UI_TEST_STAGE_TAP_NIL"] == "1" {
            try? await Task.sleep(for: .milliseconds(1000))
            ensureUITestTask()
            currentID = nil
            try? await Task.sleep(for: .milliseconds(300))
            tapRequest += 1
            return
        }
        if let raw = environment["UI_TEST_STAGE_PENDING"], let count = Int(raw) {
            try? await Task.sleep(for: .milliseconds(700))
            ensureUITestTask()
            for _ in 0..<count {
                guard let id = currentItem?.id else { break }
                discardCurrent(id: id)
                try? await Task.sleep(for: .milliseconds(40))
            }
            return
        }
        if environment["UI_TEST_MACHINE"] == "shredder" {
            try? await Task.sleep(for: .milliseconds(600))
            ensureUITestTask()
            destroy.switchMachine(.shredder)
            return
        }

        #if DEBUG
        if let mode = environment["UI_TEST_DISPLAY_MODE"].flatMap(DisplayMode.init(rawValue:)) {
            settings.displayMode = mode
        }
        if let highContrast = environment["UI_TEST_HIGH_CONTRAST"] {
            settings.highContrast = highContrast == "1"
        }
        if let reduceMotion = environment["UI_TEST_REDUCE_MOTION"] {
            settings.reduceMotion = reduceMotion == "1"
        }
        if let soundOff = environment["UI_TEST_SOUND_OFF"] {
            settings.soundEnabled = soundOff != "1"
        }
        if let vip = environment["UI_TEST_VIP"] {
            entitlements.setVIP(vip == "1")
        }
        if environment["UI_TEST_TOGGLE_DISPLAY"] == "1" {
            Task {
                try? await Task.sleep(for: .seconds(2))
                settings.displayMode = .dark
            }
        }
        if environment["UI_TEST_STATS_RESET"] == "1" {
            statistics.reset()
        }
        if environment["UI_TEST_ONBOARDING_DONE"] == "1" {
            hasCompletedOnboarding = true
            isOnboardingPresented = false
        }
        if environment["UI_TEST_OPEN_ONBOARDING"] == "1" {
            hasCompletedOnboarding = false
            isOnboardingPresented = true
        }
        if environment["UI_TEST_STATS_SELFCHECK"] == "1" {
            try? await Task.sleep(for: .milliseconds(700))
            statistics.seedSelfCheckSamples()
            toastMessage = ToastMessage(text: statistics.selfCheckReport(), kind: .success)
            return
        }
        if environment["UI_TEST_SEED_STATS"] == "1" {
            try? await Task.sleep(for: .milliseconds(500))
            statistics.seedSelfCheckSamples()
        }
        if environment["UI_TEST_OPEN_STATS"] == "1" {
            try? await Task.sleep(for: .milliseconds(800))
            settingsInitialRoute = .statistics
            try? await Task.sleep(for: .milliseconds(150))
            isSettingsPresented = true
            return
        }
        if environment["UI_TEST_OPEN_VIP"] == "1" {
            try? await Task.sleep(for: .milliseconds(800))
            settingsInitialRoute = .vip
            try? await Task.sleep(for: .milliseconds(150))
            isSettingsPresented = true
            return
        }
        if environment["UI_TEST_OPEN_ABOUT"] == "1" {
            try? await Task.sleep(for: .milliseconds(800))
            settingsInitialRoute = .about
            try? await Task.sleep(for: .milliseconds(150))
            isSettingsPresented = true
            return
        }
        #endif
    }
}
