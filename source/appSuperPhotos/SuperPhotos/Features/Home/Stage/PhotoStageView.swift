import SwiftUI
import UIKit

/// 舞台堆叠与手势参数：一次展示 4 张拍立得，轻点换牌 / 下滑销毁 / 左右滑入两侧实体。
enum StageStackPolicy {
    /// 当前照片之后同时露出的层数（含当前共 4 张）。
    static let visibleDepth = 4
    /// 各层旋转角度（正数顺时针）：0° / 左 15° / 右 10° / 左 5°，形成随手一叠的错落感。
    static let depthAngles: [Double] = [0, -15, 10, -5]
    /// 各层偏移：越靠后越向下、向外散开，避免机械对齐。
    static let depthOffsets: [CGSize] = [
        .zero,
        CGSize(width: -7, height: 11),
        CGSize(width: 9, height: 17),
        CGSize(width: -13, height: 23)
    ]
    /// 各层缩放：后层略小，强化“一叠相纸”的层次。
    static let depthScales: [CGFloat] = [1, 0.985, 0.97, 0.955]
    /// 相纸边距：左右 / 上 / 下（底部留出拍立得的“下巴”）。
    static let paperSide: CGFloat = 9
    static let paperTop: CGFloat = 9
    static let paperBottom: CGFloat = 24
    /// 卡片宽高比（宽 / 高）；照片按自身比例缩进相纸，多出的部分即边距。
    static let cardAspect: CGFloat = 0.75
    /// 下滑提交阈值；不足则弹簧回弹。
    static let discardCommitDistance: CGFloat = 96
    /// 跟手阶段的最大拉伸；超出后按 1/4 阻尼继续。
    static let discardStretchLimit: CGFloat = 180
    /// 左右滑提交距离与甩动预测。
    static let sideCommitDistance: CGFloat = 64
    static let sideFlickPrediction: CGFloat = 120
}

/// 舞台：拍立得叠放 + 轻点换牌 + 下滑入待销毁 + 左滑入保险箱 + 右滑入收藏夹 + 捏合缩放。
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
    /// 左右滑飞出距离：约等于舞台半宽 + 侧栏宽 + 间距。
    let sideDropOffset: CGFloat

    var onAdvance: (String) -> Void
    var onVaultStore: (String) -> Void
    var onFavoriteStore: (String) -> Void
    var onFavoriteRejected: () -> Void
    var onDiscard: (String) -> Void
    var onZoomChanged: (Bool, CGFloat) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: DragAxis?
    @State private var isShifting = false

    @State private var outgoing: OutgoingCard?
    @State private var outgoingOffset: CGSize = .zero
    @State private var outgoingScale: CGFloat = 1
    @State private var outgoingOpacity: Double = 1
    @State private var frontImage: UIImage?
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

    var body: some View {
        GeometryReader { proxy in
            let cardSize = fitCardSize(in: proxy.size)

            ZStack {
                if currentItem == nil {
                    emptyStage
                } else {
                    stack(cardSize: cardSize)
                }

                if let outgoing {
                    PolaroidCardView(
                        item: outgoing.item,
                        thumbnails: thumbnails,
                        size: cardSize,
                        cachedImage: outgoing.image
                    )
                    .scaleEffect(outgoingScale)
                    .offset(outgoingOffset)
                    .opacity(outgoingOpacity)
                    .zIndex(12)
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
            .gesture(dragGesture(container: proxy.size, cardSize: cardSize))
            // 轻点由容器统一接管：避免首帧/层叠状态下单张卡片的命中被判给错误图层。
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard isInteractionEnabled, !isShifting, !isZoomed else { return }
                    beginAdvance(container: proxy.size)
                }
            )
            .simultaneousGesture(magnifyGesture)
            .onChange(of: zoomScale) { _, scale in
                onZoomChanged(scale > 1.01, scale)
                if scale <= 1.01 {
                    panOffset = .zero
                    panBase = .zero
                }
            }
            .onChange(of: currentIndex) { _, _ in
                frontImage = nil
                resetZoom(animated: false)
            }
            .onChange(of: discardRequest) { _, _ in
                guard isInteractionEnabled, !isShifting else { return }
                beginDiscard(container: proxy.size)
            }
            .onChange(of: tapRequest) { _, _ in
                guard isInteractionEnabled, !isShifting else { return }
                beginAdvance(container: proxy.size)
            }
            .task(id: prefetchKey) {
                thumbnails.startPrefetching(
                    ids: stackEntries.map(\.id),
                    targetSize: CGSize(
                        width: cardSize.width * UIScreen.main.scale,
                        height: cardSize.height * UIScreen.main.scale
                    )
                )
            }
            .onDisappear {
                thumbnails.stopPrefetching()
            }
        }
    }

    // MARK: - 尺寸

    /// 相纸卡片等比适配可用区域；留出旋转与散开偏移的空间。
    private func fitCardSize(in container: CGSize) -> CGSize {
        let aspect = StageStackPolicy.cardAspect
        // 0.86 是给 ±15° 旋转留出的余量：后层只会轻微压到两栏边缘，不会被裁切。
        let maxWidth = max(72, container.width * 0.86)
        let maxHeight = max(96, container.height * 0.88)
        let width = min(maxWidth, maxHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    // MARK: - 堆叠

    private func stack(cardSize: CGSize) -> some View {
        ZStack {
            ForEach(stackEntries) { entry in
                let effectiveDepth = max(0, entry.depth - (isShifting ? 1 : 0))
                let isFront = entry.depth == 0
                let pose = pose(for: effectiveDepth)

                PolaroidCardView(
                    item: entry.item,
                    thumbnails: thumbnails,
                    size: cardSize,
                    zoomScale: isFront ? zoomScale : 1,
                    panOffset: isFront ? panOffset : .zero,
                    onImageLoaded: isFront ? { image in
                        if entry.item.id == currentItem?.id {
                            frontImage = image
                        }
                    } : nil
                )
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(pose.angle))
                .rotationEffect(.degrees(isFront ? Double(dragOffset.width) * 0.05 : 0))
                .offset(
                    x: pose.offset.width + (isFront ? dragOffset.width : 0),
                    y: pose.offset.height + (isFront ? dragOffset.height : 0)
                )
                .opacity(isFront && isShifting ? 0 : 1)
                .zIndex(Double(100 - entry.depth))
                .allowsHitTesting(isFront && isInteractionEnabled && !isShifting)
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(!isFront)
                .accessibilityLabel(
                    "第 \(currentIndex + 1) 张，共 \(items.count) 张，\(entry.item.shortDateText)，\(entry.item.kind.displayName)"
                )
                .accessibilityHint("轻点看下一张，下滑加入待销毁，左滑存入保险箱，右滑存入收藏夹")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "加入待销毁") {
                    guard canDiscard else { return }
                    beginDiscard(container: stageContainerSize(for: cardSize))
                }
            }
        }
        .animation(Theme.Motion.animation(.standard, reduceMotion: reduceMotion), value: currentIndex)
        .animation(Theme.Motion.animation(.standard, reduceMotion: reduceMotion), value: isShifting)
    }

    /// 无障碍动作拿不到容器的真实尺寸，用卡片尺寸的 3 倍高度作为近似飞行距离。
    private func stageContainerSize(for cardSize: CGSize) -> CGSize {
        CGSize(width: cardSize.width + 24, height: cardSize.height * 1.3)
    }

    private func pose(for depth: Int) -> (angle: Double, offset: CGSize, scale: CGFloat) {
        let index = min(depth, StageStackPolicy.visibleDepth - 1)
        return (
            StageStackPolicy.depthAngles[index],
            StageStackPolicy.depthOffsets[index],
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

            Text("点底部“销毁”确认，或清空待销毁累积")
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
                    dragOffset = CGSize(width: 0, height: dy > 0 ? stretched(dy) : dy * 0.15)
                case .horizontal:
                    // 左右滑用于投入两侧实体，跟手位移不做过度阻尼。
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
                    if shouldDiscard(value) {
                        beginDiscard(container: container)
                    } else {
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
        withAnimation(Theme.Motion.animation(.spring, reduceMotion: reduceMotion)) {
            dragOffset = .zero
        }
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                dragOffset = CGSize(width: 8, height: 0)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                reboundDrag()
            }
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let start = dragOffset
        dragOffset = .zero
        isShifting = true
        outgoing = OutgoingCard(item: item, image: frontImage)
        outgoingOffset = start
        outgoingScale = 1
        outgoingOpacity = 1

        withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.18)) {
            outgoingScale = 1.2
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 60 : 170))
            withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.3)) {
                outgoingOffset = CGSize(width: 0, height: -(container.height + 320))
                outgoingOpacity = 0
            }

            try? await Task.sleep(for: .milliseconds(reduceMotion ? 190 : 290))
            onAdvance(item.id)
            await Task.yield()

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
        isShifting = true
        outgoing = OutgoingCard(item: item, image: frontImage)
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
            await Task.yield()

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
        outgoing = OutgoingCard(item: item, image: frontImage)
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
        withAnimation(.easeIn(duration: reduceMotion ? 0.18 : 0.3)) {
            outgoingOffset = CGSize(
                width: side == .vault ? -horizontalTarget : horizontalTarget,
                height: start.height + 36
            )
            outgoingScale = 0.7
            outgoingOpacity = 0
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

/// 相纸卡片：主题色边距 + 按原比例缩进的照片，底部留出拍立得的“下巴”。
private struct PolaroidCardView: View {
    let item: PhotoItem
    let thumbnails: ThumbnailProvider
    let size: CGSize
    var zoomScale: CGFloat = 1
    var panOffset: CGSize = .zero
    var cachedImage: UIImage? = nil
    var onImageLoaded: ((UIImage) -> Void)? = nil

    @State private var image: UIImage?
    @State private var failed = false

    private var displayImage: UIImage? { image ?? cachedImage }

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
                        .scaledToFit()
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
            .clipped()
            .offset(y: (StageStackPolicy.paperTop - StageStackPolicy.paperBottom) / 2)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.Polaroid.edge, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
        .task(id: item.id) {
            if let cachedImage {
                image = cachedImage
                onImageLoaded?(cachedImage)
                return
            }
            let target = CGSize(
                width: contentSize.width * UIScreen.main.scale,
                height: contentSize.height * UIScreen.main.scale
            )
            if let loaded = await thumbnails.image(for: item.id, targetSize: target) {
                image = loaded
                onImageLoaded?(loaded)
            } else {
                failed = true
            }
        }
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
