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
    @State private var isSettingsPresented = false
    @State private var settingsInitialRoute: SettingsRoute?
    @State private var isDesignSystemPresented = false
    @AppStorage("onboarding.completed") private var hasCompletedOnboarding = false
    @State private var isOnboardingPresented = false
    @State private var isRequestingAccess = false
    @State private var isAlbumsDrawerPresented = false

    @State private var isVaultPresented = false
    @State private var isVaultDrawerPresented = false
    @State private var isVaultImportConfirmPresented = false
    @State private var pendingVaultImportIDs: [String] = []
    /// 左滑存入保险箱时同步打开箱门；确认弹窗出现后自动合上。
    @State private var vaultDoorOpen = false
    /// 右滑存入收藏夹时给选中相簿一个强调脉冲。
    @State private var favoritesReceiving = false

    /// 当前照片的稳定标识；待销毁累积变化时仍能指向同一张。
    @State private var currentID: String?
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1

    @State private var destroy = DestroyCoordinator()
    /// 坞口被点击时自增，舞台据此播放一次“下滑入待销毁”的等效动画。
    @State private var discardRequest = 0
    /// UI 测试用：自增触发一次舞台轻点。
    @State private var tapRequest = 0
    @State private var isDestroyConfirmPresented = false
    @State private var hasAutoPromptedBatch = false
    @State private var toastMessage: ToastMessage?
    /// 销毁开始前启动的字节采样；成功后在结果回调里取用。
    @State private var pendingDestroySampleTask: Task<ByteSample, Never>?

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
                    libraryContent
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
            .fullScreenCover(isPresented: $isDesignSystemPresented) {
                NavigationStack {
                    DesignSystemPreviewView()
                }
            }
            .fullScreenCover(isPresented: $isVaultPresented) {
                VaultLockView()
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingView {
                    hasCompletedOnboarding = true
                    isOnboardingPresented = false
                }
            }
            .alert("存入保险箱", isPresented: $isVaultImportConfirmPresented) {
                Button("取消", role: .cancel) {
                    pendingVaultImportIDs = []
                }
                Button("存入") {
                    runVaultImport()
                }
            } message: {
                Text("将复制原图到 App 保险箱，并从系统相簿删除这些照片（会进入『最近删除』保留 30 天）。")
            }
            .alert(
                "确认销毁 \(destroy.tickets.count) 张照片？",
                isPresented: $isDestroyConfirmPresented
            ) {
                Button("取消", role: .cancel) {}
                Button("销毁", role: .destructive) {
                    startDestroying(ids: destroy.tickets.map(\.id))
                }
            } message: {
                Text("确认后交由系统相簿删除；原件进入『最近删除』，保留 30 天。")
            }
            .task {
                library.excludedLocalIDs = vault.originLocalIDs
                await library.start()
                await albumService.load()
                syncDefaultAlbum()
                clampCurrentID()
                presentOnboardingIfNeeded()
                await runUITestHooksIfNeeded()
            }
            .onChange(of: library.accessState) { _, state in
                if state.canBrowse, !hasCompletedOnboarding {
                    isOnboardingPresented = true
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
            .onChange(of: destroy.tickets.count) { _, count in
                handlePendingCountChange(count)
            }
            .onChange(of: destroy.lastOutcome) { _, outcome in
                Task { await handleDestroyOutcome(outcome) }
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
        HStack(spacing: Theme.Spacing.md) {
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

            Text("SuperPhotos")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(entitlements.isVIP ? "VIP（模拟）" : "免费版")
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(entitlements.isVIP ? Theme.Accent.fire : Theme.Text.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 3)
                .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)

            Spacer()

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

    // MARK: - 主内容

    private var libraryContent: some View {
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

                FilterBar(
                    selectedKind: library.filter.mediaKind,
                    albumTitle: library.filter.albumTitle,
                    showsAlbumButton: true,
                    onSelectKind: { applyKind($0) },
                    onOpenAlbums: { openAlbums() }
                )

                stageHeader

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    VaultDoorColumn(
                        width: sideWidth,
                        count: vault.records.count,
                        isConfigured: vault.isConfigured,
                        isOpen: vaultDoorOpen,
                        onTap: { openVaultPreview() }
                    )

                    Group {
                        if library.items.isEmpty {
                            emptyState
                        } else {
                            stageSection(sideWidth: sideWidth)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    FavoriteAlbumColumn(
                        width: sideWidth,
                        albums: albumService.userAlbums,
                        selectedAlbumID: settings.defaultAlbumID,
                        isReceiving: favoritesReceiving,
                        onSelect: { selectDefaultAlbum($0) },
                        onOpenAlbums: { openAlbums() }
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
                isInteractionEnabled: !isAlbumsDrawerPresented && !isVaultDrawerPresented,
                canDiscard: destroy.tickets.count < entitlements.batchLimit(),
                canFavorite: settings.defaultAlbumID != nil,
                discardRequest: discardRequest,
                tapRequest: tapRequest,
                sideDropOffset: sideWidth + Theme.Spacing.sm + 26,
                onAdvance: { id in
                    advanceCurrent(from: id)
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

            Text("轻点看下一张 · 左滑存保险箱 · 右滑存收藏夹 · 下滑待销毁")
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
        !destroy.tickets.isEmpty || destroy.phase.isBusy
    }

    private var dockSection: some View {
        DestroyDock(
            machine: destroy.machine,
            phase: destroy.phase,
            progress: destroy.progress,
            tickets: destroy.tickets,
            pendingCount: destroy.pendingCount,
            autoConfirmThreshold: DestroyPolicy.autoConfirmThreshold,
            thumbnails: library.thumbnails,
            isExpanded: isDockExpanded,
            bottomInset: max(0, bottomSafeInset - 8),
            onSwitchMachine: { kind in
                destroy.switchMachine(kind)
            },
            onTapMouth: {
                requestDiscardCurrent()
            },
            onStart: {
                guard !destroy.tickets.isEmpty else { return }
                isDestroyConfirmPresented = true
            },
            onCancel: {
                destroy.cancel()
            },
            onClear: {
                destroy.clearQueue()
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
                selectedAlbumID: library.filter.albumLocalID,
                showsCloseButton: true,
                onSelect: { selectAlbum($0) },
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

    private var stageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(library.filter.title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)

            Spacer()

            if !library.items.isEmpty {
                Text(pageLabel)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
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

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.Text.tertiary)
            Text("这个范围里没有照片")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Text.secondary)

            if library.filter != .all {
                Button("清除筛选") {
                    Task { await library.setFilter(.all) }
                }
                .buttonStyle(NeuButtonStyle(variant: .raisedSmall, cornerRadius: Theme.Radius.chip))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentOnboardingIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_DONE"] == "1" { return }
        #endif
        guard !hasCompletedOnboarding, library.accessState.canBrowse else { return }
        isOnboardingPresented = true
    }

    // MARK: - 状态

    /// 待销毁累积中的照片不再出现在舞台上。
    private var pendingIDs: Set<String> {
        Set(destroy.tickets.map(\.id))
    }

    /// 舞台上仍可浏览的照片序列。
    private var visibleItems: [PhotoItem] {
        let pending = pendingIDs
        return library.items.filter { !pending.contains($0.id) }
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

    private var pageLabel: String {
        let position = visibleItems.isEmpty ? 0 : min(stageIndex + 1, visibleItems.count)
        let total = visibleItems.count
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let p = formatter.string(from: NSNumber(value: position)) ?? "\(position)"
        let t = formatter.string(from: NSNumber(value: total)) ?? "\(total)"
        return "\(p) / \(t)"
    }

    // MARK: - 动作

    private func requestAccess() {
        guard !isRequestingAccess else { return }
        isRequestingAccess = true
        Task {
            await library.requestAccess()
            isRequestingAccess = false
            clampCurrentID()
            await albumService.load(force: true)
        }
    }

    // MARK: 筛选

    private func applyKind(_ kind: MediaKind?) {
        var filter = library.filter
        filter.mediaKind = kind
        Task { await library.setFilter(filter) }
        resetStage()
    }

    private func selectAlbum(_ item: AlbumItem?) {
        var filter = library.filter
        filter.albumLocalID = item?.id
        filter.albumTitle = item?.title ?? "全部照片"
        Task { await library.setFilter(filter) }
        resetStage()
        closeAlbums()
    }

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

    /// 保证 currentID 指向仍可见的照片；筛选/照片库刷新后调用。
    private func clampCurrentID() {
        let visible = visibleItems
        guard !visible.isEmpty else {
            currentID = nil
            return
        }
        if let currentID, visible.contains(where: { $0.id == currentID }) { return }
        currentID = visible.first?.id
    }

    /// 轻点换牌：以舞台实际动画的那张照片为锚点推进，避免与派生状态分叉。
    private func advanceCurrent(from id: String) {
        let visible = visibleItems
        guard let index = visible.firstIndex(where: { $0.id == id }) else {
            clampCurrentID()
            return
        }
        let nextIndex = index + 1
        guard visible.indices.contains(nextIndex) else { return }

        currentID = visible[nextIndex].id
        isZoomed = false
        zoomScale = 1
        #if DEBUG
        NSLog("[stage] advance %@ -> %@", id, visible[nextIndex].id)
        #endif
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

    /// 右滑：把照片加入默认相簿，成功后推进到下一张。
    private func favoriteSwipe(_ id: String) {
        guard let albumID = settings.defaultAlbumID else {
            toastMessage = ToastMessage(text: "先在右侧选择一个默认收藏夹", kind: .warning)
            return
        }

        favoritesReceiving = true
        Task {
            do {
                try await albumService.addAssets([id], toAlbum: albumID)
                advanceCurrent(from: id)
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

    /// 左滑：箱门立即打开，照片飞入后再走既有的复制+删除确认流程。
    private func vaultSwipe(_ id: String) {
        withAnimation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.28)
        ) {
            vaultDoorOpen = true
        }

        Task {
            // 让飞入动效先完成，再弹确认，避免弹窗遮住“门开照片进”的过程。
            try? await Task.sleep(for: .milliseconds(360))
            requestVaultImport(ids: [id])
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.25)) {
                vaultDoorOpen = false
            }
        }
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

    private func storeCurrentInVault() {
        guard let item = currentItem else { return }
        closeVaultDrawer()
        requestVaultImport(ids: [item.id])
    }

    private func requestVaultImport(ids: [String]) {
        guard !ids.isEmpty else { return }
        pendingVaultImportIDs = ids
        isVaultImportConfirmPresented = true
    }

    private func runVaultImport() {
        let ids = pendingVaultImportIDs
        pendingVaultImportIDs = []
        guard !ids.isEmpty else { return }

        // 删除完成后这张就不在列表里了，先记下舞台应该停在哪。
        let nextID = ids.first.flatMap { idAfterRemoving($0) }
        let kinds = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0.kind) })
        Task {
            let summary = await vault.importAssets(
                localIDs: ids,
                kinds: kinds,
                entitlements: entitlements,
                simulateRemoval: simulateVaultRemoval
            )
            library.excludedLocalIDs = vault.originLocalIDs
            await library.refresh()
            handleVaultImportSummary(summary, nextID: nextID)
        }
    }

    private var simulateVaultRemoval: Bool {
        #if DEBUG
        DebugOptions.isSimulatingDestroy
        #else
        false
        #endif
    }

    private func handleVaultImportSummary(_ summary: VaultStore.ImportSummary, nextID: String?) {
        if summary.imported > 0 {
            statistics.recordImport(count: summary.imported)
            sound.play(.vaultImport)
            let base = "已存入保险箱 \(summary.imported) 件"
            if summary.removalPending {
                toastMessage = ToastMessage(
                    text: base + "；原件仍在相册，可在房间内重试移出",
                    kind: .warning
                )
            } else {
                toastMessage = ToastMessage(
                    text: base + "，原件已移入系统『最近删除』",
                    kind: .success
                )
            }
            // 原图已从相簿移除：停在原先记下的下一张，不再退回列表头部。
            currentID = nextID
            clampCurrentID()
            return
        }

        if let message = summary.messages.first {
            toastMessage = ToastMessage(text: message, kind: .warning)
        }
    }

    // MARK: 销毁

    /// 点击坞口只触发一次“下滑入待销毁”，真正的入队发生在舞台回调里。
    private func requestDiscardCurrent() {
        guard destroy.phase == .idle || destroy.phase == .finished else { return }
        guard currentItem != nil else {
            toastMessage = ToastMessage(text: "当前没有可加入的照片", kind: .warning)
            return
        }
        guard destroy.tickets.count < entitlements.batchLimit() else {
            toastMessage = ToastMessage(text: "累积已满，先销毁或清空", kind: .warning)
            return
        }
        discardRequest += 1
    }

    /// 舞台完成下滑动画后调用：加入待销毁累积，并把舞台推进到下一张。
    private func discardCurrent(id: String) {
        guard let item = library.items.first(where: { $0.id == id }) else { return }
        guard destroy.phase == .idle || destroy.phase == .finished else { return }

        // 入队后这张会从可见序列里消失，先算出落点。
        let nextID = idAfterRemoving(id)

        let accepted = destroy.enqueue(
            ids: [item.id],
            kinds: [item.id: item.kind],
            limit: entitlements.batchLimit()
        )

        guard accepted > 0 else {
            toastMessage = ToastMessage(text: "累积已满，先销毁或清空", kind: .warning)
            return
        }

        currentID = nextID
        isZoomed = false
        zoomScale = 1
    }

    /// 累积到阈值时自动点亮指示灯并弹出确认；阈值见 DestroyPolicy。
    private func handlePendingCountChange(_ count: Int) {
        if count == 0 {
            hasAutoPromptedBatch = false
            return
        }

        guard count >= DestroyPolicy.autoConfirmThreshold else {
            hasAutoPromptedBatch = false
            return
        }

        guard !hasAutoPromptedBatch, !destroy.phase.isBusy else { return }
        hasAutoPromptedBatch = true
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        isDestroyConfirmPresented = true
    }

    private func startDestroying(ids: [String]) {
        guard !ids.isEmpty, destroy.phase == .idle else { return }
        // 在删除提交前开始采样，蓄力与系统确认期间并行读取，不阻塞流程。
        pendingDestroySampleTask = Task {
            await StatisticsService.sampleBytes(localIDs: ids)
        }
        sound.play(.destroyStart)
        destroy.start { localIDs in
            #if DEBUG
            if DebugOptions.isSimulatingDestroy {
                try? await Task.sleep(for: .milliseconds(400))
                return
            }
            #endif
            try await library.delete(localIDs: localIDs)
        }
    }

    private func handleDestroyOutcome(_ outcome: DestroyOutcome?) async {
        guard let outcome else { return }

        if outcome.wasCancelled {
            pendingDestroySampleTask?.cancel()
            pendingDestroySampleTask = nil
            toastMessage = ToastMessage(
                text: "已取消，未删除任何照片，队列已保留",
                kind: .warning
            )
            return
        }

        let sample: ByteSample
        if let task = pendingDestroySampleTask {
            sample = await task.value
        } else {
            sample = ByteSample()
        }
        pendingDestroySampleTask = nil

        statistics.recordDestroy(
            count: outcome.succeededIDs.count,
            sample: sample.scoped(to: outcome.succeededIDs),
            machine: outcome.machine
        )
        sound.play(.destroyFinish)

        toastMessage = ToastMessage(
            text: "已将 \(outcome.succeededIDs.count) 张移入系统『最近删除』，30 天内可找回",
            kind: .success
        )
    }

    /// UI 测试用：直接把前 count 张加入待销毁累积，不播放舞台动画。
    private func enqueueForUITest(count: Int) {
        let ids = library.items.prefix(count).map(\.id)
        guard !ids.isEmpty else { return }
        let kinds = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0.kind) })
        destroy.enqueue(ids: ids, kinds: kinds, limit: entitlements.batchLimit())
    }

    /// UI 测试钩子；正常启动不会触发。
    private func runUITestHooksIfNeeded() async {
        let arguments = ProcessInfo.processInfo.arguments
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
                _ = await vault.importAssets(
                    localIDs: ids,
                    kinds: kinds,
                    entitlements: entitlements,
                    simulateRemoval: true
                )
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
            isAlbumsDrawerPresented = true
            return
        }
        if environment["UI_TEST_STAGE_DISCARD"] == "1" {
            try? await Task.sleep(for: .milliseconds(1000))
            discardRequest += 1
            return
        }
        if environment["UI_TEST_STAGE_TAP"] == "1" {
            try? await Task.sleep(for: .milliseconds(1000))
            tapRequest += 1
            return
        }
        if environment["UI_TEST_STAGE_TAP_NIL"] == "1" {
            try? await Task.sleep(for: .milliseconds(1000))
            currentID = nil
            try? await Task.sleep(for: .milliseconds(300))
            tapRequest += 1
            return
        }
        if let raw = environment["UI_TEST_STAGE_PENDING"], let count = Int(raw) {
            try? await Task.sleep(for: .milliseconds(700))
            for _ in 0..<count {
                guard let id = currentItem?.id else { break }
                discardCurrent(id: id)
                try? await Task.sleep(for: .milliseconds(40))
            }
            return
        }
        if environment["UI_TEST_ENQUEUE"] == "1" {
            try? await Task.sleep(for: .milliseconds(600))
            enqueueForUITest(count: 3)
            startDestroying(ids: destroy.tickets.map(\.id))
            return
        }
        if environment["UI_TEST_ENQUEUE"] == "2" {
            try? await Task.sleep(for: .milliseconds(600))
            enqueueForUITest(count: 3)
            startDestroying(ids: destroy.tickets.map(\.id))
            try? await Task.sleep(for: .milliseconds(900))
            destroy.cancel()
            return
        }
        if environment["UI_TEST_MACHINE"] == "shredder" {
            try? await Task.sleep(for: .milliseconds(600))
            destroy.switchMachine(.shredder)
            enqueueForUITest(count: 2)
            startDestroying(ids: destroy.tickets.map(\.id))
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

        guard arguments.contains("-ui-test-open-settings")
                || environment["UI_TEST_OPEN_SETTINGS"] == "1" else { return }
        try? await Task.sleep(for: .milliseconds(500))
        isSettingsPresented = true
    }
}

#Preview {
    HomeView()
        .environment(EntitlementStore())
        .environment(VaultStore())
        .environment(AppSettings())
        .environment(StatisticsService())
        .environment(SoundService())
}
