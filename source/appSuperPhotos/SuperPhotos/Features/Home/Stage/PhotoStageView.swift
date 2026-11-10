import SwiftUI
import UIKit

/// 舞台堆叠与手势参数：一次展示 4 张拍立得，轻点换牌 / 下滑销毁 / 左右滑入两侧实体。
enum StageStackPolicy {
    /// 当前照片之后同时露出的层数（含当前共 4 张）。
    static let visibleDepth = 4
    /// 各层旋转角度（正数顺时针）：0° / 左 15° / 右 10° / 左 5°，形成随手一叠的错落感。
    static let depthAngles: [Double] = [0, -15, 10, -5]
    /// 各层横向偏移：越靠后越向外散开，避免机械对齐；纵向由底边露出量统一计算。
    static let depthShiftX: [CGFloat] = [0, -7, 9, -13]
    /// 各层缩放：后层略小，强化“一叠相纸”的层次。
    static let depthScales: [CGFloat] = [1, 0.985, 0.97, 0.955]
    /// 相纸边距：左右 / 上 / 下（底部留出拍立得的“下巴”）。
    static let paperSide: CGFloat = 10
    static let paperTop: CGFloat = 10
    static let paperBottom: CGFloat = 26
    /// 等面积基准：S 为“基准正方形”的边长，卡片内容面积恒为 S²。
    /// 4:3 取 长边 S·2/√3、短边 S·√3/2；3:4 两者互换，
    /// 因此 w_land = h_port、h_land = w_port，横竖视觉分量一致。
    static let stackBaseRatio: CGFloat = 0.72
    static let minStackBaseSide: CGFloat = 88
    static let equalAreaLongRatio: CGFloat = 2 / CGFloat(3).squareRoot()
    static let equalAreaShortRatio: CGFloat = CGFloat(3).squareRoot() / 2
    /// 正方形按横图处理（width >= height），超长图按方向归一后居中裁切。
    static let maxDepthReveal: CGFloat = 30
    /// 每层向下露出的底边高度（含前排 0）。
    static let depthReveal: [CGFloat] = [0, 22, 26, 30]
    /// 舞台高度的可用比例（留出进度条与底部信息）。
    static let stackHeightRatio: CGFloat = 0.9
    /// 下滑提交阈值；不足则弹簧回弹。
    static let discardCommitDistance: CGFloat = 96
    /// 跟手阶段的最大拉伸；超出后按 1/4 阻尼继续。
    static let discardStretchLimit: CGFloat = 180
    /// 左右滑提交距离与甩动预测。
    static let sideCommitDistance: CGFloat = 64
    static let sideFlickPrediction: CGFloat = 120

    /// 横图（含正方形）走 4:3 盒，竖图走 3:4 盒；两者面积相同。
    static func isLandscape(_ item: PhotoItem) -> Bool {
        item.pixelSize.width >= item.pixelSize.height
    }
}

/// 舞台：拍立得叠放 + 轻点全屏 + 上滑延后 + 下滑入待销毁 + 左滑入保险箱 + 右滑入收藏夹 + 捏合缩放。
struct PhotoStageView: View {
    /// 当前可见（未进入待销毁）的照片序列。
    let items: [PhotoItem]
    let currentIndex: Int
    let thumbnails: ThumbnailProvider
    let isInteractionEnabled: Bool
    /// 待销毁累积是否还有容量；满时不允许再下滑。
    let canDiscard: Bool
    /// 是否已选择默认收藏夹；未选择时右滑只回弹。
    let canFavorite: Bool
    /// 来自坞体的程序化下滑请求，每次自增 1 触发一次。
    let discardRequest: Int
    /// 来自 UI 测试的程序化轻点请求，每次自增 1 触发一次。
    let tapRequest: Int
    /// 来自 UI 测试的程序化左右滑请求，每次自增 1 触发一次。
    /// 与手势走同一条 `beginFlight` 路径，用于回归飞出顺序与尺寸。
    var vaultRequest: Int = 0
    var favoriteRequest: Int = 0
    /// 左右滑飞出距离：约等于舞台半宽 + 侧栏宽 + 间距。
    let sideDropOffset: CGFloat

    var onAdvance: (String) -> Void
    var onOpenFullscreen: (String) -> Void
    var onVaultStore: (String) -> Void
    var onFavoriteStore: (String) -> Void
    var onFavoriteRejected: () -> Void
    var onDiscard: (String) -> Void
    var onSnooze: (String, Int) -> Void
    var onZoomChanged: (Bool, CGFloat) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: DragAxis?
    @State private var isShifting = false
    /// 上滑跟手时的目标延后天数；nil 表示当前不是上滑。
    @State private var snoozePreviewDays: Int?

    @State private var outgoing: OutgoingCard?
    @State private var outgoingOffset: CGSize = .zero
    @State private var outgoingScale: CGFloat = 1
    @State private var outgoingOpacity: Double = 1
    /// 前排放上报的缩略图；必须带 asset ID，避免换牌时把上一张的图交给新卡。
    @State private var frontThumbnail: FrontThumbnail?
    @State private var burstToken = 0

    @State private var zoomScale: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var panBase: CGSize = .zero

    private enum DragAxis {
        case horizontal
        case vertical
    }

    private enum FlightSide {
        case vault
        case favorite
    }

    private struct OutgoingCard {
        let item: PhotoItem
        let image: UIImage?
    }

    /// 缩略图与它所属的 asset 绑定，读取时校验 ID 才使用。
    private struct FrontThumbnail {
        let id: String
        let image: UIImage
    }

    private struct StackEntry: Identifiable {
        let id: String
        let item: PhotoItem
        let depth: Int
    }

    private var currentItem: PhotoItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    private var isZoomed: Bool { zoomScale > 1.01 }

    /// 只有与目标 asset 一致的缩略图才可作为飞出卡片的占位；
    /// ID 不匹配时返回 nil，让卡片按自己的 ID 重新加载，绝不把上一张的图带过去。
    private func cachedThumbnail(for item: PhotoItem) -> UIImage? {
        guard let frontThumbnail, frontThumbnail.id == item.id else { return nil }
        return frontThumbnail.image
    }

    private var stackEntries: [StackEntry] {
        let start = max(0, currentIndex)
        return items
            .dropFirst(start)
            .prefix(StageStackPolicy.visibleDepth)
            .enumerated()
            .map { depth, item in
                StackEntry(id: item.id, item: item, depth: depth)
            }
    }

    private var prefetchKey: String {
        stackEntries.map(\.id).joined(separator: "|")
    }

    /// 整叠是否还在「替飞出卡占位」。
    ///
    /// - 轻点换牌 / 上滑 / 下滑：飞出卡在动画结束前仍留在 `items` 里，
    ///   列表 depth 0 是它本人、真正要顶上来的是 depth 1，所以渲染时整叠前移一层。
    /// - 左右滑：飞出卡在动画第一帧就已由外部从 `items` 移除，
    ///   depth 0 已经是对的下一张；此时绝不能再前移，
    ///   否则第二张被压到后排、第三张顶到前排（表现为先看到第三张）。
    ///
    /// 所有依赖 `isShifting` 的位置 / 深度 / 缩放 / zIndex / 尺寸偏移都用它，
    /// 不要直接再用 `isShifting ? 1 : 0`。
    private var isHoldingFrontPosition: Bool {
        guard isShifting, let outgoing else { return false }
        return items.contains(where: { $0.id == outgoing.item.id })
    }

    var body: some View {
        GeometryReader { proxy in
            let baseSide = stackBaseSide(in: proxy.size)
            let frontCardSize = currentItem.map { cardSize(for: $0, base: baseSide) }
                ?? fallbackCardSize(base: baseSide)
            // 整叠锚点：以“最高竖卡 + 最深露出”的外接框中心为准。
            // 换牌只改各卡尺寸，不改这个基准，前后排都不会上下跳。
            let referenceHeight = referenceCardHeight(base: baseSide)
            let baseline = stackBaseline(referenceHeight: referenceHeight)

            ZStack {
                if currentItem == nil {
                    emptyStage
                } else {
                    stack(baseSide: baseSide, baseline: baseline)
                }

                if let outgoing {
                    let outgoingSize = cardSize(for: outgoing.item, base: baseSide)
                    PolaroidCardView(
                        item: outgoing.item,
                        thumbnails: thumbnails,
                        size: outgoingSize,
                        cachedImage: outgoing.image
                    )
                    // 身份跟随 asset：连续飞出多张时不复用上一张的视图状态。
                    .id(outgoing.item.id)
                    .scaleEffect(outgoingScale)
                    .offset(
                        x: outgoingOffset.width,
                        // 起飞点必须与固定底边的前排卡重合，否则换牌第一帧会跳一下。
                        y: baseline - outgoingSize.height / 2 + outgoingOffset.height
                    )
                    .opacity(outgoingOpacity)
                    // 必须在整叠之上：换牌时它要先盖住前排，再向上飞走，
                    // 否则它会从后排卡下方穿过去，露出前后两张的缝隙。
                    .zIndex(200)
                    .allowsHitTesting(false)
                }

                if burstToken > 0 {
                    PhotoParticleBurst(reduceMotion: reduceMotion)
                        .id(burstToken)
                        .frame(width: proxy.size.width, height: 200)
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 24)
                        .zIndex(20)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(container: proxy.size, cardSize: frontCardSize))
            // 轻点由容器统一接管：进入全屏查看，不再推进。
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard isInteractionEnabled, !isShifting, !isZoomed else { return }
                    openFullscreen()
                }
            )
            .simultaneousGesture(magnifyGesture)
            // 上滑跟手时在照片上方浮出目标天数。
            .overlay(alignment: .center) {
                if let days = snoozePreviewDays, !isShifting {
                    snoozeBadge(days: days)
                        .offset(y: baseline - frontCardSize.height - 26)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .zIndex(30)
                }
            }
            .onChange(of: zoomScale) { _, scale in
                onZoomChanged(scale > 1.01, scale)
                if scale <= 1.01 {
                    panOffset = .zero
                    panBase = .zero
                }
            }
            .onChange(of: currentIndex) { _, _ in
                snoozePreviewDays = nil
                resetZoom(animated: false)
            }
            .onChange(of: discardRequest) { _, _ in
                guard isInteractionEnabled, !isShifting else { return }
                beginDiscard(container: proxy.size)
            }
            .onChange(of: tapRequest) { _, _ in
                guard isInteractionEnabled, !isShifting else { return }
                openFullscreen()
            }
            .onChange(of: vaultRequest) { _, _ in
                guard isInteractionEnabled, !isShifting else { return }
                beginFlight(to: .vault, container: proxy.size)
            }
            .onChange(of: favoriteRequest) { _, _ in
                guard isInteractionEnabled, !isShifting else { return }
                beginFlight(to: .favorite, container: proxy.size)
            }
            .task(id: prefetchKey) {
                thumbnails.startPrefetching(
                    ids: stackEntries.map(\.id),
                    targetSize: prefetchTargetSize(baseSide: baseSide)
                )
            }
            .onDisappear {
                thumbnails.stopPrefetching()
            }
        }
    }

    // MARK: - 尺寸

    private var paperMarginY: CGFloat {
        StageStackPolicy.paperTop + StageStackPolicy.paperBottom
    }

    /// 等面积基准边长 S：只取决于舞台容器，与当前这张的方向无关。
    ///
    /// - 宽度上限：S × 0.72，保证 4:3 长边（S×2/√3 ≈ 1.155S）旋转 ±15° 后
    ///   仍落在中栏宽度内；
    /// - 高度上限：竖卡内容高 = S×2/√3，加上相纸下巴与最深露出后不超过舞台 90%；
    /// - 下限：S = 88（4:3 卡宽约 102pt），窄屏中栏最小 120pt 时也不会溢出。
    private func stackBaseSide(in container: CGSize) -> CGFloat {
        let widthLimit = max(0, container.width * StageStackPolicy.stackBaseRatio)
        let maxContentHeight = max(
            0,
            container.height * StageStackPolicy.stackHeightRatio
                - paperMarginY
                - StageStackPolicy.maxDepthReveal
        )
        let heightLimit = maxContentHeight / StageStackPolicy.equalAreaLongRatio
        let natural = min(widthLimit, heightLimit)
        guard widthLimit > 0, natural > 0 else {
            return StageStackPolicy.minStackBaseSide
        }
        // 下限只用于“舞台过矮”的兜底，且永远不允许超过宽度上限。
        return max(1, min(max(natural, StageStackPolicy.minStackBaseSide), widthLimit))
    }

    /// 等面积内容框：横图 长×短（4:3），竖图 短×长（3:4），边长正好互换。
    private func contentSize(for item: PhotoItem, base: CGFloat) -> CGSize {
        if StageStackPolicy.isLandscape(item) {
            return CGSize(
                width: base * StageStackPolicy.equalAreaLongRatio,
                height: base * StageStackPolicy.equalAreaShortRatio
            )
        }
        return CGSize(
            width: base * StageStackPolicy.equalAreaShortRatio,
            height: base * StageStackPolicy.equalAreaLongRatio
        )
    }

    /// 卡片尺寸 = 内容框 + 相纸边距；高度随横竖变化，宽度也随横竖互换。
    private func cardSize(for item: PhotoItem, base: CGFloat) -> CGSize {
        let content = contentSize(for: item, base: base)
        return CGSize(width: content.width, height: content.height + paperMarginY)
    }

    /// 空舞台（没有素材比例可参考）时按横图盒兜底。
    private func fallbackCardSize(base: CGFloat) -> CGSize {
        CGSize(
            width: base * StageStackPolicy.equalAreaLongRatio,
            height: base * StageStackPolicy.equalAreaShortRatio + paperMarginY
        )
    }

    /// 竖卡最高，用它作为整叠的参考高度，保证任何横竖组合下锚点不变。
    private func referenceCardHeight(base: CGFloat) -> CGFloat {
        base * StageStackPolicy.equalAreaLongRatio + paperMarginY
    }

    /// 锚点取整叠最大外接框（最高竖卡 + 最深露出）的中心：
    /// 前排底边相对舞台中心的偏移固定为 (参考高 − 最深露出)/2。
    private func stackBaseline(referenceHeight: CGFloat) -> CGFloat {
        (referenceHeight - StageStackPolicy.maxDepthReveal) / 2
    }

    /// 预热按这一叠里最大的内容区域请求，横竖混合时也不会糊。
    private func prefetchTargetSize(baseSide: CGFloat) -> CGSize {
        let sizes = stackEntries.map { contentSize(for: $0.item, base: baseSide) }
        let maxWidth = max(1, sizes.map(\.width).max() ?? baseSide)
        let maxHeight = max(1, sizes.map(\.height).max() ?? baseSide)
        return CGSize(
            width: maxWidth * UIScreen.main.scale,
            height: maxHeight * UIScreen.main.scale
        )
    }

    // MARK: - 堆叠

    private func stack(baseSide: CGFloat, baseline: CGFloat) -> some View {
        // 升位瞬间底板要跟着换成“即将成为前排”的那一张的尺寸，
        // 否则横竖图混排时会露出旧尺寸多出来的相纸边。
        let backingSize = backingCardSize(baseSide: baseSide)

        return ZStack {
            // 不透明相纸底板：恒垫在前排卡正下方，跟随拖拽的位移与旋转。
            // 换牌时前排卡有一帧未就绪/透明，看到的也是相纸色，不会透出后面第三张；
            // 正常状态下它被前排卡完全盖住，不参与命中与无障碍。
            RoundedRectangle(cornerRadius: Theme.Polaroid.corner, style: .continuous)
                .fill(Theme.Polaroid.paper)
                .frame(width: backingSize.width, height: backingSize.height)
                .rotationEffect(.degrees(Double(dragOffset.width) * 0.05))
                // 底边钉在固定基准线上：底板高度变化时只向上长，不带动整叠。
                .offset(x: dragOffset.width, y: baseline - backingSize.height / 2 + dragOffset.height)
                .shadow(color: Theme.Polaroid.shadow, radius: 10, x: 0, y: 6)
                .zIndex(99.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ForEach(stackEntries) { entry in
                // 只有飞出卡仍占着 depth 0 时才整体前移一层；左右滑已提前移除，不偏移。
                let effectiveDepth = max(0, entry.depth - (isHoldingFrontPosition ? 1 : 0))
                let isFront = entry.depth == 0
                let entrySize = cardSize(for: entry.item, base: baseSide)
                let pose = pose(for: effectiveDepth, entryHeight: entrySize.height, baseline: baseline)

                PolaroidCardView(
                    item: entry.item,
                    thumbnails: thumbnails,
                    size: entrySize,
                    zoomScale: isFront ? zoomScale : 1,
                    panOffset: isFront ? panOffset : .zero,
                    reportsImage: isFront,
                    onImageLoaded: isFront ? { image in
                        frontThumbnail = FrontThumbnail(id: entry.item.id, image: image)
                    } : nil
                )
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(pose.angle))
                .rotationEffect(.degrees(isFront ? Double(dragOffset.width) * 0.05 : 0))
                .offset(
                    x: pose.x + (isFront ? dragOffset.width : 0),
                    y: pose.y + (isFront ? dragOffset.height : 0)
                )
                // 只隐藏“正在飞出的那一张”（按 asset 身份判断），而不是“当前前排”：
                // 左右滑在飞行一开始就由外部移除了这张，新前排必须立刻可见；
                // 若按位置隐藏，新前排会在整个飞行期间是透明的，露出后面的卡。
                .opacity(isShifting && entry.item.id == outgoing?.item.id ? 0 : 1)
                // 用升位后的深度排序：升上来的卡必须站到前排层，而不是被旧前排压住。
                .zIndex(Double(100 - effectiveDepth))
                .allowsHitTesting(isFront && isInteractionEnabled && !isShifting)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(!isFront)
                .accessibilityLabel(
                    "第 \(currentIndex + 1) 张，共 \(items.count) 张，\(entry.item.shortDateText)，\(entry.item.kind.displayName)"
                )
                .accessibilityHint("轻点全屏查看，上滑延后，下滑加入待销毁，左滑存入保险箱，右滑存入收藏夹")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "全屏查看") {
                    openFullscreen()
                }
                .accessibilityAction(named: "下一张照片") {
                    beginAdvance(container: stageContainerSize(for: entrySize))
                }
                .accessibilityAction(named: "加入待销毁") {
                    guard canDiscard else { return }
                    beginDiscard(container: stageContainerSize(for: entrySize))
                }
            }
        }
        .animation(Theme.Motion.animation(.standard, reduceMotion: reduceMotion), value: currentIndex)
        // 注意：不要给 isShifting 加动画。整叠升位若与旧前排的隐藏一起插值，
        // 中途会出现“前排半透明、后排还在路上”的帧，那正是穿透的来源。
        // 升位在同一帧内完成，动画只发生在顶层飞出卡上。
    }

    /// 底板尺寸：升位过程中取即将成为前排的那一张，其余时候取当前前排。
    /// 用 stackEntries 而不是 `items[currentIndex + 1]`：升位与本地的
    /// `isShifting = false` 在同一事务里提交，避免中间帧取到再下一张的尺寸。
    /// 换牌（轻点/上滑/下滑）时旧前排仍在列表里，真正要顶上来的是 depth 1；
    /// 左右滑在飞行开始时就已由外部移除，新前排已经是 depth 0。
    private var incomingFrontDepth: Int {
        isHoldingFrontPosition ? 1 : 0
    }

    private func backingCardSize(baseSide: CGFloat) -> CGSize {
        let target = stackEntries.first(where: { $0.depth == incomingFrontDepth })?.item
            ?? stackEntries.first?.item
        if let target {
            return cardSize(for: target, base: baseSide)
        }
        return fallbackCardSize(base: baseSide)
    }

    /// 无障碍动作拿不到容器的真实尺寸，用卡片尺寸作为近似飞行距离。
    private func stageContainerSize(for cardSize: CGSize) -> CGSize {
        CGSize(width: cardSize.width + 24, height: cardSize.height * 1.3)
    }

    /// 所有卡片共用一条固定底边基准：每深一层在基准线下方多露出常量高度。
    /// 关键点是不再依赖“当前前排高度”，所以 4:3 ↔ 3:4 换牌时后排完全不动。
    private func pose(for depth: Int, entryHeight: CGFloat, baseline: CGFloat) -> (angle: Double, x: CGFloat, y: CGFloat, scale: CGFloat) {
        let index = min(depth, StageStackPolicy.visibleDepth - 1)
        let scale = StageStackPolicy.depthScales[index]
        // 缩放是按卡片中心做的，若仍用原始高度的一半，后层底边会被缩放“吃掉”约 h×(1−scale)/2，
        // 露出量就不再等于 depthReveal。这里用缩放后的半高定位，保证每层露出严格为 0/22/26/30。
        let y = baseline + StageStackPolicy.depthReveal[index] - entryHeight * scale / 2
        return (
            StageStackPolicy.depthAngles[index],
            StageStackPolicy.depthShiftX[index],
            y,
            StageStackPolicy.depthScales[index]
        )
    }

    private var emptyStage: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.Text.tertiary)

            Text("这一批已经处理完")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)
                .multilineTextAlignment(.center)

            Text("正在统一加密与删除，请稍候")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 手势

    private func dragGesture(container: CGSize, cardSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard isInteractionEnabled, !isShifting else { return }

                if isZoomed {
                    let proposed = CGSize(
                        width: panBase.width + value.translation.width,
                        height: panBase.height + value.translation.height
                    )
                    panOffset = clampedPan(proposed, scale: zoomScale, cardSize: cardSize)
                    return
                }

                if dragAxis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) > 4 else { return }
                    dragAxis = dy > dx ? .vertical : .horizontal
                }

                switch dragAxis {
                case .vertical:
                    let dy = value.translation.height
                    if dy >= 0 {
                        // 下滑 = 入待销毁；正向拉伸有阻尼上限。
                        snoozePreviewDays = nil
                        dragOffset = CGSize(width: 0, height: stretched(dy))
                    } else {
                        // 上滑 = 延后；跟手实时算出目标天数并浮出提示。
                        let lift = min(-dy, SnoozePolicy.stretchLimit)
                        let days = SnoozePolicy.days(
                            translation: -dy,
                            predicted: -value.predictedEndTranslation.height
                        )
                        if snoozePreviewDays != days {
                            withAnimation(.easeOut(duration: 0.12)) {
                                snoozePreviewDays = days
                            }
                        }
                        dragOffset = CGSize(width: 0, height: -lift * 0.9)
                    }
                case .horizontal:
                    // 左右滑用于投入两侧实体，跟手位移不做过度阻尼。
                    snoozePreviewDays = nil
                    dragOffset = CGSize(width: value.translation.width * 0.78, height: 0)
                case .none:
                    break
                }
            }
            .onEnded { value in
                guard isInteractionEnabled, !isShifting else {
                    reboundDrag()
                    return
                }

                if isZoomed {
                    panBase = panOffset
                    return
                }

                let axis = dragAxis
                dragAxis = nil

                switch axis {
                case .vertical:
                    // 方向已在起点裁决：向上只可能是延后，向下只可能是待销毁。
                    if shouldSnooze(value) {
                        beginSnooze(days: snoozePreviewDays ?? 1, container: container)
                    } else if shouldDiscard(value) {
                        beginDiscard(container: container)
                    } else {
                        snoozePreviewDays = nil
                        reboundDrag()
                    }
                case .horizontal:
                    if let side = committedSide(value) {
                        beginFlight(to: side, container: container)
                    } else {
                        reboundDrag()
                    }
                case .none:
                    reboundDrag()
                }
            }
    }

    /// 左滑 = 保险箱，右滑 = 收藏夹；首尾不再有横滑翻页。
    private func committedSide(_ value: DragGesture.Value) -> FlightSide? {
        let dx = value.translation.width
        let predicted = value.predictedEndTranslation.width
        let commit = StageStackPolicy.sideCommitDistance
        let flick = StageStackPolicy.sideFlickPrediction

        if dx <= -commit || predicted <= -flick { return .vault }
        if dx >= commit || predicted >= flick { return .favorite }
        return nil
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard isInteractionEnabled, !isShifting else { return }
                zoomScale = min(4, max(1, zoomBase * value.magnification))
            }
            .onEnded { _ in
                zoomBase = zoomScale
                if zoomScale < 1.06 {
                    resetZoom(animated: true)
                }
            }
    }

    private func stretched(_ dy: CGFloat) -> CGFloat {
        guard dy > StageStackPolicy.discardStretchLimit else { return dy }
        return StageStackPolicy.discardStretchLimit
            + (dy - StageStackPolicy.discardStretchLimit) * 0.25
    }

    private func shouldDiscard(_ value: DragGesture.Value) -> Bool {
        let dy = value.translation.height
        let predicted = value.predictedEndTranslation.height
        if dy > StageStackPolicy.discardCommitDistance { return true }
        return dy > 24 && predicted > StageStackPolicy.discardCommitDistance * 1.8
    }

    private func reboundDrag() {
        snoozePreviewDays = nil
        withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
            dragOffset = .zero
        }
    }

    /// 上滑提交：距离达到阈值，或“距离 + 甩动预测”达标。
    private func shouldSnooze(_ value: DragGesture.Value) -> Bool {
        let up = -value.translation.height
        let predictedUp = -value.predictedEndTranslation.height
        guard up > 0 else { return false }
        if up >= SnoozePolicy.commitDistance { return true }
        return up > 24 && predictedUp >= SnoozePolicy.commitDistance * 1.4
    }

    private func openFullscreen() {
        guard isInteractionEnabled, !isShifting, !isZoomed, let item = currentItem else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpenFullscreen(item.id)
    }

    private func snoozeBadge(days: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
            Text("延后 \(days) 天")
                .font(Theme.Typography.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Theme.Text.primary)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 28)
        .neuSurface(.raisedSmall, cornerRadius: Theme.Radius.chip)
    }

    private func clampedPan(_ value: CGSize, scale: CGFloat, cardSize: CGSize) -> CGSize {
        let maxX = max(0, cardSize.width * (scale - 1) / 2) * 0.85
        let maxY = max(0, cardSize.height * (scale - 1) / 2) * 0.85
        return CGSize(
            width: min(max(value.width, -maxX), maxX),
            height: min(max(value.height, -maxY), maxY)
        )
    }

    private func resetZoom(animated: Bool) {
        let apply = {
            zoomScale = 1
            zoomBase = 1
            panOffset = .zero
            panBase = .zero
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), apply)
        } else {
            apply()
        }
    }

    // MARK: - 动作

    /// 轻点：当前照片先放大到 120%，再向上飞出；下面一张同时成为新当前。
    private func beginAdvance(container: CGSize) {
        guard isInteractionEnabled, !isShifting else { return }
        guard let item = currentItem else { return }
        guard currentIndex + 1 < items.count else {
            // 最后一张也要能被“下一张”决定为保留，否则任务无法收尾。
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                dragOffset = CGSize(width: 8, height: 0)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                reboundDrag()
                onAdvance(item.id)
            }
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let start = dragOffset
        dragOffset = .zero
        snoozePreviewDays = nil
        isShifting = true
        outgoing = OutgoingCard(item: item, image: cachedThumbnail(for: item))
        outgoingOffset = start
        outgoingScale = 1
        outgoingOpacity = 1

        withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.18)) {
            outgoingScale = 1.2
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 170))
            withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.3)) {
                // 只在位移上做过渡，全程保持 100% 不透明：
                // 淡出会让下一层的卡（以及更后面那张）在重叠区透出来。
                outgoingOffset = CGSize(width: 0, height: -(container.height + 320))
            }

            try? await Task.sleep(for: .milliseconds(reduceMotion ? 190 : 290))
            // 升位与“结束换牌”必须在同一事务提交：中间不能有一帧
            // “已是新下标 + 仍在升位”的状态，那会让再下一张也被抬到前排层。
            onAdvance(item.id)
            isShifting = false
            outgoing = nil
            outgoingOffset = .zero
            outgoingScale = 1
            outgoingOpacity = 1
        }
    }

    /// 上滑：照片向上飞出舞台，交给外部落库延后。
    private func beginSnooze(days: Int, container: CGSize) {
        guard isInteractionEnabled, !isShifting else { return }
        guard let item = currentItem else { return }

        let clamped = min(SnoozePolicy.maxDays, max(SnoozePolicy.minDays, days))

        resetZoom(animated: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let start = dragOffset
        dragOffset = .zero
        snoozePreviewDays = nil
        isShifting = true
        outgoing = OutgoingCard(item: item, image: cachedThumbnail(for: item))
        outgoingOffset = start
        outgoingScale = 1
        outgoingOpacity = 1

        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : 0.3)) {
            outgoingOffset = CGSize(width: 0, height: -(container.height + 260))
            outgoingScale = 0.86
            outgoingOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 300))
            onSnooze(item.id, clamped)
            // 与换牌同理：外部移除素材与本地结束升位同事务，不留双前排帧。
            isShifting = false
            outgoing = nil
            outgoingOffset = .zero
            outgoingScale = 1
            outgoingOpacity = 1
        }
    }

    /// 下滑：当前照片飞入底部处理口，同时迸发粒子，交给外部加入待销毁累积。
    private func beginDiscard(container: CGSize) {
        guard isInteractionEnabled, !isShifting, canDiscard else { return }
        guard let item = currentItem else { return }

        resetZoom(animated: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let start = dragOffset
        dragOffset = .zero
        snoozePreviewDays = nil
        isShifting = true
        outgoing = OutgoingCard(item: item, image: cachedThumbnail(for: item))
        outgoingOffset = start
        outgoingScale = 1
        outgoingOpacity = 1
        burstToken += 1

        withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.34)) {
            outgoingOffset = CGSize(width: start.width, height: container.height + 260)
            outgoingScale = 0.76
            outgoingOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 340))
            onDiscard(item.id)
            // 与换牌同理：外部移除素材与本地结束升位同事务，不留双前排帧。
            isShifting = false
            outgoing = nil
            outgoingOffset = .zero
            outgoingScale = 1
            outgoingOpacity = 1
        }
    }

    /// 左右滑：照片向保险箱门 / 收藏夹卡片飞去，同时通知外部开门与执行存入。
    private func beginFlight(to side: FlightSide, container: CGSize) {
        guard isInteractionEnabled, !isShifting else { return }
        guard let item = currentItem else { return }

        if side == .favorite, !canFavorite {
            reboundDrag()
            onFavoriteRejected()
            return
        }

        resetZoom(animated: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let start = dragOffset
        dragOffset = .zero
        isShifting = true
        outgoing = OutgoingCard(item: item, image: cachedThumbnail(for: item))
        outgoingOffset = start
        outgoingScale = 1
        outgoingOpacity = 1

        // 先通知外部开门/选中，门与照片同时动起来。
        switch side {
        case .vault:
            onVaultStore(item.id)
        case .favorite:
            onFavoriteStore(item.id)
        }

        let horizontalTarget = container.width / 2 + sideDropOffset
        // 与换牌一致：飞出卡全程 100% 不透明，只做位移与缩放。
        // 任何淡出都会在它离开前排位置的过程中露出下面那张，正是左右滑独有闪烁的来源。
        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : 0.3)) {
            outgoingOffset = CGSize(
                width: side == .vault ? -horizontalTarget : horizontalTarget,
                height: start.height + 36
            )
            outgoingScale = 0.7
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 320))
            isShifting = false
            outgoing = nil
            outgoingOffset = .zero
            outgoingScale = 1
            outgoingOpacity = 1
        }
    }
}

// MARK: - 拍立得卡片

/// 相纸卡片：按素材横竖归一到 4:3 / 3:4 裁切填充，圆润白边 + 底部“下巴”。
private struct PolaroidCardView: View {
    let item: PhotoItem
    let thumbnails: ThumbnailProvider
    let size: CGSize
    var zoomScale: CGFloat = 1
    var panOffset: CGSize = .zero
    var cachedImage: UIImage? = nil
    /// 本卡是否处于舞台前排；变为前排时补报一次已有缩略图，避免父层继续使用上一张的图。
    var reportsImage: Bool = false
    var onImageLoaded: ((UIImage) -> Void)? = nil

    @State private var loaded: LoadedThumbnail?
    @State private var failed = false

    /// 加载完成的缩略图与 asset ID 一起保存；ID 不匹配时不显示。
    private struct LoadedThumbnail {
        let id: String
        let image: UIImage
    }

    private var displayImage: UIImage? {
        if let loaded, loaded.id == item.id { return loaded.image }
        return cachedImage
    }

    private var contentSize: CGSize {
        CGSize(
            width: max(1, size.width - StageStackPolicy.paperSide * 2),
            height: max(1, size.height - StageStackPolicy.paperTop - StageStackPolicy.paperBottom)
        )
    }

    var body: some View {
        ZStack {
            Theme.Polaroid.paper

            ZStack {
                Theme.Polaroid.paper

                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        // 缩略图已按目标比例裁切；这里再兜一层填充裁切，避免留白。
                        .scaledToFill()
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                } else if failed {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Theme.Text.tertiary)
                } else {
                    ProgressView()
                        .tint(Theme.Text.tertiary)
                }
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.Polaroid.photoCorner, style: .continuous)
            )
            .offset(y: (StageStackPolicy.paperTop - StageStackPolicy.paperBottom) / 2)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Polaroid.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Polaroid.corner, style: .continuous)
                .strokeBorder(Theme.Polaroid.edge, lineWidth: 0.8)
        }
        .shadow(color: Theme.Polaroid.shadow, radius: 10, x: 0, y: 6)
        .task(id: item.id) {
            let requestID = item.id
            failed = false

            if let cachedImage {
                loaded = LoadedThumbnail(id: requestID, image: cachedImage)
                reportImage()
                return
            }

            let target = CGSize(
                width: contentSize.width * UIScreen.main.scale,
                height: contentSize.height * UIScreen.main.scale
            )
            let result = await thumbnails.image(for: requestID, targetSize: target)

            // 回调可能晚于换牌：请求的 asset 必须仍是本卡，且任务未被取消才写入。
            guard !Task.isCancelled, requestID == item.id else { return }
            guard let result else {
                failed = true
                return
            }
            loaded = LoadedThumbnail(id: requestID, image: result)
            reportImage()
        }
        // 从后排升到前排、或图片晚到时补报一次，保证父层缓存的缩略图始终属于当前 asset。
        .onChange(of: reportsImage) { _, _ in
            reportImage()
        }
        .onChange(of: loaded?.id) { _, _ in
            reportImage()
        }
    }

    /// 仅在处于前排且图片确实属于本卡时上报。
    private func reportImage() {
        guard reportsImage, let loaded, loaded.id == item.id else { return }
        onImageLoaded?(loaded.image)
    }
}

// MARK: - 粒子

private struct PhotoParticleBurst: View {
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0
    private let particles: [BurstParticle]

    init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        self.particles = (0..<(reduceMotion ? 10 : 26)).map { _ in BurstParticle.random() }
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: particle.dx * progress,
                        y: particle.dy * progress + 34 * progress * progress
                    )
                    .opacity(Double(max(0, 1 - progress)))
                    .scaleEffect(max(0.3, 1 - 0.4 * progress))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.18 : 0.62)) {
                progress = 1
            }
        }
    }
}

private struct BurstParticle: Identifiable {
    let id = UUID()
    let dx: CGFloat
    let dy: CGFloat
    let size: CGFloat
    let color: Color

    static func random() -> BurstParticle {
        let angle = Double.random(in: -165 ... -15) * .pi / 180
        let speed = CGFloat.random(in: 34 ... 118)
        let palette = [Theme.Accent.fire, Theme.Accent.ember, Theme.Text.tertiary]
        return BurstParticle(
            dx: cos(angle) * speed,
            dy: sin(angle) * speed,
            size: CGFloat.random(in: 2 ... 6),
            color: palette.randomElement() ?? Theme.Accent.fire
        )
    }
}
