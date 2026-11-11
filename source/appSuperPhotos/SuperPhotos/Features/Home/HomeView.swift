import SwiftUI
import UIKit

/// 桌面 / 舞台的呈现状态。
///
/// 用引用类型而不是 `@State` 值：桌面按钮的 `onResume` 闭包可能持有旧一版
/// `HomeView` 副本，值类型 `@State` 在这种副本上的写入不一定会让已安装的
/// 视图刷新；引用对象的写入始终通知观察者。
@Observable
final class WorkspacePresentation {
    var isPresented = false

    func present() { isPresented = true }
    func dismiss() { isPresented = false }
}

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
    @State private var workspace = WorkspacePresentation()
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

    /// 当前照片的稳定标识；决策记录后仍能指向同一张。
    @State private var currentID: String?
    @State private var isZoomed = false
    @State private var zoomScale: CGFloat = 1

    @State private var destroy = DestroyCoordinator()
    /// 程序化触发一次“下滑入待销毁”（UI 测试与无障碍路径使用）。
    @State private var discardRequest = 0
    /// 照片落入底部道具时自增：按当前道具播放一次专属动效与音效。
    @State private var binShakeToken = 0
    /// 点击底部道具循环切换时自增：驱动切换弹跳与名称牌。
    @State private var deviceSwitchToken = 0
    /// UI 测试用：自增触发一次舞台轻点。
    @State private var tapRequest = 0
    /// UI 测试用：自增触发一次左/右滑飞出（与手势同一条路径）。
    @State private var stageVaultRequest = 0
    @State private var stageFavoriteRequest = 0
    @State private var toastMessage: ToastMessage?
    /// 液晶屏上的瞬时反馈：只保留最新一条，2.4s 后自动清空。
    /// 收藏夹 / 延后 / 待销毁 / 保险箱四类成功反馈都走这里，不再用浮层 Toast。
    @State private var lcdNotice: LCDNotice?
    /// 底部纸篓实测高度：内容落桌时要避开它，短屏上以不压住纸篓优先。
    @State private var dockHeight: CGFloat = 112
    /// 受限访问提示条的实测高度：它占用的那部分要从行高里扣掉。
    @State private var bannerHeight: CGFloat = 0
    /// 顶栏钥匙的提示摆动：冷启动后只触发一次。
    @State private var keySwayToken = 0
    @State private var hasPlayedKeySway = false

    /// 三栏工作区（顶部 LCD 行与底部纸篓之间的「中间区」）高度倍率。
    ///
    /// 1.44 = 在「内容顶 → 台面 / 纸篓上沿」的基准行高上累计放大 44%：
    /// 先在 1.2 基础上再 +20%（1.2 × 1.2）。顶边与 LCD 整行的相对位置不变，
    /// 台面线、纸篓锚点、背景都不动；三栏（照片堆叠、保险箱门、收藏夹滚轮）
    /// 按新行高重算居中落点。想调回原高度把这里改回 1 即可，其它计算无需同步修改。
    private static let workspaceHeightScale: CGFloat = 1.44

    var body: some View {
        NavigationStack {
            ZStack {
                if library.accessState.canBrowse {
                    SceneryBackgroundView()
                } else {
                    Theme.Surface.base.ignoresSafeArea()
                }

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
                    // 首屏不再独立成页：桌面状态就是三栏场景里的中央区域。
                    taskWorkspace
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
                    requestedRoute: $settingsInitialRoute,
                    snooze: snooze,
                    thumbnails: library.thumbnails,
                    onWakeSnoozed: { id in wakeUpSnoozed(id: id) },
                    onWakeAllSnoozed: { wakeAllSnoozed() }
                )
            }
            .sheet(isPresented: $isAlbumPickerPresented) {
                TaskAlbumPickerView(
                    allPhotoCount: albumService.allPhotoCount,
                    uncategorizedCount: albumService.uncategorizedDisplayCount,
                    albums: albumService.userAlbums,
                    onSelect: { selection in
                        isAlbumPickerPresented = false
                        startTask(selection: selection)
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
                albumService.excludedLocalIDs = vault.originLocalIDs
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
            // 进入桌面态 5 秒后，保险箱非空才让顶栏钥匙绕上边中点轻晃一次提示。
            // 冷启动只触发一次；减弱动态效果时由按钮内部把幅度压到 0。
            .task(id: library.accessState.canBrowse) {
                guard library.accessState.canBrowse, !hasPlayedKeySway else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, !hasPlayedKeySway, !vault.records.isEmpty else { return }
                hasPlayedKeySway = true
                keySwayToken += 1
            }
            .onChange(of: library.accessState) { _, state in
                if state.canBrowse {
                    restoreTaskIfNeeded()
                    clampCurrentID()
                    // 授权范围变化（首次授权 / 受限 → 完整）后按新的可见集合重算。
                    Task { await albumService.load(force: true) }
                    if !hasCompletedOnboarding {
                        #if DEBUG
                        // 回归时强制授权会把状态从 notDetermined 推过来，
                        // 没走正常首启流程，不要让引导盖住工作区。
                        if ProcessInfo.processInfo.environment["UI_TEST_ONBOARDING_DONE"] == "1" {
                            return
                        }
                        #endif
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
                // 保险箱资产不算「未归类」，移入/移出后要重算差集。
                albumService.excludedLocalIDs = vault.originLocalIDs
                Task { await albumService.refreshUncategorized() }
            }
            .task(id: currentItem?.id) {
                guard let id = currentItem?.id else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                statistics.recordBrowse(id: id)
            }
            // 顶部整行改为 152pt 后，Toast 要落在它下方，不能压住 LCD 读数。
            .toast($toastMessage, topPadding: LCDSpec.rowHeight + 10)
            // 冷启动恢复上次选中的销毁道具；设置页与首页共用 AppSettings 这一份。
            .onAppear {
                destroy.switchMachine(settings.destroyMachine)
            }
            // 设置页直接选道具后回首页要同步；首页自己切换时两者已相等，直接跳过，
            // 避免弹跳动效播两次。
            .onChange(of: settings.destroyMachine) { _, newValue in
                guard newValue != destroy.machine else { return }
                if destroy.switchMachine(newValue) {
                    deviceSwitchToken += 1
                }
            }
        }
        // 单屏工作区的固定高度元素较多，限制在非无障碍字号内避免遮挡；
        // 设置、统计、引导等阅读页仍完整支持 AX 字号。
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .modifier(HitDebugOverlayModifier())
    }

    // MARK: - 顶部

    /// 顶部整行三段：左按钮区 / LCD / 右按钮区。
    ///
    /// 屏体收到 240 宽后两侧各约 68pt，足够放 64pt 的圆形操作按钮；
    /// 左右区等宽弹性分配，LCD 因而始终精确居中，不依赖硬编码的屏幕宽度。
    /// 整行进 `safeAreaInset(edge: .top)`，高度固定为 `LCDSpec.rowHeight`，
    /// 桌面态与处理态只是替换左右按钮的内容，行高与三栏落点都不跳。
    private var headerBar: some View {
        let total = windowSize.width
        let padding = LCDSpec.headerPadding
        // 极窄宽度下先保住两侧 64pt 命中区，再收缩 LCD，避免按钮被挤出屏幕。
        let lcdWidth = min(
            LCDSpec.displayWidth,
            max(0, total - 2 * padding - 2 * LCDSpec.sideButtonWidth)
        )
        let lcdHeight = lcdWidth * LCDSpec.imageAspect

        // 挂件有挂钩，必须贴行顶悬挂；处理态的圆按钮没有挂钩，
        // 按 LCD 屏面高度垂直居中，才不会飘在挂环那一层。
        let buttonAlignment: Alignment = showsStage ? .center : .top

        return HStack(alignment: .top, spacing: 0) {
            headerLeftButton
                .frame(maxWidth: .infinity, minHeight: lcdHeight, alignment: buttonAlignment)

            // LCD 是唯一固定宽的元素，两侧弹性区被它推成等宽。
            headerLCD(width: lcdWidth, height: lcdHeight)

            headerRightButton
                .frame(maxWidth: .infinity, minHeight: lcdHeight, alignment: buttonAlignment)
        }
        .frame(height: LCDSpec.rowHeight, alignment: .top)
        .padding(.horizontal, padding)
        .padding(.top, 2)
        // DEBUG 长按顶栏空白处开关命中调试；放在 background 不参与布局，
        // 也不会像 Spacer / Color 那样在 safeAreaInset 里把顶栏撑成整屏高。
        .background { hitDebugToggleArea }
    }

    /// 左上角按钮区：桌面态是保险箱钥匙，处理态换成回退（撤销上一步）。
    @ViewBuilder
    private var headerLeftButton: some View {
        if showsStage {
            PegboardActionButton(
                assetName: "icon_undo",
                accessibilityTitle: "撤销上一步",
                accessibilityHintText: "把最近一次决定退回舞台，并恢复对应的待销毁或待加密计数",
                isEnabled: task.canUndo && !isExecutingTaskEnd
            ) {
                undoLastStep()
            }
        } else {
            PegboardHookButton(
                assetName: "icon_vault_keys",
                title: "私密保险箱，已存 \(vault.records.count) 件",
                swayToken: keySwayToken
            ) {
                openVaultPreview()
            }
            .offset(x:8,y:8)
        }
    }

    /// 右上角按钮区：桌面态是螺丝刀进设置，处理态换成提前结束并结算。
    @ViewBuilder
    private var headerRightButton: some View {
        if showsStage {
            PegboardActionButton(
                assetName: "icon_stop",
                accessibilityTitle: "结束并结算",
                accessibilityHintText: "未处理的照片按保留处理，随后进入结算",
                isEnabled: !isExecutingTaskEnd && !task.isFinished
            ) {
                finishTaskNow()
            }
        } else {
            PegboardHookButton(
                assetName: "icon_tool_screwdriver",
                title: "设置",
                iconSize: 50
            ) {
                isSettingsPresented = true
            }
        }
    }

    /// 顶栏中央的液晶屏：桌面态静置物料图，处理态显示进度并作为暂停入口。
    /// 未授权时保留等尺寸占位，避免在权限引导页挂一块进度屏、又不让两侧按钮位移。
    private func headerLCD(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if library.accessState.canBrowse {
                LCDScreen(
                    mode: showsStage
                        ? .progress(
                            pendingDelete: task.destroyCount,
                            processed: task.processedCount,
                            total: task.totalCount
                        )
                        : .idle,
                    notice: lcdNotice,
                    isPauseEnabled: showsStage && !isExecutingTaskEnd && !task.isFinished,
                    onPause: { pauseTask() }
                )
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .offset(x:0,y:4)
        .hitDebugRegion("液晶屏")
    }

    /// DEBUG 下长按顶栏空白 2 秒开关命中调试；Release 不编译手势。
    @ViewBuilder
    private var hitDebugToggleArea: some View {
        #if DEBUG
        Color.clear
            // 显式定高：safeAreaInset 里的弹性视图会接受整屏高度，
            // 把顶栏撑满、把下面的工作区挤出可视区。
            .frame(height: LCDSpec.rowHeight)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 2) {
                let enabled = hitDebugToggle()
                toastMessage = ToastMessage(
                    text: enabled ? "命中调试：开，点按后看左上角日志" : "命中调试：关",
                    kind: .info
                )
            }
        #else
        EmptyView()
        #endif
    }

    // MARK: - 桌面

    private var showsStage: Bool {
        workspace.isPresented && task.isActive
    }

    private var deskView: some View {
        TaskDeskView(
            isTaskActive: task.isActive,
            isTaskFinished: task.isFinished,
            albumTitle: task.albumTitle,
            processed: task.processedCount,
            total: task.totalCount,
            pendingDestroy: task.destroyCount,
            onStart: { isAlbumPickerPresented = true },
            onResume: { enterWorkspace() },
            onFinishNow: { finishTaskNow() }
        )
    }

    // MARK: - 三栏工作区

    private var taskWorkspace: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rowW = size.width.isFinite ? max(0, size.width) : 0
            let columnGap = Theme.Spacing.sm
            // 两侧宽度与中栏宽度统一在这里反推：窄屏时先收缩两侧，
            // 保证中栏至少 120pt，避免「左右栏 + 间距 > 行宽」把中栏算成 0。
            let columns = workspaceColumns(rowW: rowW)
            let sideWidth = columns.side
            let favoriteWidth = columns.favorite
            let middleWidth = columns.middle

            let contentTopValue = contentTop(in: proxy)
            let usableH = contentHeight(in: proxy)
            // 纸篓最多让出「可用高度 − 220」：任何情况下都保留一块可见的内容区，
            // 不会出现 contentHeight − dockHeight ≤ 0 把行高挤成 0 的情况。
            let dockBudget = min(dockHeight, max(0, usableH - 220))
            let fallbackBottom = usableH - dockBudget
            // 桌面上沿算成 0/负值（坐标系异常）时回退到纸篓上方，避免整行被压没。
            let benchTopValue = benchTopY(in: proxy)
            let contentBottom = max(
                0,
                min(benchTopValue > 0 ? benchTopValue : fallbackBottom, fallbackBottom)
            )
            // 行高显式给出，不再让内层 GeometryReader 反推：
            // GeometryReader 的最小高度是 0，一旦外层建议高度异常就会被压成 0，
            // 三栏（尤其被 clipped 的中栏）会整块消失。
            // 顶部三段（左按钮 / LCD / 右按钮）已整体移入 safeAreaInset，
            // 这里不再单独扣 LCD 行；占位与切态无关，桌面 / 处理中完全一致。
            // 「中间区」按 workspaceHeightScale 放大：多出来的部分全部向下延伸，
            // 由下方 padding 让出同样高度，保证行顶仍贴在 LCD 行下沿、不向上溢出。
            let baseRowHeight = max(0, contentBottom - bannerHeight)
            // 增量不许超过「内容底 → 容器底」的余量：否则 VStack 会比容器还高，
            // 行顶被顶到 LCD 行上方（倍率继续调大或极短屏时尤其容易触发）。
            let availableDrop = max(0, size.height - contentBottom)
            let extraRowHeight = min(
                baseRowHeight * (Self.workspaceHeightScale - 1),
                availableDrop
            )
            let rowHeight = baseRowHeight + extraRowHeight

            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if library.accessState == .limited {
                        LimitedAccessBanner {
                            library.manageLimitedAccess()
                        }
                        .padding(.horizontal, Theme.Spacing.page)
                        .padding(.bottom, Theme.Spacing.sm)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: BannerHeightKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: columnGap) {
                        VaultDoorColumn(
                            width: sideWidth,
                            count: vault.records.count,
                            isOpen: vaultDoorOpen,
                            onTap: { openVaultPreview() }
                        )
                        .frame(width: sideWidth, height: rowHeight)
                        // 这里不裁剪：图标中心落在屏幕坐标 0.25×边长处，
                        // 左侧 25% 必须真的在屏幕外，箱体左缘贴住屏幕左缘（0 边距）。

                        // 中栏：舞台与桌面共用一条中线，和左右栏（整行居中）同一套落点规则。
                        // 液晶屏已在顶栏三段里，不再压在中栏顶部。
                        ZStack {
                            if showsStage {
                                stageSection(vaultDropOffset: vaultDropOffset(in: proxy, sideWidth: sideWidth))
                                    .frame(width: middleWidth, height: rowHeight)
                                    .transition(
                                        .asymmetric(
                                            insertion: .scale(scale: 0.92, anchor: .center)
                                                .combined(with: .opacity),
                                            removal: .opacity
                                        )
                                    )
                            }

                            // 桌面态内容常驻在最上层，只有“当前该显示的那一层”接收命中。
                            deskView
                                .frame(width: middleWidth, height: rowHeight)
                                .clipped()
                                .opacity(showsStage ? 0 : 1)
                                .allowsHitTesting(!showsStage)
                                .accessibilityHidden(showsStage)
                        }
                        .frame(width: middleWidth, height: rowHeight)
                        .animation(
                            Theme.Motion.animation(.drawer, reduceMotion: reduceMotion),
                            value: showsStage
                        )
                        .onChange(of: showsStage) { _, newValue in
                            hitDebugNote("showsStage->\(newValue) workspace=\(workspace.isPresented)")
                        }
                        // 中栏画在左右栏之上：舞台卡片飞出时要跨过两侧实体。
                        .zIndex(1)
                        .hitDebugRegion("中栏")

                        FavoriteAlbumColumn(
                            // 比左侧保险箱宽一档，整体放大；中栏宽度已按这个宽度反推。
                            width: favoriteWidth,
                            albums: albumService.userAlbums,
                            selectedAlbumID: settings.defaultAlbumID,
                            isReceiving: favoritesReceiving,
                            thumbnails: library.thumbnails,
                            onSelect: { selectDefaultAlbum($0) }
                        )
                        .frame(height: rowHeight)
                        .clipped()
                    }
                    // 右侧只留很小边距：收藏夹整体贴近右边缘，同时避开安全区。
                    .padding(.leading, Theme.Spacing.md)
                    .padding(.trailing, 2)
                    // 行高锁死为显式值，三栏谁都不能把它撑大。
                    .frame(width: rowW, height: rowHeight, alignment: .top)
                    // 撤销 / 结束已上移到顶栏左右按钮区，三栏行顶部不再挂浮层。
                    // 舞台要接住抽屉带来的缩放与失焦；两侧实体不参与缩放。
                    .allowsHitTesting(!isAlbumsDrawerPresented && !isVaultDrawerPresented)
                }
                // 基准底边是 contentBottom；减去放大出来的 extraRowHeight，
                // 让中间区向下长 20%，而不是把行顶顶到 LCD 行上方。
                .padding(.bottom, max(0, size.height - contentBottom - extraRowHeight))

                dockSection
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: DockHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            }
            .onPreferenceChange(DockHeightKey.self) { dockHeight = $0 }
            .onPreferenceChange(BannerHeightKey.self) { bannerHeight = $0 }
            // 真机可读的中间量：长按顶栏中间或 SP_HIT_DEBUG=1 时显示在 HUD 右上角。
            .layoutProbe(
                LayoutProbe(
                    rowW: rowW,
                    rowH: rowHeight,
                    sideW: sideWidth,
                    favoriteW: favoriteWidth,
                    middleW: middleWidth,
                    minY: proxy.frame(in: .global).minY,
                    safeTop: proxy.safeAreaInsets.top,
                    safeBottom: proxy.safeAreaInsets.bottom,
                    contentTop: contentTopValue,
                    contentHeight: usableH,
                    dockH: dockHeight,
                    benchTop: benchTopValue,
                    contentBottom: contentBottom,
                    showsStage: showsStage
                )
            )
            .overlay {
                if isAlbumsDrawerPresented {
                    albumsDrawer(width: size.width)
                }
            }
        }
    }

    // MARK: - 三栏计算

    /// 三栏宽度的唯一来源：两侧按行宽 20% 取、收藏夹比保险箱宽 10pt，
    /// 中栏吃掉剩余；剩余不足 120pt 时按比例收缩两侧，避免中栏被算成 0。
    private struct WorkspaceColumns {
        var side: CGFloat
        var favorite: CGFloat
        var middle: CGFloat
    }

    private func workspaceColumns(rowW: CGFloat) -> WorkspaceColumns {
        let horizontalPadding = Theme.Spacing.md + 2
        let gap = Theme.Spacing.sm
        let usableW = max(0, rowW - horizontalPadding - gap * 2)
        var side = min(148, max(56, rowW * 0.2))
        var favorite = min(168, max(64, side + 10))
        var middle = max(0, usableW - side - favorite)
        if middle < 120 {
            let budget = max(0, usableW - 120)
            side = min(side, budget * 0.45)
            favorite = min(favorite, max(0, budget - side))
            middle = max(0, usableW - side - favorite)
        }
        return WorkspaceColumns(side: side, favorite: favorite, middle: middle)
    }

    /// 内容界面的顶部（全局坐标）。必须把顶部安全区算进去：
    /// 有的状态下 `GeometryReader` 的 frame 不含安全区（minY = 头部高度），
    /// 有的状态 frame 从屏幕原点开始（minY = 0、安全区 = 头部高度）；
    /// 只减 `minY` 会让同一块屏幕算出两种行高，左右栏的垂直中心随之漂移。
    private func contentTop(in proxy: GeometryProxy) -> CGFloat {
        proxy.frame(in: .global).minY + proxy.safeAreaInsets.top
    }

    /// 工作区实际可用的内容高度，同样与 frame 是否包含安全区无关。
    private func contentHeight(in proxy: GeometryProxy) -> CGFloat {
        max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
    }

    /// 桌面（台面）上沿在内容坐标系中的位置；与 SceneryBackgroundView 使用同一份比例。
    private func benchTopY(in proxy: GeometryProxy) -> CGFloat {
        let metrics = SceneryLayout.metrics(in: windowSize)
        return metrics.benchTopY - contentTop(in: proxy)
    }

    /// 背景图按窗口尺寸铺满，落点计算需要同一份窗口尺寸。
    private var windowSize: CGSize {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.bounds.size
            ?? CGSize(width: 390, height: 844)
    }

    /// 左滑飞出落点：保险箱图标中心在屏幕坐标 0.25×边长处，
    /// 所以从舞台中心（≈ 屏幕中心）往左的位移是屏幕半宽减去这段距离。
    private func vaultDropOffset(in proxy: GeometryProxy, sideWidth: CGFloat) -> CGFloat {
        let iconSize = VaultDoorColumn.iconSize(for: sideWidth)
        return max(0, proxy.size.width / 2 - 0.25 * iconSize)
    }

    private func stageSection(vaultDropOffset: CGFloat) -> some View {
        // 进度信息已移到中栏上方的液晶屏里，这里只负责照片舞台。
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
            vaultRequest: stageVaultRequest,
            favoriteRequest: stageFavoriteRequest,
            sideDropOffset: vaultDropOffset,
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
        .scaleEffect(isAlbumsDrawerPresented ? 0.96 : 1)
        .animation(
            Theme.Motion.animation(.drawer, reduceMotion: reduceMotion),
            value: isAlbumsDrawerPresented
        )
        .onAppear {
            hitDebugNote("stage appear items=\(visibleItems.count)")
        }
    }

    // MARK: - 纸篓

    private var dockSection: some View {
        DestroyDock(
            pendingCount: task.destroyCount,
            shakeToken: binShakeToken,
            machine: destroy.machine,
            switchToken: deviceSwitchToken,
            onSwitch: { cycleDestroyMachine() },
            bottomInset: max(0, bottomSafeInset - 8)
        )
        // 只下移道具本体：布局位置不变，照片区与台面起算点也不变。
        .offset(y: effectiveDockDrop)
    }

    /// 轻点底部道具：按 MachineKind.allCases 顺序循环切换并持久化。
    /// 结算执行中或销毁流程忙碌时不切换，避免统计口径与界面显示分叉。
    private func cycleDestroyMachine() {
        guard !isExecutingTaskEnd, !destroy.phase.isBusy else { return }
        let next = destroy.machine.next
        guard destroy.switchMachine(next) else { return }
        settings.destroyMachine = next
        deviceSwitchToken += 1
        sound.play(.deviceSwitch)
        showLCDNotice("已切换为「\(next.displayName)」")
    }

    /// 纸篓下移量：满额 `dockDrop`，但短屏 / iPad 上按屏底余量收敛。
    ///
    /// 纸篓内容底边到屏幕底的现有留白 = 底部安全区 + 自身 4pt + `bottomInset`
    /// （`bottomInset = max(0, 安全区 − 8)`）。下移吃掉这段留白，
    /// 最后仍保留 `dockBottomClearance`，因此任何设备都不会被裁切。
    private var effectiveDockDrop: CGFloat {
        let safe = bottomSafeInset
        let contentGap = safe + 4 + max(0, safe - 8)
        let slack = contentGap - Theme.Metrics.dockBottomClearance
        return min(Theme.Metrics.dockDrop, max(0, slack))
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

    private func startTask(selection: AlbumPickerSelection) {
        let albumID: String?
        let title: String
        let rawItems: [PhotoItem]

        switch selection {
        case .all:
            albumID = nil
            title = "全部照片"

        case .uncategorized:
            // 首次差集还在后台跑：不拿空集合去建任务，避免把「全部照片」当成未归类。
            guard albumService.uncategorizedDisplayCount != nil else {
                toastMessage = ToastMessage(text: "正在统计未归类照片，请稍后再试", kind: .info)
                return
            }
            albumID = nil
            title = "未归类照片"

        case .album(let album):
            albumID = album.id
            title = album.title
        }

        // 每批张数取设置值；只影响这一批，进行中的任务以快照为准。
        let batchLimit = TaskPolicy.configuredBatchSize
        // 延后未到期的照片不进入本批；多取一些再截断，保证凑满一批。
        let snoozedIDs = snooze.activeIDs
        let limit = batchLimit + snoozedIDs.count
        switch selection {
        case .uncategorized:
            rawItems = library.uncategorizedTaskItems(
                skipping: albumService.classifiedLocalIDs,
                limit: limit
            )
        case .all, .album(_):
            rawItems = library.taskItems(albumLocalID: albumID, limit: limit)
        }
        let items = Array(
            rawItems
                .filter { !snoozedIDs.contains($0.id) }
                .prefix(batchLimit)
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

        task.start(albumLocalID: albumID, albumTitle: title, items: items, batchSize: batchLimit)
        currentID = task.remainingItems.first?.id
        workspace.present()
        closeAlbums()
        closeVaultDrawer()

        if task.isFinished {
            Task { await executeTaskEnd() }
        }
    }

    private func enterWorkspace() {
        hitDebugNote("resume active=\(task.isActive) finished=\(task.isFinished) remaining=\(task.remainingItems.count)")
        guard task.isActive else {
            isAlbumPickerPresented = true
            return
        }
        clampCurrentID()
        workspace.present()
        hitDebugNote("workspace=\(workspace.isPresented) showsStage=\(showsStage)")
        if task.isFinished {
            Task { await executeTaskEnd() }
        }
    }

    private func pauseTask() {
        hitDebugNote("pause")
        workspace.dismiss()
        isAlbumsDrawerPresented = false
        isVaultDrawerPresented = false
        resetStage()
        toastMessage = ToastMessage(text: "已保留本批进度，下次可继续", kind: .info)
    }

    /// 撤销最近一步决策：照片退回舞台、去向与计数一起回退。
    /// 延后额外删除 SnoozeStore 记录；结算已开始执行后不可撤销。
    private func undoLastStep() {
        hitDebugNote("undo processed=\(task.processedCount)")
        guard showsStage, task.isActive, !isExecutingTaskEnd else { return }
        guard let undone = task.undoLastDecision() else { return }

        if undone.decision == .snooze {
            snooze.unsnooze(id: undone.id)
        }

        currentID = undone.id
        isZoomed = false
        zoomScale = 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toastMessage = ToastMessage(text: "已撤销上一步", kind: .info)
    }

    /// 直接结束本批：未决定的照片一律按“保留”归档，其余队列照常走结算。
    /// 删除/加密仍由系统确认框把关，不额外弹 App 自建确认。
    private func finishTaskNow() {
        hitDebugNote("finishNow remaining=\(task.remainingItems.count)")
        guard task.isActive, !isExecutingTaskEnd else { return }
        for item in task.remainingItems {
            task.record(id: item.id, decision: .keep)
        }
        guard task.isFinished else { return }
        workspace.dismiss()
        Task { await executeTaskEnd() }
    }

    private func restoreTaskIfNeeded() {
        guard task.isActive, library.accessState.canBrowse else { return }
        #if DEBUG
        // 合成任务没有对应的相册资产，不能被“恢复”清空。
        if task.assetIDs.contains(where: { $0.hasPrefix("ui-test-") }) { return }
        #endif
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
        workspace.dismiss()
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
        lcdNotice = nil
    }

    // MARK: 屏内反馈

    /// 往液晶屏推一条瞬时反馈：不排队，后来的直接覆盖前面的；
    /// 2.4s 内没有新反馈就清空，回落到常驻提示。
    private func showLCDNotice(_ text: String, tone: LCDNotice.Tone = .info) {
        let notice = LCDNotice(text: text, tone: tone)
        lcdNotice = notice
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2400))
            guard lcdNotice?.id == notice.id else { return }
            lcdNotice = nil
        }
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
        showLCDNotice("已延后 \(days) 天，本批不再出现", tone: .success)
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
        hitDebugNote("favorite → \(album.title)")
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

        // 侧栏脉冲只由 FavoriteAlbumColumn 内部的 .animation(value: isReceiving) 驱动，
        // 这里不放进任何 withAnimation，避免和舞台换牌共用动画事务。
        favoritesReceiving = true

        let nextID = idAfterRemoving(id)
        // 舞台数据的推进显式禁用动画：左右滑会在飞出动画开始时就改 items，
        // 若被任何外层动画事务带上，新前排会被插值淡入而露出后面的卡。
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) {
            task.record(id: id, decision: .keep)
            currentID = nextID
            isZoomed = false
            zoomScale = 1
        }
        handleTaskProgress()

        Task {
            do {
                try await albumService.addAssets([id], toAlbum: albumID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showLCDNotice("已加入「\(settings.defaultAlbumTitle)」", tone: .success)
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
        // 同上：舞台推进禁止动画，侧栏开门动画只包它自己的布尔量。
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) {
            task.record(id: id, decision: .vault)
            currentID = nextID
            isZoomed = false
            zoomScale = 1
        }

        withAnimation(
            reduceMotion ? .easeOut(duration: 0.14) : .easeOut(duration: 0.28)
        ) {
            vaultDoorOpen = true
        }
        showLCDNotice("已存入保险箱，结算时加密", tone: .success)

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

    /// 舞台完成下滑动画后调用：记录“废纸篓”决策并推进。
    private func discardCurrent(id: String) {
        guard task.isActive, !isExecutingTaskEnd else { return }
        guard task.items.contains(where: { $0.id == id }) else { return }

        // 照片落入当前道具：播放它的专属动效与音效。
        binShakeToken += 1
        sound.play(device: destroy.machine)

        let nextID = idAfterRemoving(id)
        task.record(id: id, decision: .destroy)
        currentID = nextID
        isZoomed = false
        zoomScale = 1
        showLCDNotice("已加入待销毁 · \(task.destroyCount) 张", tone: .danger)
        handleTaskProgress()
    }

    /// UI 测试用：确保有任务可操作。
    private func ensureUITestTask() {
        guard !task.isActive else {
            workspace.present()
            clampCurrentID()
            return
        }
        let snoozedIDs = snooze.activeIDs
        let batchLimit = TaskPolicy.configuredBatchSize
        let rawItems = library.taskItems(
            albumLocalID: nil,
            limit: batchLimit + snoozedIDs.count
        )
        let items = Array(
            rawItems
                .filter { !snoozedIDs.contains($0.id) }
                .prefix(batchLimit)
        )
        guard !items.isEmpty else { return }
        task.start(albumLocalID: nil, albumTitle: "全部照片", items: items, batchSize: batchLimit)
        workspace.present()
        currentID = task.remainingItems.first?.id
    }

    #if DEBUG
    /// 模拟器回归用：不依赖相簿权限的合成任务。
    /// 横竖交替（奇数横图 4:3、偶数竖图 3:4），缩略图按序号生成，便于逐帧确认顺序与尺寸。
    private func startSyntheticUITestTask() {
        // 强制授权会触发 onChange 里的引导判断，先标记已完成避免盖住舞台。
        hasCompletedOnboarding = true
        library.debugForceAuthorized()
        let items: [PhotoItem] = (1...10).map { index in
            let landscape = index % 2 == 1
            return PhotoItem(
                id: String(format: "ui-test-photo-%02d", index),
                kind: .photo,
                pixelSize: landscape
                    ? CGSize(width: 1600, height: 1200)
                    : CGSize(width: 1200, height: 1600),
                duration: 0,
                createdAt: Date().addingTimeInterval(TimeInterval(-index * 60)),
                isHidden: false
            )
        }
        task.start(albumLocalID: nil, albumTitle: "全部照片", items: items, batchSize: items.count)
        workspace.present()
        currentID = task.remainingItems.first?.id
    }
    #endif

    /// UI 测试钩子；正常启动不会触发。
    private func runUITestHooksIfNeeded() async {
        let environment = ProcessInfo.processInfo.environment

        #if DEBUG
        if environment["UI_TEST_ALBUM_PICKER"] == "1" {
            try? await Task.sleep(for: .milliseconds(900))
            isAlbumPickerPresented = true
        }
        #endif

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
        #if DEBUG
        if let mode = environment["UI_TEST_SYNTHETIC_STAGE"] {
            try? await Task.sleep(for: .milliseconds(600))
            if mode == "stage" {
                startSyntheticUITestTask()
            } else {
                hasCompletedOnboarding = true
                library.debugForceAuthorized()
            }
            return
        }
        if let raw = environment["UI_TEST_STAGE_SIDE"] {
            // 逗号分隔的序列，例如 "vault,vault,favorite"：
            // 每一项都走与手势相同的飞出/换牌路径，用于回归飞行期间的顺序与尺寸。
            try? await Task.sleep(for: .milliseconds(1000))
            if environment["UI_TEST_SYNTHETIC"] == "1" {
                startSyntheticUITestTask()
            } else {
                ensureUITestTask()
            }
            if raw.contains("favorite"), settings.defaultAlbumID == nil {
                // 模拟器里通常没有用户相簿；给一个占位 ID 让右滑飞出路径可走
                // （写入相簿会失败并提示，但不影响舞台飞出的视觉验证）。
                settings.setDefaultAlbum(id: "ui-test-album", title: "测试相簿")
            }
            try? await Task.sleep(for: .milliseconds(500))
            for token in raw.split(separator: ",") {
                switch token {
                case "vault":
                    stageVaultRequest += 1
                case "favorite":
                    // 占位相簿每次写入都会失败并触发相簿列表刷新，
                    // 默认收藏夹可能被清空；每次右滑前补回来，保证飞行路径连续可测。
                    if settings.defaultAlbumID == nil {
                        settings.setDefaultAlbum(id: "ui-test-album", title: "测试相簿")
                    }
                    stageFavoriteRequest += 1
                case "tap":
                    tapRequest += 1
                default: break
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
            return
        }
        #endif
        // UI_TEST_MACHINE 接受五款道具的 rawValue（bin_waste / shredder /
        // fireplace / mailbox / any_door）；旧的 "shredder" 仍然有效。
        if let requested = environment["UI_TEST_MACHINE"].flatMap(MachineKind.init(rawValue:)) {
            try? await Task.sleep(for: .milliseconds(600))
            ensureUITestTask()
            if destroy.switchMachine(requested) {
                settings.destroyMachine = requested
                deviceSwitchToken += 1
            }
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

/// 底部纸篓的实际高度：用于把三栏内容的底边让到纸篓上方。
private struct DockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 112
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 受限访问提示条的实际高度：它占用的空间要从三栏行高里扣掉。
private struct BannerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
